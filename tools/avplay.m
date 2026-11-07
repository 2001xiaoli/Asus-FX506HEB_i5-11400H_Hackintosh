/*
 * avplay.m - 用 AVPlayer 真实播放（无窗口），测播放态 CPU 与解码器加载
 *
 * 用法：./tools/avplay <文件> [秒数]
 * 说明：这是 QuickTime / Safari 播放时同一套 AVFoundation 管线，
 *      只是不带 UI，便于无人值守测量。
 */

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <mach-o/dyld.h>
#import <unistd.h>

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

int main(int argc, char **argv)
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        if (argc < 2) {
            printf("用法: avplay <视频文件> [播放秒数]\n");
            return 1;
        }
        NSString *path = [NSString stringWithUTF8String:argv[1]];
        double seconds = (argc > 2) ? atof(argv[2]) : 6.0;

        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
        NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (tracks.count == 0) { printf("无视频轨\n"); return 1; }
        AVAssetTrack *track = tracks[0];
        CGSize sz = track.naturalSize;

        AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
        NSDictionary *attrs = @{
            (id)kCVPixelBufferPixelFormatTypeKey :
                @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            (id)kCVPixelBufferIOSurfacePropertiesKey : @{}
        };
        AVPlayerItemVideoOutput *out =
            [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attrs];
        [item addOutput:out];

        AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
        player.muted = YES;

        printf("\n播放 %.0fx%.0f，时长 %.1f s，采样 %.1f s\n",
               sz.width, sz.height, CMTimeGetSeconds(asset.duration), seconds);

        [player play];

        double t0 = now_sec(), c0 = cpu_sec();
        int frames = 0;
        double last = 0;
        while (now_sec() - t0 < seconds) {
            /* 必须让 run loop 转起来，否则 AVPlayer 不会推进播放 */
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            CMTime ct = item.currentTime;
            CVPixelBufferRef pb = [out copyPixelBufferForItemTime:ct itemTimeForDisplay:NULL];
            if (pb) { frames++; CVPixelBufferRelease(pb); }
            last = CMTimeGetSeconds(ct);
        }
        double wall = now_sec() - t0;
        double cpu = cpu_sec() - c0;

        printf("实际推进到 %.2f s，取到 %d 帧\n", last, frames);
        printf("CPU 时间 %.3f s / 墙钟 %.3f s  → 占用 %.0f%%\n",
               cpu, wall, cpu / wall * 100);
        printf("（单核满载 = 100%%，多核并行会超过 100%%）\n\n");

        int found = 0;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *n = _dyld_get_image_name(i);
            if (n && strstr(n, "nvdec")) { printf("  [解码器] %s\n", n); found = 1; }
        }
        if (!found) printf("  [解码器] 未加载 NVDEC（走了软件或 Intel 路径）\n");
        printf("\n");

        [player pause];
    }
    return 0;
}
