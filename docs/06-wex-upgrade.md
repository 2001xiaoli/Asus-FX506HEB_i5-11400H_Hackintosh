← [返回 README](../README.md)

<a id="s6"></a>

## 附录 A. WhateverXe 升级记录（0.7.0 → 0.8.0 → 0.8.2）



<a id="s6-1"></a>

### A.1 版本必须成对

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| WhateverXe kext | **0.8.2**（本仓库用补丁版） | 1,845,040 B / sha256 `e0bbc744…4026` |
| WhateverXe Graphics pkg | **0.4.3** | 内含 Compat **0.8.1** + GLDriver / XeCompilerAdapter |
| donor（`/Library/Extensions`） | Graphics / Framebuffer **16.0.0**，Compat **0.8.1** | 由 pkg 安装；实测就是 16.0.0，不是早期文档写的 16.0.32 |

- **0.8.2 与 0.4.3 必须配套，且这是硬失败。** 先装 pkg、再换 kext、最后重启；顺序反了或只用一半，显存直接掉 7 MB。
- 原因是 Compat 0.8.1 带来上游「只装一半组件时保留固件输出」的行为：它会检查 WEX 是否提供 `WhateverXeGraphicsABI`，没有就打 `WEX inactive; leaving firmware graphics in control` 并放弃接管。0.8.0 的 kext 没有这个属性，所以「新 Compat + 旧 kext」= 7 MB。
- 官方支持的 device ID 仍是 `9A40 / 9A49 / 9A78`，**不含本机 `9A68`**，所以不能直接换官方二进制，必须用打过补丁的 kext。
- 历史版本对照：0.7.0 ↔ 0.4.0、0.8.0 ↔ 0.4.1（那两代 Compat 是 0.8.0，没有 ABI 检查，错配只表现为功能缺失，不会立刻掉驱动）。

<a id="s6-2"></a>

### A.2 上游 0.8.0 → 0.8.2 改了什么（只列与本机有关的）

0.8.0 那一次的变更：

| 类别 | 内容 | 对本机 |
| --- | --- | --- |
| 新增 | Raptor Lake-U 支持 | 无关 |
| 新增 | 实验性系统睡眠 / 唤醒 | **无关**：只服务 MIPI DSI 笔记本 + 特定 ACPI，本机是 eDP |
| 新增 | MiniBook X 60Hz 模式 | 无关 |
| 修复 | 0.7.0 引入的「部分受支持 Tiger Lake 配置丢失图形加速」回归 | 相关，但本机走的是自己的 accel 开关 |
| 修复 | 重启 / 关机异常 | 相关 |
| 修复 | macOS 更新后内核/驱动代码位置变化时的兼容性 | 相关（决定补丁是否还能挂上） |
| 要求 | 必须搭配最新 Graphics | 见 A.1 |

0.8.1 / 0.8.2 那一次（CHANGELOG 里 0.8.2 没有独立条目，实质变化来自 0.8.1 + 配套 Compat）：

| 类别 | 内容 | 对本机 |
| --- | --- | --- |
| 变更 | **只装一半组件时保留固件输出**（`WEX inactive; leaving firmware graphics in control`） | **关键**：这就是 7 MB 兜底的来源，配合 Compat 0.8.1 的 `WhateverXeGraphicsABI` 检查 |
| 新增 | MIPI DSI 面板实验性 10-bit framebuffer | 无关（eDP） |
| 修复 | 系统睡眠后显示唤醒通知缺失 / 重复 | 无关（本机 S3 本来就是死的） |
| 修复 | buffer 边界处的显存映射 | 可能相关，未单独验证 |
| 要求 | 必须搭配 Graphics 0.4.3 | 见 A.1 |

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

> 本节记录的是 **0.8.0** 那一次。0.8.2 起改用合并补丁 `patches/whateverxe-0.8.2-gt1-backlight.patch`（16 hunk，GT1 系列 + 背光 duty 修正），产物 1,845,040 B / sha256 `e0bbc744…4026`，细节见 [5.4](05-patches.md#s5-4) 与 [A.10](#s6-10)。移植方式不变：官方源码 + 本仓库补丁，不要只挑其中一部分。

<a id="s6-4"></a>

### A.4 六个坑

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

4. **只移植了新补丁、漏了旧补丁 → 同样 7 MB。**

   0.8.2 升级时踩过：拿官方新源码只加了「背光 hook」这一处自己的补丁，忘了 `patches/whateverxe-0.8.0-gt1.patch` 那 15 个 hunk。
   症状与第 1 条**完全一样**（7 MB / 无 framebuffer 实例），但原因不是「用了官方版」，而是「用了一部分补丁的版本」。
   判断方法仍是数 `strings`：`-wex-gt1-*` + `WEXEDPKeep` 必须 **8 个**，0 个说明补丁全丢，1～7 个说明只打了部分。

5. **Graphics pkg 升级会抬高 Compat 的 ABI 门槛 → 7 MB。**

   0.4.3 装的 `AppleIntelTGLCompat 0.8.1` 新增了 `WhateverXeGraphicsABI` 检查与日志串 `WEX inactive; leaving firmware graphics in control`：**WEX 不提供该属性就直接放弃接管、把图形交回固件**。
   所以「新 Compat + 旧 kext」即使补丁齐全，也一定是 7 MB。判断方法：`strings <WEX> | grep -c WhateverXeGraphicsABI`，0 说明 kext 太旧；正常运行时 `ioreg` 里该属性应为 `<01000000>`。
   **这条把 A.1「版本必须成对」从"建议"变成了"硬失败"：错配不再只是功能缺失，而是直接掉驱动。**

6. **Graphics pkg 会把 Intel VA 驱动装回来 → 开机末段 panic。**

   pkg 的 payload 里带 `AppleIntelTGLGraphicsVADriver.bundle`，每次安装都会复原；而本机 `video=4` 没有 VCS0/VECS0，只要 VA 驱动启用 + 加速器开启，系统在登录阶段自己发起硬解就必崩。
   签名三要素：`Panicked task: VTDecoderXPCService`、`Fault CR2: 0x284`、栈含 `AppleIntelTGLGraphics → IOAcceleratorFamily2`，`uptime` 约 60～70 s（"进度条走完自动重启"）。
   **每次装完 pkg 必须重新确认 `AppleIntelTGLGraphicsVADriver.bundle` 不存在，只有 `.disabled`。**

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
# 1) kext 是否为补丁版 0.8.2
kextstat | grep -i whateverxe

# 2) fuse 扩展、eDP keep、PAVP 守卫、ABI、背光 hook 是否都 Ready
ioreg -l | grep -E "XELPSmallGTFuseExtension|WEXEDPKeepReady|TGLWEGRoutePAVPGuard|WhateverXeGT1|WhateverXeGraphicsABI|TGLPanelBacklightReady"

# 3) 加速器实例应为 2（核显 + 独显）
ioreg -rc IOAccelerator | grep -c IOClass

# 4) 核显 Metal + 分辨率/刷新率
system_profiler SPDisplaysDataType | head -25

# 5) 有没有新的 panic
ls -lat /Library/Logs/DiagnosticReports/*.panic | head -3

# 6) 背光满档是否真的到 ~100%（本机修正是 99.8%；脚本 check-brightness-kext.sh 在本机工作区，未入库）
bash tools/check-brightness-kext.sh
```

本次通过时的实测值（0.8.2 那次启动）：

| 项 | 值 |
| --- | --- |
| 核显加速器 | `IOClass = IntelAccelerator`，`MetalPluginName = AppleIntelTGLGraphicsMTLDriver`，`IOGVACodec = Gen10` |
| 真的在跑 | `textureCount = 1644`、`contextGLCount = 2`、`context2DCount = 3`、`gartUsedBytes ≈ 318 MB` |
| Metal | 核显 **Metal 2**（该 MTLDriver 就到 Metal 2，不是 Metal 3；独显是 Metal 3） |
| 显存 / 显示 | 1536 MB、1920×1080@144Hz、`IOFBMemorySize = 268435456` |
| WEX 状态 | `XELPSmallGTFuseExtension=Yes`、`WEXEDPKeepReady=Yes`、`TGLWEGRoutePAVPGuard=Yes`、`WhateverXeGraphicsABI=<01000000>` |
| 背光 | `TGLPanelBacklightReady=Yes`，满亮度 duty `95806 / 96000 = 99.8%` |

<a id="s6-7"></a>

### A.7 下次升级照这个顺序做

**核心原则：顺序是硬的，门禁是脚本执行的，不是"提醒你还差一步"。**

#### 阶段 0：准备（改任何东西之前）

1. **整目录备份** `/Volumes/EFI/EFI/OC` → `backups/EFI-OC-before-WEX-<版本>-<时间>/`。
2. **记录基线**：当前 `CFBundleVersion`、二进制 sha256、`strings` 的 GT1/ABI/背光三项计数、Compat 版本、VA bundle 是否存在。回滚时要靠这些数说明"确实回到了原样"。
3. **确认救援路径可用**：`config.plist.good` 存在且 boot-args 是 `-wex-noaccel`；OpenCore 选单里有 `Rescue: UEFI Shell`。

#### 阶段 1：编译（在源码里把补丁打全）

4. 取新版本源码，**先重放全部自研补丁**，再谈别的：

```bash
patch -p1 -F3 < patches/whateverxe-0.8.2-gt1-backlight.patch   # 应 16 hunk 全过、0 个 .rej
grep -c 'wrapTGLPanelBacklight' WhateverXe/kern_xe.cpp          # 背光 hook 也必须在
```

5. **编译 + 字符串验收**（这一步不过就不要往下走）：

```bash
python3 tools/build.py --release \
  --sdk ../downloads/MacKernelSDK-extract/MacKernelSDK-master \
  --lilu ../downloads/lilu-sdk/Lilu.kext --output build

K=build/WhateverXe.kext/Contents/MacOS/WhateverXe
strings -a $K | grep -c -E '\-wex-gt1|WEXEDPKeep'   # 必须 8
strings -a $K | grep -c WhateverXeGraphicsABI        # 必须 ≥1（0.8.1+ Compat 的前提）
strings -a $K | grep -c TGLPanelBacklightReady       # 必须 ≥1（背光修复）
shasum -a 256 $K                                     # 记下来
```

#### 阶段 2：系统侧先装 pkg（顺序不能反）

6. `sudo installer -pkg WhateverXe-Graphics-<版本>.pkg -target /`，等它重建 aux 内核集合。
7. **立刻禁用 VA 驱动**（A.4 第 6 条）：

```bash
sudo mv /Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle \
        /Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle.disabled
ls -ld /Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle*   # 只应剩 .disabled*
```

8. 确认 Compat 实际版本：`PlistBuddy -c 'Print :CFBundleVersion' /Library/Extensions/AppleIntelTGLCompat.kext/Contents/Info.plist`。

#### 阶段 3：换 kext + 刷新救援配置

9. 部署新 kext 到 `Kexts/WhateverXe.kext`，**写入后逐字节回读**（FAT32 会假成功，A.4 第 2 条）。
10. 断言：版本号 / sha256 / GT1=8 / ABI / 背光 hook 全部对上，否则立刻用阶段 0 的备份还原。
11. 同步 `Kernel/Add` 里的 `Comment` 为 `V<版本>`（纯注释，等价于给人看的路标）。
12. **重新生成 `config.plist.good`**：同内容但 `-wex-gt1-accel` → `-wex-noaccel`，保证任何时候都有一条能开机的路。

> 10～12 三步 + 第 7 步在本机工作区已串成 `tools/finish-wex-0.8.2.sh`（**不在本仓库**，因为它含本机绝对路径）：任一步失败即 `set -e` 中止、EFI 保持原状，全部通过才打印「可以重启」。在外人机器上照着 7～12 手工做即可。

#### 阶段 4：重启与验收

13. 重启，跑 A.6 的清单（本机工作区有自动化版 `check-wex-0.8.2.sh`，未入库）。
14. 判据：`VRAM 1536 MB`、`IOFBMemorySize=268435456`、`WhateverXeGraphicsABI=<01000000>`、`WEXEDPKeepReady=Yes`、`TGLPanelBacklightReady=Yes`、满亮度占空比 ≈99.8%、无新 panic。

#### 阶段 5：失败时（按症状分诊，别猜）

| 症状 | 原因 | 处理 |
| --- | --- | --- |
| 显存 7 MB，但能进系统 | GT1 补丁没打全（A.4-1/4），或 Compat 的门槛比 kext 新（A.4-5） | 先 `strings` 数 GT1=8、ABI≥1，再核 Compat 版本；两者必须同时满足 |
| 进度条走完自动重启（≈68 s） | VA 驱动被装回 + 加速器开启（A.4-6） | 见 A.5；UEFI Shell 换 `config.plist.good` 进系统，然后禁用 VA |
| 开机黑屏但无 panic | eDP 重训失败 | `-wex-edp-keep` 是否还在、`WEXEDPKeepReady` 是否为 Yes |

回滚一律走整包脚本（Compat + GPUBundles + kext + 重建 KC 一起还原），不要手改单点；本机工作区对应 `rollback-wex-0.8.2.sh`。

<a id="s6-8"></a>

### A.8 已知遗留

| 项 | 状态 |
| --- | --- |
| 合盖 / S3 睡眠 | 仍未解，`pmset displaysleepnow` 可测唤醒黑屏 |
| Intel Quick Sync | 主动禁用（fuse 无 VCS0），解码走独显 nvdec 或软解 |
| 核显 Metal 版本 | Metal 2，UI 已硬件加速；对 Metal 3 专属特性有影响 |
| HDMI | 仍未解，显示异常或黑屏 |

<a id="s6-9"></a>

### A.9 本仓库里的对应内容

| 路径 | 说明 |
| --- | --- |
| `oc/config.plist` | 与实机同步的加速版配置，但 `PlatformInfo/Generic` 的四码是**占位值**，必须换成自己生成的才能引导 |
| `oc/config.plist.good` | 同内容但 `-wex-noaccel` 的救援版，同样已脱敏；A.7 第 8 步的 `Rescue: UEFI Shell` 就是靠它回退 |
| `oc/Kexts/WhateverXe.kext` | 0.8.2 补丁版二进制（1,845,040 B / sha256 `e0bbc744…4026`） |
| `patches/whateverxe-0.8.2-gt1-backlight.patch` | 本机在用：GT1 系列 + 背光 duty 修正合并补丁，对官方 0.8.2 源码 `patch -p1` 16 hunk 全过 |
| `patches/whateverxe-0.8.0-gt1.patch` | 0.8.0 时期的补丁，保留供对照与移植底本；`whateverxe-0.7.0-gt1.patch` 同理 |
| `tools/accel-trial.sh` | `on` / `off` / `status` 一键切换加速与 Intel VA，`off` 会同时恢复 VA bundle 并把 EFI 切回救援版 |
| `tools/sanitize-efi.py` | 从实机 EFI 生成脱敏副本并全量复扫四码 |

A.3 里提到的 `tools/WhateverXe-0.8.0-fbonly/` 是**本机源码副本，不在仓库里**（仓库只放自己写的改动）。需要重建时，从上游对应版本源码应用本仓库补丁即可。

<a id="s6-10"></a>

#### 最终状态（升级成功时的实测值）

| 项 | 值 |
| --- | --- |
| WhateverXe | **0.8.2**，1,845,040 B，sha256 `e0bbc744…4026` |
| 二进制判据 | GT1 字符串 **8**、`WhateverXeGraphicsABI` **1**、`TGLPanelBacklightReady` **1** |
| Compat | **0.8.1** |
| VA 驱动 | 仅 `.disabled`（pkg 装回的 02:14 那份已改名） |
| 加速器 | `VRAM 1536 MB`、`Metal 2`、`IOFBMemorySize = 268435456` |
| WEX 状态 | `WhateverXeGraphicsABI=<01000000>`、`WEXEDPKeepReady=Yes`、`TGLPanelBacklightReady=Yes` |
| 背光 | 满亮度 duty `95806 / 96000 = 99.8%` |
| boot-args | 未变：`-wex-gt1-fb-only -wex-gt1-accel -wex-edp-keep` |

> 注意：早期文档（0.8.0 时期）写 donor 是 `16.0.32`，实测本机 `AppleIntelTGLGraphics` / `Framebuffer` 都是 **16.0.0**，A.1 已按实测更正。背光 hook 的入口字节 `55 48 89 e5 41 56 53 48 ff 05 90 44 09 00`（偏移 `0x4A56A`）在 16.0.0 上完全匹配；若将来换 donor，这个字节序列必须重新校验，对不上就不装 hook（会退回 18.5% 亮度，但不会崩）。
