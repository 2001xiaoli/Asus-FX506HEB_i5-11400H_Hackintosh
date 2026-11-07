/*
 * vdacheck.c - 实证本机 VDA / VideoToolbox 硬件解码能力
 *
 * 做法：用 VideoToolbox 自己编码一段测试码流（不依赖外部素材），
 *      再用三种模式去解：
 *        B. 强制硬解 (RequireHardwareAcceleratedVideoDecoder)
 *        C. 允许软解回落 (EnableHardwareAcceleratedVideoDecoder)
 *      并读取 UsingHardwareAcceleratedVideoDecoder 实际取值。
 *
 * 编译：
 *   clang -O1 -o tools/vdacheck tools/vdacheck.c \
 *     -framework VideoToolbox -framework CoreVideo -framework CoreMedia \
 *     -framework CoreFoundation
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <dlfcn.h>
#include <sys/resource.h>
#include <time.h>

#include <VideoToolbox/VideoToolbox.h>
#include <CoreVideo/CoreVideo.h>
#include <CoreMedia/CoreMedia.h>

#define ENC_W 1280
#define ENC_H 720
#define ENC_FRAMES 12
#define MAXS 64

#define CODEC_H264 0x61766331 /* 'avc1' */
#define CODEC_HEVC 0x68766331 /* 'hvc1' */
#define CODEC_VP9  0x76703039 /* 'vp09' */
#define CODEC_AV1  0x61763031 /* 'av01' */

static CMSampleBufferRef gS[MAXS];
static int gN = 0;

typedef Boolean (*VTIsHWDecodeFn)(CMVideoCodecType);

static const char *cname(CMVideoCodecType t)
{
    if (t == CODEC_H264) return "H.264";
    if (t == CODEC_HEVC) return "HEVC ";
    if (t == CODEC_VP9)  return "VP9  ";
    if (t == CODEC_AV1)  return "AV1  ";
    return "?????";
}

static void printStatus(OSStatus st)
{
    if (st == 0) { printf("noErr"); return; }
    if (st > -200000 && st < 0) {
        printf("%d", (int)st);
        return;
    }
    char s[5];
    s[0] = (char)((st >> 24) & 0xff);
    s[1] = (char)((st >> 16) & 0xff);
    s[2] = (char)((st >> 8) & 0xff);
    s[3] = (char)(st & 0xff);
    s[4] = 0;
    int printable = 1;
    for (int i = 0; i < 4; i++) {
        if (s[i] < 0x20 || s[i] > 0x7e) printable = 0;
    }
    if (printable) printf("%d ('%s')", (int)st, s);
    else printf("%d", (int)st);
}

static void enc_cb(void *refCon, void *srcRef, OSStatus status,
                   VTEncodeInfoFlags flags, CMSampleBufferRef sb)
{
    (void)refCon; (void)srcRef; (void)flags;
    if (status == noErr && sb != NULL && gN < MAXS) {
        gS[gN++] = (CMSampleBufferRef)CFRetain(sb);
    }
}

/* 用 VT 编码器生成一段码流，返回首帧的 format description；失败返回 NULL */
static CMFormatDescriptionRef makeStream(CMVideoCodecType codec, int w, int h, int nframes)
{
    for (int i = 0; i < gN; i++) {
        if (gS[i]) { CFRelease(gS[i]); gS[i] = NULL; }
    }
    gN = 0;

    VTCompressionSessionRef enc = NULL;
    OSStatus st = VTCompressionSessionCreate(kCFAllocatorDefault, w, h, codec,
                                             NULL, NULL, NULL, enc_cb, NULL, &enc);
    if (st != noErr) {
        printf("    (编码器创建失败: ");
        printStatus(st);
        printf("，跳过实解码)\n");
        return NULL;
    }

    VTSessionSetProperty(enc, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(enc, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);

    for (int i = 0; i < nframes; i++) {
        CVPixelBufferRef pb = NULL;
        if (CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                kCVPixelFormatType_32BGRA, NULL, &pb) != kCVReturnSuccess) {
            break;
        }
        CVPixelBufferLockBaseAddress(pb, 0);
        uint8_t *base = (uint8_t *)CVPixelBufferGetBaseAddress(pb);
        size_t bpr = CVPixelBufferGetBytesPerRow(pb);
        for (int y = 0; y < h; y++) {
            uint8_t *row = base + (size_t)y * bpr;
            for (int x = 0; x < w; x++) {
                uint8_t *p = row + (size_t)x * 4;
                p[0] = (uint8_t)((x + i * 16) & 0xff);
                p[1] = (uint8_t)(y & 0xff);
                p[2] = (uint8_t)((x ^ y) & 0xff);
                p[3] = 255;
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, 0);

        CMTime pts = CMTimeMake(i, 30);
        VTCompressionSessionEncodeFrame(enc, pb, pts, CMTimeMake(1, 30),
                                       NULL, NULL, NULL);
        CVPixelBufferRelease(pb);
    }
    VTCompressionSessionCompleteFrames(enc, kCMTimeInvalid);

    CMFormatDescriptionRef fmt = NULL;
    if (gN > 0) {
        fmt = (CMFormatDescriptionRef)CFRetain(CMSampleBufferGetFormatDescription(gS[0]));
    }
    VTCompressionSessionInvalidate(enc);
    CFRelease(enc);
    return fmt;
}

/* 记录解码后的实际属性 */
static CFBooleanRef gUsedHW = NULL;

static void dec_cb(void *decompressionOutputRefCon, void *srcRef, OSStatus status,
                   VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer,
                   CMTime pts, CMTime dur)
{
    (void)decompressionOutputRefCon; (void)srcRef; (void)status;
    (void)infoFlags; (void)imageBuffer; (void)pts; (void)dur;
}

static int gDecoded = 0;
static OSStatus gDecStatus = 0;

static void dec_cb_count(void *refCon, void *srcRef, OSStatus status,
                         VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer,
                         CMTime pts, CMTime dur)
{
    (void)refCon; (void)srcRef; (void)infoFlags; (void)imageBuffer; (void)pts; (void)dur;
    gDecStatus = status;
    if (status == noErr) gDecoded++;
}

/*
 * mode: 0 = 强制硬解, 1 = 允许软解回落
 * 返回 1 表示成功创建并解码
 */
static int tryDecode(CMFormatDescriptionRef fmt, int mode, const char *label)
{
    CFMutableDictionaryRef spec = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (mode == 0) {
        CFDictionarySetValue(spec, CFSTR("RequireHardwareAcceleratedVideoDecoder"), kCFBooleanTrue);
    } else {
        CFDictionarySetValue(spec, CFSTR("EnableHardwareAcceleratedVideoDecoder"), kCFBooleanTrue);
    }

    VTDecompressionOutputCallbackRecord rec;
    rec.decompressionOutputCallback = dec_cb_count;
    rec.decompressionOutputRefCon = NULL;

    VTDecompressionSessionRef dec = NULL;
    OSStatus st = VTDecompressionSessionCreate(kCFAllocatorDefault, fmt, spec,
                                               NULL, &rec, &dec);
    CFRelease(spec);

    printf("    %-14s ", label);
    if (st != noErr) {
        printf("→ session 创建失败 (");
        printStatus(st);
        printf(")\n");
        return 0;
    }

    gDecoded = 0;
    gDecStatus = 0;
    VTDecodeFrameFlags flags = 0;
    VTDecodeInfoFlags info = 0;
    st = VTDecompressionSessionDecodeFrame(dec, gS[0], flags, NULL, &info);
    if (st != noErr) {
        printf("→ DecodeFrame 失败 (");
        printStatus(st);
        printf(")\n");
        VTDecompressionSessionInvalidate(dec);
        CFRelease(dec);
        return 0;
    }
    VTDecompressionSessionWaitForAsynchronousFrames(dec);

    CFBooleanRef usedHW = NULL;
    VTSessionCopyProperty(dec, CFSTR("UsingHardwareAcceleratedVideoDecoder"),
                          kCFAllocatorDefault, &usedHW);
    CFBooleanRef fallback = NULL;
    VTSessionCopyProperty(dec, CFSTR("UsingSandboxedDecoder"),
                          kCFAllocatorDefault, &fallback);

    printf("→ 解码成功，UsingHardwareAccelerated = %s",
           usedHW ? (CFBooleanGetValue(usedHW) ? "YES   ★真硬解" : "NO    （软件解码）")
                  : "(属性不可读)");
    if (gDecStatus != noErr) {
        printf("  [回调状态 ");
        printStatus(gDecStatus);
        printf("]");
    }
    printf("\n");

    if (usedHW) CFRelease(usedHW);
    if (fallback) CFRelease(fallback);

    /* 调试用：让 session 存活一段时间，便于外部 lsof 观察真正加载的解码器 */
    const char *hold = getenv("VDACHECK_HOLD");
    if (hold && atoi(hold) > 0) {
        printf("    [保持 session %ds，供外部观察]", atoi(hold));
        fflush(stdout);
        sleep(atoi(hold));
        printf(" 结束\n");
    }

    VTDecompressionSessionInvalidate(dec);
    CFRelease(dec);
    return 1;
}

static double now_sec(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static double cpu_sec(void)
{
    struct rusage ru;
    getrusage(RUSAGE_SELF, &ru);
    return (double)ru.ru_utime.tv_sec + (double)ru.ru_utime.tv_usec / 1e6
         + (double)ru.ru_stime.tv_sec + (double)ru.ru_stime.tv_usec / 1e6;
}

/* 串行单帧延迟基准：每帧投递后立即等待，反映单帧解码成本 */
static void bench(CMVideoCodecType codec, int w, int h, int nframes, int loops, int allowHW)
{
    printf("[D] %s %dx%d  串行解码延迟 (%d 帧 × %d 轮, %s)\n",
           cname(codec), w, h, nframes, loops, allowHW ? "允许硬件" : "禁用硬件");

    CMFormatDescriptionRef fmt = makeStream(codec, w, h, nframes);
    if (!fmt) { printf("    码流生成失败，跳过\n\n"); return; }
    if (gN == 0) { CFRelease(fmt); printf("    无码流\n\n"); return; }

    CFMutableDictionaryRef spec = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(spec, CFSTR("EnableHardwareAcceleratedVideoDecoder"),
                         allowHW ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionarySetValue(spec, CFSTR("RequireHardwareAcceleratedVideoDecoder"),
                         allowHW ? kCFBooleanFalse : kCFBooleanFalse);

    VTDecompressionOutputCallbackRecord rec;
    rec.decompressionOutputCallback = dec_cb_count;
    rec.decompressionOutputRefCon = NULL;

    VTDecompressionSessionRef dec = NULL;
    OSStatus st = VTDecompressionSessionCreate(kCFAllocatorDefault, fmt, spec, NULL, &rec, &dec);
    CFRelease(spec);
    if (st != noErr) {
        printf("    session 创建失败\n\n");
        CFRelease(fmt);
        return;
    }

    CFBooleanRef actualHW = NULL;
    VTSessionCopyProperty(dec, CFSTR("UsingHardwareAcceleratedVideoDecoder"),
                          kCFAllocatorDefault, &actualHW);
    printf("    session 自报 UsingHardwareAccelerated = %s\n",
           actualHW ? (CFBooleanGetValue(actualHW) ? "YES" : "NO") : "(不可读)");
    if (actualHW) CFRelease(actualHW);

    /* 预热 */
    for (int i = 0; i < gN; i++) {
        VTDecompressionSessionDecodeFrame(dec, gS[i], 0, NULL, NULL);
    }
    VTDecompressionSessionWaitForAsynchronousFrames(dec);

    double t0 = now_sec(), c0 = cpu_sec();
    int done = 0;
    for (int l = 0; l < loops; l++) {
        for (int i = 0; i < gN; i++) {
            VTDecompressionSessionDecodeFrame(dec, gS[i], 0, NULL, NULL);
            VTDecompressionSessionWaitForAsynchronousFrames(dec);
            done++;
        }
    }
    double wall = now_sec() - t0;
    double cpu = cpu_sec() - c0;

    if (done > 0 && wall > 0) {
        printf("    %d 帧 / %.3f s  →  %.2f ms 每帧  (约 %.0f fps 单线程串行)\n",
               done, wall, wall * 1000.0 / done, done / wall);
        printf("    本进程 CPU %.3f s（占墙钟 %.0f%%）\n", cpu, cpu / wall * 100.0);
    }

    VTDecompressionSessionInvalidate(dec);
    CFRelease(dec);
    CFRelease(fmt);
    printf("\n");
}

int main(int argc, char **argv)
{
    int doBench = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "bench") == 0) doBench = 1;
    }
    setvbuf(stdout, NULL, _IONBF, 0);

    printf("\n================ VDA / VideoToolbox 解码能力实测 ================\n\n");

    /* ---------- A. 系统声明的硬件解码支持 ---------- */
    printf("[A] 硬件解码能力声明  VTIsHardwareDecodeSupported()\n");
    void *sym = dlsym(RTLD_DEFAULT, "VTIsHardwareDecodeSupported");
    if (!sym) {
        printf("    符号不可用，跳过\n");
    } else {
        VTIsHWDecodeFn fn = (VTIsHWDecodeFn)sym;
        CMVideoCodecType list[] = { CODEC_H264, CODEC_HEVC, CODEC_VP9, CODEC_AV1 };
        for (int i = 0; i < 4; i++) {
            Boolean r = fn(list[i]);
            printf("    %s  →  %s\n", cname(list[i]), r ? "支持硬解" : "不支持（走软件）");
        }
    }
    printf("\n");

    /* ---------- B/C. 实解码 ---------- */
    CMVideoCodecType streams[] = { CODEC_H264, CODEC_HEVC };
    for (int i = 0; i < 2; i++) {
        CMVideoCodecType codec = streams[i];
        printf("[%s] %s 实解码测试\n", i == 0 ? "B" : "C", cname(codec));

        CMFormatDescriptionRef fmt = makeStream(codec, ENC_W, ENC_H, ENC_FRAMES);
        if (!fmt) {
            printf("    无可用码流，本节跳过\n\n");
            continue;
        }

        tryDecode(fmt, 0, "强制硬解");
        tryDecode(fmt, 1, "允许软解回落");
        CFRelease(fmt);
        printf("\n");
    }

    for (int i = 0; i < gN; i++) { if (gS[i]) { CFRelease(gS[i]); gS[i] = NULL; } }
    gN = 0;

    if (doBench) {
        bench(CODEC_HEVC, 3840, 2160, 30, 2, 1);
        bench(CODEC_HEVC, 3840, 2160, 30, 2, 0);
        bench(CODEC_H264, 1920, 1080, 60, 3, 1);
        bench(CODEC_H264, 1920, 1080, 60, 3, 0);
    }

    printf("================================================================\n\n");
    return 0;
}
