← [返回 README](../README.md)

<a id="s6"></a>

## 附录 A. WhateverXe 0.7.0 → 0.8.0 升级记录

记录日期 2026-11-09，机器为本仓库对应的华硕天选2（i5-11400H / UHD 9A68 / RTX 3050 Ti）。目的是给**下一次升级**留一份照着做就行的清单，而不是重新踩一遍坑。

<a id="s6-1"></a>

### A.1 版本必须成对

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| WhateverXe kext | **0.8.0**（本仓库用补丁版） | 上游 2026-11-07 发布，asset `721068791` |
| WhateverXe Graphics pkg | **0.4.1** | asset `721061161`，95,200,578 B |
| donor（`/Library/Extensions`） | Graphics / Framebuffer **16.0.32**，Compat **0.8.0** | 由 pkg 安装 |

- **0.8.0 与 0.4.1 必须配套**。先装 pkg、再换 kext、最后重启；顺序反了会出现「0.8.0 kext + 0.4.0 payload」的错配组合。
- 0.4.1 相对 0.4.0 **只差 217 B**，donor 二进制没换；变化只在通用兼容组件：不再要求精确内核 build string。
- 官方支持的 device ID 仍是 `9A40 / 9A49 / 9A78`，**不含本机 `9A68`**，所以不能直接换官方二进制，必须用打过补丁的 kext。

<a id="s6-2"></a>

### A.2 上游 0.8.0 改了什么（只列与本机有关的）

| 类别 | 内容 | 对本机 |
| --- | --- | --- |
| 新增 | Raptor Lake-U 支持 | 无关 |
| 新增 | 实验性系统睡眠 / 唤醒 | **无关**：只服务 MIPI DSI 笔记本 + 特定 ACPI，本机是 eDP |
| 新增 | MiniBook X 60Hz 模式 | 无关 |
| 修复 | 0.7.0 引入的「部分受支持 Tiger Lake 配置丢失图形加速」回归 | 相关，但本机走的是自己的 accel 开关 |
| 修复 | 重启 / 关机异常 | 相关 |
| 修复 | macOS 更新后内核/驱动代码位置变化时的兼容性 | 相关（决定补丁是否还能挂上） |
| 要求 | 必须搭配最新 Graphics | 见 A.1 |

<a id="s6-3"></a>

### A.3 本机补丁的移植结果

- 补丁文件：`patches/whateverxe-0.8.0-gt1.patch`，**381 行**，只动 `kern_xe.cpp`（319 行 diff）和 `kern_xe.hpp`（62 行 diff）。
- 以 0.7.0 时期的功能 diff 为基准，`patch -p1 -F3` **15 个 hunk 全通过、0 个 `.rej`**。官方源码更新后行号必然错位，按功能说明手动移植即可。
- 0.8.0 新增的 `kern_display13_power.inc`（原 `kern_display13_framebuffer_power.inc`）是 **Display13 / DSI 专用**，不碰 TGL eDP 路径；`wrapTGLDisableDisplay` 仍在，`-wex-edp-keep` 用的是符号名 hook，不依赖硬编码偏移，所以这些重构对本机无害。
- 编译（29 秒，0 error）：

```bash
cd tools/WhateverXe-0.8.0-fbonly && rm -rf build
python3 tools/build.py --release \
  --sdk ../downloads/MacKernelSDK-extract/MacKernelSDK-master \
  --lilu ../downloads/lilu-sdk/Lilu.kext --output build
```

- 产物：`WhateverXe.kext` **0.8.0 RELEASE / x86_64 / 1,840,416 B / sha256 `28ec9a97…82227`**（官方原版 1,720,264 B）。未签名，OpenCore 注入不需要签名。
- 重编译前必须 `rm -rf build`；Lilu 头文件是符号链接，需要 `cp -RL` 解引用后再当 SDK 用。

<a id="s6-4"></a>

### A.4 三个坑（下次一定会再遇到）

1. **EFI 里的 kext 被换成官方版 → 显存掉到 7 MB。**
   症状：`system_profiler` 显示 `Intel UHD Graphics 7 MB`、`ioreg -rc AppleIntelTGLGraphicsFramebuffer` 无实例、`IOFBMemorySize = 8294400`（正好是 1920×1080×4 一帧，说明被 `IONDRVFramebuffer` 兜底接管）。
   原因：官方 `decodeSmallGT` 只认 `video ∈ {1,5}`，本机 `video=4` 直接被判不合格；此时 boot-args 里的 `-wex-gt1-*` 全是空参数。
   判断方法：`strings` 补丁版二进制应能数到 8 个 `-wex-gt1-*` / `WEXEDPKeep` 字符串，官方版是 0 个。

2. **FAT32 上写 `config.plist` 会假成功。**
   `Path.write_bytes()` 返回了、字节数没变。必须 `open(...,"wb") + flush + os.fsync()`，然后**同一函数内回读比字节**。本仓库所有改 EFI 的脚本都按这个来。

3. **`-wex-gt1-fb-only` 不能删。**
   fuse 扩展（放行 `video=4`）是挂在 fb-only 这条路径下的；想开加速要**叠加** `-wex-gt1-accel`，而不是把 `-wex-gt1-fb-only` 去掉。最终可用的组合：

```
-wex-gt1-fb-only -wex-gt1-accel -wex-edp-keep
```

`WhateverXeGT1FramebufferOnly=Yes` 与 `WhateverXeGT1AcceleratorTrial=Yes` **并存是正常的**：前者决定 fuse 扩展，后者才真正放开加速器。

<a id="s6-5"></a>

### A.5 关键结论：Intel 硬解必须关掉，Metal 才活得下来

- 本机 GT1 fuse `fuses=[1,1,0,f0,e00fb]` → `video = (~0xE00FB) & 0xFF = 4`，含义是**只暴露 VD2，没有 VCS0/VECS0**。
- 加速器起来后，只要有进程走 Intel 解码：`VTDecoderXPCService` → `IGAccelVideoContextMedia::processDataBuffers` → `IGHardwareRingBufferMedia::init` → `IGScheduler5::bind`，而 `scheduler->cs[1]`（媒体命令流）**永远是 NULL** → 空指针，CR2=`0x284`。
- 这是硅片 fuse 编程的结果，**不是驱动 bug**，改 WhateverXe 也没用。历史上 5 次 panic 全部同签名：

| 报告 | uptime | 说明 |
| --- | --- | --- |
| `Kernel-2026-11-08-120030.panic` | **1230 s** | 加速状态下稳定跑了 20 分半，只在解码时崩 → Metal 本身没问题 |
| `Kernel-2026-11-09-130741 / 132535 / 133712 / 135934` | 70~95 s | 开机末段触发解码即崩，表现为「进度条走完自动重启」 |

- **解决办法**：把 Intel 的 VA 驱动下线，VDA 交给独显（`com.nullmoth.NVMTLDriver` 自带 `libnvdec_h264/hevc`）或软件解码。`/Library/GPUBundles` 不在 SSV 上，改名即可，随时可复原：

```bash
sudo mv /Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle \
        /Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle.disabled
```

- 代价：**Intel Quick Sync 用不了**（硬解/硬编）。这是本机 fuse 决定的硬限制，不要再往这条路上投入。
- 排查 panic 的心法：只看三样——进程名是不是 `VTDecoderXPCService`、`CR2` 是不是 `0x284`、栈里有没有 `AppleIntelTGLGraphics(16.0)`。三样齐了就是媒体引擎，和 framebuffer / Metal / edp-keep 都无关。

<a id="s6-6"></a>

### A.6 升级后验证清单

```bash
# 1) kext 是否为补丁版 0.8.0
kextstat | grep -i whateverxe

# 2) fuse 扩展、eDP keep、PAVP 守卫是否都 Ready
ioreg -l | grep -E "XELPSmallGTFuseExtension|WEXEDPKeepReady|TGLWEGRoutePAVPGuard|WhateverXeGT1"

# 3) 加速器实例应为 2（核显 + 独显）
ioreg -rc IOAccelerator | grep -c IOClass

# 4) 核显 Metal + 分辨率/刷新率
system_profiler SPDisplaysDataType | head -25

# 5) 有没有新的 panic
ls -lat /Library/Logs/DiagnosticReports/*.panic | head -3
```

本次通过时的实测值：

| 项 | 值 |
| --- | --- |
| 核显加速器 | `IOClass = IntelAccelerator`，`MetalPluginName = AppleIntelTGLGraphicsMTLDriver`，`IOGVACodec = Gen10` |
| 真的在跑 | `textureCount = 1644`、`contextGLCount = 2`、`context2DCount = 3`、`gartUsedBytes ≈ 318 MB` |
| Metal | 核显 **Metal 2**（该 MTLDriver 就到 Metal 2，不是 Metal 3；独显是 Metal 3） |
| 显存 / 显示 | 1536 MB、1920×1080@144Hz、`IOFBMemorySize = 268435456` |
| WEX 状态 | `XELPSmallGTFuseExtension=Yes`、`WEXEDPKeepReady=Yes`、`TGLWEGRoutePAVPGuard=Yes` |

<a id="s6-7"></a>

### A.7 下次升级照这个顺序做

1. **备份**：整个 `/Volumes/EFI/EFI/OC` 拷到 `backups/EFI-before-WEX-<版本>-<时间>/`，旧 kext 单列一份。
2. **先装 Graphics pkg**（新 kext 配套的那个版本），装完不要急着确认加速，先把 kext 也换了。
3. **换 kext**：只替换 `Kexts/WhateverXe.kext` 的 `Info.plist` + 二进制；换完 `shasum` 与编译产物对齐。
4. **同步 Comment**：`Kernel/Add` 里那条 `V0.x.y` 纯注释，跟着版本改（不影响引导，但方便排查）。
5. **确认 boot-args** 仍是 `-wex-gt1-fb-only -wex-gt1-accel -wex-edp-keep`（外加 `nvfb=1 nvaccel=1 nvfbheads=4`）。
6. **核对 VA 驱动仍处于 `.disabled`**：Graphics pkg 重装可能把 bundle 装回来，装完一定检查。
7. **重启 → 跑 A.6 的 5 条命令**。
8. **失败回滚**：EFI 里常备 `config.plist.good`（同内容但把 `-wex-gt1-accel` 换成 `-wex-noaccel`），OpenCore 选单的 `Rescue: UEFI Shell` 一条命令即可换回：

```
cp fs0:\EFI\OC\config.plist.good fs0:\EFI\OC\config.plist
reset
```

<a id="s6-8"></a>

### A.8 已知遗留

| 项 | 状态 |
| --- | --- |
| 合盖 / S3 睡眠 | 仍未解，`pmset displaysleepnow` 可测唤醒黑屏 |
| Intel Quick Sync | 主动禁用（fuse 无 VCS0），解码走独显 nvdec 或软解 |
| 核显 Metal 版本 | Metal 2，UI 已硬件加速；对 Metal 3 专属特性有影响 |
| Thunderbolt / USB4 | 控制器在，macOS 无驱动 |

<a id="s6-9"></a>

### A.9 本仓库里的对应内容

| 路径 | 说明 |
| --- | --- |
| `oc/config.plist` | 与实机同步的加速版配置，但 `PlatformInfo/Generic` 的四码是**占位值**，必须换成自己生成的才能引导 |
| `oc/config.plist.good` | 同内容但 `-wex-noaccel` 的救援版，同样已脱敏；A.7 第 8 步的 `Rescue: UEFI Shell` 就是靠它回退 |
| `oc/Kexts/WhateverXe.kext` | 0.8.0 补丁版二进制（sha256 `28ec9a97…82227`） |
| `patches/whateverxe-0.8.0-gt1.patch` | A.3 里的补丁；`whateverxe-0.7.0-gt1.patch` 保留供对照 |
| `tools/accel-trial.sh` | `on` / `off` / `status` 一键切换加速与 Intel VA，`off` 会同时恢复 VA bundle 并把 EFI 切回救援版 |
| `tools/sanitize-efi.py` | 从实机 EFI 生成脱敏副本并全量复扫四码 |

A.3 里提到的 `tools/WhateverXe-0.8.0-fbonly/` 是**本机源码副本，不在仓库里**（仓库只放自己写的改动）。需要重建时，从上游 0.8.0 源码应用本仓库补丁即可。

**绝对不要把本机原始 `config.plist`（含真实三码）覆盖进 `oc/`。** 每次同步后都应重新跑一次三码复扫，确认将入库的文件 0 命中。
