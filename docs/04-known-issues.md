← [返回 README](../README.md)

<a id="s4"></a>

## 4. 已知问题与限制

⚠️ **S3 整机睡眠无法唤醒，合盖必死**：`pmset sleepnow` 或合盖后按键、电源键都没反应，只能长按电源强制重启。`pmset -g log` 里没有任何 Wake 记录，只有 `Failure during sleep: 0x5F9100000012`。熄屏（display sleep）只走显卡 Doze/Wake 状态机，已修好；S3 涉及 PCI D3、GPU 电源井、framebuffer 整体重建，是另一条路。**绕法：关掉自动睡眠，合盖前关机。**

| 限制 | 说明 |
| --- | --- |
| VP9 / AV1 无硬解 | `VTIsHardwareDecodeSupported()` 实测只有 H.264 / HEVC 支持，bundle 里没有对应 decoder。4K AV1 只能 CPU 软解，看在线视频优先选 HEVC / H.264 源 |
| 核显媒体引擎熔断 | `video=4` → VCS0 / VECS0 不存在。强开核显 accelerator 走 VideoToolbox，两次 panic 都指到 `IGHardwareRingBufferMedia::init` 里 `scheduler->cs[1]` 为 NULL。芯片层面缺失，patch 骗不过去；代价是 VADriver 必须保持 `chmod 000` |
| 内屏只接核显 | Optimus 无 MUX，内屏 eDP 走核显，独显不驱动屏幕 |
| Thunderbolt / USB4 | 硬件在，macOS 侧没有驱动 |
| MTLDriver 是 ad-hoc 签名 | 修泄漏后重签，在 `amfi=0x80` 下能加载；系统更新或重装 donor 包会覆盖补丁，90KB/次的泄漏会回来 |
| 核显只有 Metal 2 | 实测 4096 线程计算内核 0 错；Metal 3 由独显提供，但不参与桌面合成 |
