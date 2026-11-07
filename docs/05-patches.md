← [返回 README](../README.md)

<a id="s5"></a>

## 5. 补丁说明

仓库只放**自己写的改动**。Apple donor 驱动、官方 WhateverXe 发行包、打过补丁的系统二进制都不在仓库里，请从各项目官方渠道获取。

<a id="s5-1"></a>

### 5.1 `patches/whateverxe-0.7.0-gt1.patch`

相对官方 **WhateverXe 0.7.0** 源码，只动 `WhateverXe/kern_xe.cpp` 和 `kern_xe.hpp`，约 380 行 diff（已 `patch --dry-run` 验证）。官方源码更新后行号会对不上，请按下面的功能说明手动移植。

- **资格审核**：`decodeSmallGT` 原要求 `(~fuses[4]) & 0xFF ∈ {1,5}`，本机 `video=4` 被判不合格、退回 7MB 兜底帧缓冲。补丁只在 `video==4 && enhance==1` 且 `smallGTResources()` 确实解出 16EU / 4 L3 / 256KiB 时放行，并发布 `XELPSmallGTFuseExtension` 供核对。
- **三个新开关**：`-wex-gt1-fb-only` / `-wex-gt1-accel` / `-wex-edp-keep`（含义见 [第 2 章](02-drivers.md#s2-4)），状态写进 IORegistry；另加 `-wex-skip-gputicks`，`wrapTGLRegisterRead` 对 `0x2910` 返回 0，避开 TGL-H GT1 开机 16~17 秒硬冻（参考 WhateverXe issue #11 与 Elezorn 的 `gputicks-bootarg` 分支）。
- **绕开两个 panic**：`wrapTGLPAVPCommandCallback` 在 `[accel+0x1278]`（media engine）为 NULL 时直接返回 `0xe00002bc`；`AppleIntelPowerWell::init` 的纯虚调用由 `-wex-edp-keep` 让该路径不再执行。
- **eDP keep 与熄屏唤醒（最核心）**：`wrapTGLRegsNeedUpdate` 改成粘性抑制 `keep = (pipe==2) || tglEdpKeepBroken`，三条 return 路径全打点（`KeepCalls` / `KeepPassed` / `KeepAfterDoze`）；`wrapTGLDisableDisplay` 加 `EDP_KEEP_DOZE_HOLD`，Doze 期间只让背光变黑、不拆管线；`wrapTGLFBSetPowerState` **先记录状态再调原生**（原顺序反了，导致守卫读过期状态）；`wrapTGLPanelPower` / `wrapTGLSetDCState` 加面板电源与 DC6/DC9 守卫。

排查中间态留下的 `EDP_KEEP_SCOPE` / `EDP_KEEP_AFTER_DOZE` 分支保留在代码里便于对照。编译命令和验证方法见[安装第 3 步](03-install.md#s3-3)。

### 5.2 MTLDriver 两个字节补丁

| 项 | 值 |
| --- | --- |
| 文件 | `/Library/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle/Contents/MacOS/AppleIntelTGLGraphicsMTLDriver` |
| 适用版本 | Sequoia donor 16.0.x，`__TEXT` fileoff = 0（文件偏移等于 vmaddr） |
| 偏移 | `0x7ed87`：`75 0d`（`jne`，`m_isOnlyActiveCommandBuffer` 为真时跳过 `free`）→ `90 90`（两个 NOP，强制走释放路径） |
| 收尾 | `codesign -f -s - <文件>` ad-hoc 重签 |

打之前先备份原文件，并用偏移处的原始字节校验（不匹配说明 donor 版本不同，别硬改）。效果：50 次提交 RSS 从 5.0→9.5MB 变成 5.0→5.7MB，500 次后 5.9MB。完整命令见[安装第 5 步](03-install.md#s3-5)。
