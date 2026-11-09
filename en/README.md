# macOS on ASUS Tianxuan 2 (i5-11400H / RTX 3050 Ti)

[![Chinese (default)](https://img.shields.io/badge/Chinese-default-blue?style=for-the-badge)](../README.md)

**English** · [← Back to Chinese](../README.md)

> **Before use**: `oc/` is a sanitized EFI — the serial, MLB, SystemUUID and ROM in `oc/config.plist` are placeholders. Replace them with your own values before booting.

## What Works Today

| Item | Status |
| --- | --- |
| Internal display | Working, 1920×1080 @144Hz |
| Keyboard / trackpad / brightness keys | Working |
| iGPU UHD (9A68) | Working, 1536MB, Metal 2, drives the display |
| dGPU RTX 3050 Ti | Working, Metal 3, handles compute and video decode, **does not drive the display** |
| Audio / Wi-Fi / Bluetooth / battery | Working |
| Wake after display sleep | Working |
| **System sleep / closing the lid (S3)** | **Broken — it never wakes** |

---

## 1. Hardware Details

Read from the actual machine (IORegistry / `system_profiler` / decompiled ACPI / Windows registry).

| Item | Value |
| --- | --- |
| Model / CPU | ASUS Tianxuan 2 · i5-11400H (Tiger Lake-H45, 6C/12T) · Intel 500-series (HM570 class) |
| Internal panel | 1920×1080 @144Hz, eDP |
| OS / bootloader | macOS 15.8.1 `24H32` · OpenCore 1.0.8 (RELEASE) · SMBIOS `MacBookPro16,2` · WD SN550 |
| iGPU | `8086:9A68` Intel UHD (TGL-H GT1), up to 1536MB shared, Metal 2, **drives the internal eDP panel** |
| dGPU | `10de:25A0` RTX 3050 Ti Laptop (GA107), 4GB, PCIe x8, Metal 3 (NVK translation layer), **not connected to the panel** |
| Keyboard | PS/2, `PS2K` / `MSFT0001` / `PNP0303` |
| Trackpad | **ELAN1203**, I2C HID `PNP0C50`, ACPI `\_SB.PC00.I2C0.TPD0` (Windows registry: `ACPI\INTC1043\SEN2/SEN3`) |
| I2C / GPIO | `pci8086,43e8` (`00:15.0`) · `INT34C6`, ACPI name `GPI0` |
| Other | Realtek ALC (`alcid=48`) · Intel Wi-Fi `AirportItlwm 2.4.0` · Intel Bluetooth `IntelBluetoothFirmware` + `BlueToolFixup` |
| Thunderbolt / USB4 | Controller present, but `No drivers are loaded` under macOS |

**First pitfall**: stock VoodooI2C 2.9.1 only matches up to Ice Lake `0x34e8`; TGL-H's `0x43e8` is missing, so the main driver never loads at all.

---

2. [EFI Drivers](docs/02-drivers.md#s2)

3. [Installation Steps](docs/03-install.md#s3)

4. [Known Issues & Limitations](docs/04-known-issues.md#s4)

5. [Patch Notes](docs/05-patches.md#s5)

Appendix A. [WhateverXe Upgrade Notes (0.7.0 → 0.8.0)](docs/06-wex-upgrade.md#s6)

## 6. Credits & References

| Project | Used for |
| --- | --- |
| [**WhateverXe**](https://github.com/b00t0x/WhateverXe) (b00t0x) | Foundation of the whole iGPU solution; our patch is based on the 0.8.0 source |
| [WhateverXe-patched OCLP](https://github.com/b00t0x/OpenCore-Legacy-Patcher) | Installs the donor graphics drivers (`WhateverXe-Graphics` pkg) |
| [**nvidia-macos-driver**](https://github.com/nullmoth/nvidia-macos-driver) (NullMoth) | `NVRM` / `NVAccel` / `NVRMFB` / `NVRMAGDC` + `NVMTLDriver`; provides Metal 3 and NVDEC / NVENC hardware codecs |
| [**VoodooI2C**](https://github.com/VoodooI2C/VoodooI2C) | I2C trackpad; PR **#586** supplies the TGL-H `0x43e8` match table |
| [AirportItlwm](https://github.com/laobamac/itlwm) | Intel Wi-Fi |
| [**MECHREVO-GM6AR57C-OpenCore**](https://github.com/559911/MECHREVO-GM6AR57C-OpenCore) (559911) | Section 4.8's `hwSetPanelPower` no-op when not powering on, and the `setDCState` DC guard; a key reference while debugging the black screen after display sleep |
| [Samsung NP550XDA EFI](https://github.com/cost-12/Hackintosh-Samsung-Book-INTEL-CORE-I3-1115G4-11TH) (cost-12) | A comparable Tiger Lake + WhateverXe configuration |
| [`patches/whateverxe-0.8.0-gt1.patch`](../patches/whateverxe-0.8.0-gt1.patch) (in use) | Patched WhateverXe 0.8.0: fuse override, `-wex-edp-keep`, doze-hold, PAVP guard. See [Patch Notes](docs/05-patches.md#s5-3) and [Appendix A](docs/06-wex-upgrade.md#s6) |
| [`patches/whateverxe-0.7.0-gt1.patch`](../patches/whateverxe-0.7.0-gt1.patch) (historical) | Kept for reference |

This repo is **only a usage and troubleshooting log**. All drivers, the bootloader, and donor packages belong to their respective authors. If links break or versions change, defer to the upstream repos.

**License note**: the documentation and original tools here are under [MIT](../LICENSE). The patch under `patches/` is a derivative of upstream WhateverXe 0.7.0 / 0.8.0 and stays under its **BSD-3-Clause** license (Copyright © 2018 vit9696); keep the upstream copyright notice and disclaimer when redistributing it.

---

## 7. Applicability & Disclaimer

- Verified on this one machine only (iGPU `8086:9A68`, dGPU `10de:25a0`, macOS 15.8.1 `24H32`).
- **Do not copy the boot-args and patch onto other models**: this 11400H has an unusual fuse `video=4`; most GT1 CPUs that work in the community are `video=1`, and the patch was written for this single value.
- Editing EFI, replacing system drivers, and lowering SIP can brick the machine or lose data. Back up the entire EFI partition first and keep a bootable USB drive ready.
- This is a personal log, not an official support channel. Report issues upstream.
