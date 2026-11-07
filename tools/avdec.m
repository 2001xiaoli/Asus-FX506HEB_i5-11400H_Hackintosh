/*
 * avdec.m - 用 AVFoundation 走「播放器同款」解码路径，验证 VDA 硬解是否生效
 *
 * 流程：AVAssetWriter 写一段 4K HEVC -> AVAssetReader 读回并解码 -> 统计吞吐
 * 播放器（QuickTime / Safari）解码时走的就是 AVAssetReader 这一层。
 *
 * 编译：
 *   clang -fobjc-arc -O1 -o tools/avdec tools/avdec.m \
 *     -framework Foundation -framework AVFoundation \
 *     -framework CoreVideo -framework CoreMedia
 */

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <mach-o/dyld.h>

static void dumpCodecImages(void)
{
    int found = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i);
        if (!n) continue;
        if (strstr(n, "nvdec") || strstr(n, "nvenc") ||
            strstr(n, "NVMTLDriver") || strstr(n, "VADriver")) {
            printf("      [映射] %s\n", n);
            found = 1;
        }
    }
    if (!found) printf("      [映射] 未加载任何硬件解码器库\n");
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

static int writeMovie(NSString *path, int W, int H, int N, NSString *codec)
{
    NSURL *url = [NSURL fileURLWithPath:path];
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];

    NSError *err = nil;
    AVAssetWriter *w = [[AVAssetWriter alloc] initWithURL:url
                                                 fileType:AVFileTypeQuickTimeMovie
                                                    error:&err];
    if (!w) { printf("    编码器创建失败: %s\n", err.localizedDescription.UTF8String); return 0; }

    NSDictionary *settings = @{
        AVVideoCodecKey  : codec,
        AVVideoWidthKey  : @(W),
        AVVideoHeightKey : @(H),
    };
    AVAssetWriterInput *in = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                                        outputSettings:settings];
    in.expectsMediaDataInRealTime = NO;

    NSDictionary *attrs = @{
        (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey           : @(W),
        (id)kCVPixelBufferHeightKey          : @(H),
    };
    AVAssetWriterInputPixelBufferAdaptor *ad =
        [[AVAssetWriterInputPixelBufferAdaptor alloc] initWithAssetWriterInput:in
                                                  sourcePixelBufferAttributes:attrs];

    [w addInput:in];
    if (![w startWriting]) {
        printf("    startWriting 失败: %s\n", w.error.localizedDescription.UTF8String);
        return 0;
    }
    [w startSessionAtSourceTime:kCMTimeZero];

    for (int i = 0; i < N; i++) {
        while (!in.isReadyForMoreMediaData) usleep(1000);
        CVPixelBufferRef pb = NULL;
        if (ad.pixelBufferPool) {
            CVPixelBufferPoolCreatePixelBuffer(NULL, ad.pixelBufferPool, &pb);
        }
        if (!pb) CVPixelBufferCreate(NULL, W, H, kCVPixelFormatType_32BGRA, NULL, &pb);
        if (!pb) break;

        CVPixelBufferLockBaseAddress(pb, 0);
        uint8_t *base = (uint8_t *)CVPixelBufferGetBaseAddress(pb);
        size_t bpr = CVPixelBufferGetBytesPerRow(pb);
        for (int y = 0; y < H; y++) {
            uint8_t *row = base + (size_t)y * bpr;
            for (int x = 0; x < W; x++) {
                uint8_t *p = row + (size_t)x * 4;
                p[0] = (uint8_t)((x + i * 16) & 0xff);
                p[1] = (uint8_t)(y & 0xff);
                p[2] = (uint8_t)(((x * 7) ^ (y * 3)) & 0xff);
                p[3] = 255;
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, 0);

        [ad appendPixelBuffer:pb withPresentationTime:CMTimeMake(i, 30)];
        CVPixelBufferRelease(pb);
    }

    [in markAsFinished];
    __block bool finished = false;
    [w finishWritingWithCompletionHandler:^{ finished = true; }];
    while (!finished && w.status == AVAssetWriterStatusWriting) usleep(10000);

    BOOL ok = (w.status == AVAssetWriterStatusCompleted);
    if (!ok) printf("    写入失败: status=%ld %s\n", (long)w.status,
                    w.error.localizedDescription.UTF8String);
    return ok;
}

static void decodeMovie(NSString *path, const char *tag)
{
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!track) { printf("    无视频轨\n"); return; }

    CGSize size = track.naturalSize;
    NSError *err = nil;
    AVAssetReader *r = [[AVAssetReader alloc] initWithAsset:asset error:&err];
    if (!r) { printf("    AVAssetReader 创建失败\n"); return; }

    AVAssetReaderTrackOutput *out =
        [[AVAssetReaderTrackOutput alloc] initWithTrack:track
                                         outputSettings:@{
            (id)kCVPixelBufferPixelFormatTypeKey :
                @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            (id)kCVPixelBufferIOSurfacePropertiesKey : @{}
        }];
    out.alwaysCopiesSampleData = NO;
    [r addOutput:out];
    [r startReading];

    double t0 = now_sec(), c0 = cpu_sec();
    int cnt = 0;
    while (r.status == AVAssetReaderStatusReading) {
        CMSampleBufferRef sb = [out copyNextSampleBuffer];
        if (!sb) break;
        cnt++;
        CFRelease(sb);
    }
    double wall = now_sec() - t0;
    double cpu = cpu_sec() - c0;

    printf("    %s %.0fx%.0f：解码 %d 帧 / %.3f s → %.2f ms/帧（%.0f fps）\n",
           tag, size.width, size.height, cnt, wall,
           cnt ? wall * 1000.0 / cnt : 0, wall > 0 ? cnt / wall : 0);
    printf("    CPU %.3f s，占墙钟 %.0f%%\n", cpu, wall > 0 ? cpu / wall * 100 : 0);
    dumpCodecImages();
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        int decodeOnly = (argc > 1 && strcmp(argv[1], "decode") == 0);
        printf("\n========== AVFoundation（播放器同款路径）解码验证 ==========\n");
        printf("%s\n\n", decodeOnly ? "模式：仅解码已有素材" : "模式：重新生成素材后解码");

        struct { const char *path; int w, h, n; NSString *codec; const char *name; } cases[] = {
            { "/tmp/vdacheck-4k-hevc.mov",  3840, 2160, 60, AVVideoCodecTypeHEVC, "HEVC 4K" },
            { "/tmp/vdacheck-1080p-h264.mov", 1920, 1080, 60,
              AVVideoCodecTypeH264, "H.264 1080p" },
        };

        for (int i = 0; i < 2; i++) {
            printf("[%d] %s\n", i + 1, cases[i].name);
            NSString *p = [NSString stringWithUTF8String:cases[i].path];
            if (!decodeOnly) {
                double te0 = now_sec();
                if (!writeMovie(p, cases[i].w, cases[i].h, cases[i].n, cases[i].codec)) {
                    printf("    跳过\n\n");
                    continue;
                }
                printf("    写入 %d 帧耗时 %.2f s\n", cases[i].n, now_sec() - te0);
            }

            const char *hold = getenv("AV_HOLD");
            if (hold) {
                printf("    [pid %d] 保持 %ss，供外部采样…\n", getpid(), atoi(hold));
                sleep(atoi(hold));
            }

            decodeMovie(p, cases[i].name);
            printf("\n");
        }

        printf("==========================================================\n\n");
    }
    return 0;
}
