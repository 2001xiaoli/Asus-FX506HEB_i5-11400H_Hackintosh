# 华硕天选2（i5-11400H / RTX 3050 Ti）装 macOS

![English Version](https://img.shields.io/badge/English_Version-blue?style=for-the-badge)

**简体中文** · [English →](en/README.md)

> **使用前注意**：仓库内的 `oc/` 是脱敏 EFI，`oc/config.plist` 里三码与 ROM 为占位值，须换成自己生成的才能引导。

## 现在能用到什么程度

| 项目                   | 状态                             |
| -------------------- | ------------------------------ |
| 显示屏                  | 可用，1920×1080 @144Hz |
| 键盘 / 触摸板 / 亮度快捷键     | 可用                             |
| 核显 UHD（9A68）         | 可用，1536MB，Metal 2，负责输出画面       |
| 独显 RTX 3050 Ti       | 可用，Metal 3，负责计算和视频硬解，**不驱动屏幕** |
| 声卡 / Wi-Fi / 蓝牙 / 电池 | 可用                             |
| 熄屏后唤醒                | 可用                             |
| **睡眠 / 合盖（S3）**      | **不可用，睡下去就醒不过来**               |

---

## 1. 硬件详情

实机探测（IORegistry / `system_profiler` / ACPI 反编译 / Windows 注册表）。

| 项                  | 值                                                                                                               |
| ------------------ | --------------------------------------------------------------------------------------------------------------- |
| 机型 / CPU           | 华硕天选2 · i5-11400H（Tiger Lake-H45，6 核 12 线程）· Intel 500 系（HM570 一类）                                              |
| 内屏                 | 1920×1080 @144Hz，eDP                                                                                            |
| 系统 / 引导            | macOS 15.8.1 `24H32` · OpenCore 1.0.8 (RELEASE) · SMBIOS `MacBookPro16,2` · 西数 SN550                            |
| 核显                 | `8086:9A68` Intel UHD（TGL-H GT1），动态共享最大 1536MB，Metal 2，**内屏 eDP 输出**                                            |
| 独显                 | `10de:25A0` RTX 3050 Ti Laptop（GA107），4GB PCIe x8，Metal 3（NVK 翻译层），**不接屏幕**                                     |
| 键盘                 | PS/2，`PS2K` / `MSFT0001` / `PNP0303`                                                                            |
| 触摸板                | **ELAN1203**，I2C HID `PNP0C50`，ACPI `\_SB.PC00.I2C0.TPD0`（Windows 注册表挂在 `ACPI\INTC1043\SEN2/SEN3`）              |
| I2C / GPIO         | `pci8086,43e8`（`00:15.0`）· `INT34C6`，ACPI 名 `GPI0`                                                              |
| 其他                 | Realtek ALC256（`alcid=17` + `alcverbs=1`）· Intel Wi-Fi `AirportItlwm 2.4.0` · Intel 蓝牙 `IntelBluetoothFirmware` + `BlueToolFixup` · EC/风扇 `AsusSMC 1.4.1` |
| Thunderbolt / USB4 | 控制器硬件在，macOS 下 `No drivers are loaded`                                                                          |

**第一个坑**：官方 VoodooI2C 2.9.1 的匹配表最晚只到 Ice Lake `0x34e8`，不含 TGL-H 的 `0x43e8`，主驱动压根不加载。

---

2.[EFI 驱动情况](docs/02-drivers.md#s2)

3.[安装步骤](docs/03-install.md#s3)

4.[已知问题与限制](docs/04-known-issues.md#s4)

5\. [补丁说明](docs/05-patches.md#s5)

附录 A.[WhateverXe 升级记录（0.7.0 → 0.8.0 → 0.8.2）](docs/06-wex-upgrade.md#s6)

## 6. 致谢与参考项目

| 项目                                                                                                            | 用在哪                                                                                      |
| ------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| [**WhateverXe**](https://github.com/b00t0x/WhateverXe)（b00t0x）                                                | 整个核显方案的地基，本机补丁基于 0.8.2 源码                                                                |
| [WhateverXe 修改版 OCLP](https://github.com/b00t0x/OpenCore-Legacy-Patcher)                                      | 安装 donor 图形驱动（`WhateverXe-Graphics` pkg）                                                 |
| [**nvidia-macos-driver**](https://github.com/nullmoth/nvidia-macos-driver)（NullMoth）                          | `NVRM` / `NVAccel` / `NVRMFB` / `NVRMAGDC` + `NVMTLDriver`，提供 Metal 3 和 NVDEC / NVENC 硬解 |
| [**VoodooI2C**](https://github.com/VoodooI2C/VoodooI2C)                                                       | I2C 触摸板；PR **#586** 提供 TGL-H `0x43e8` 匹配表                                                |
| [AirportItlwm](https://github.com/laobamac/itlwm)                                                             | Intel Wi-Fi                                                                              |
| [**MECHREVO-GM6AR57C-OpenCore**](https://github.com/559911/MECHREVO-GM6AR57C-OpenCore)（559911）                | 4.8 节的 `hwSetPanelPower` 非上电 no-op、`setDCState` DC 守卫；排查熄屏唤醒黑屏时的重要参照                     |
| [Samsung NP550XDA EFI](https://github.com/cost-12/Hackintosh-Samsung-Book-INTEL-CORE-I3-1115G4-11TH)（cost-12） | Tiger Lake + WhateverXe 同类配置对照                                                           |
| [`patches/whateverxe-0.8.2-gt1-backlight.patch`](patches/whateverxe-0.8.2-gt1-backlight.patch)（本机在用） | 基于 WhateverXe 0.8.2 的合并补丁：fuse 放行、`-wex-edp-keep`、doze-hold、PAVP 守卫，外加**背光 duty 修正**（满亮度 18.5% → 99.8%），见[补丁说明](docs/05-patches.md#s5-4) 与[附录 A](docs/06-wex-upgrade.md#s6) |
| [`patches/whateverxe-0.8.0-gt1.patch`](patches/whateverxe-0.8.0-gt1.patch)（历史） | 0.8.0 时期补丁，作为 0.8.2 补丁的移植底本保留 |
| [`patches/whateverxe-0.7.0-gt1.patch`](patches/whateverxe-0.7.0-gt1.patch)（历史） | 0.7.0 时期的补丁，保留供对照 |

本仓库只是**使用与排障记录**，所有驱动、引导器、donor 包的著作权归各自项目所有。链接失效或版本更新请以上游仓库为准。

**许可说明**：本仓库的文档与自写工具采用 [MIT](LICENSE)。`patches/` 下的补丁是上游 WhateverXe 0.8.2 的衍生作品，遵循其 **BSD-3-Clause** 许可（Copyright © 2018 vit9696）；转载或再分发时须一并保留上游版权声明与免责条款。

---

## 7. 适用性与免责

- 只在这台机器（核显 `8086:9A68`、独显 `10de:25a0`、macOS 15.8.1 `24H32`）实机验证过。
- 别的型号**不要直接套** boot-args 和补丁：这颗 11400H 的 fuse `video=4` 很特殊，社区里能跑通的 GT1 大多是 `video=1`，补丁是为这一个值写的。
- 改 EFI、改系统驱动、关 SIP 都有变砖和丢数据的风险。动手前备份整个 EFI 分区，并准备一个能引导的 U 盘。
- 个人记录，不是官方支持渠道。遇到问题请去上游项目提 issue。
