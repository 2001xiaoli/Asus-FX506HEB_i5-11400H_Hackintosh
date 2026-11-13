← [返回 README](../README.md)

<a id="s2"></a>

## 2. EFI 驱动情况

三层：`config.plist → Kernel/Add` 注入的 kext、装进系统的 donor / NVIDIA 驱动、手工打过补丁的二进制。

### EFI 注入的 kext（全部启用）

按功能分组，括号内为版本，名称统一省略 `.kext` 后缀：

- **基础**：Lilu 1.7.3、VirtualSMC 1.3.9、AMFIPass 1.4.1、**WhateverXe 0.8.2（本机补丁版，核心）**
- **显示 / 声音 / 电源**：AppleALC 1.9.8、BrightnessKeys 1.0.4、CpuTscSync 1.1.3、RestrictEvents 1.1.7、SMCBatteryManager / SMCLightSensor / SMCProcessor 1.3.9、**AsusSMC 1.4.1**（华硕 EC / 风扇，替代 SMCSuperIO）
- **USB / 存储**：USBToolBox 1.2.0、UTBMap 1.1、XHCI-unsupported 0.9.2、NVMeFix 1.1.4、PC711Probe 1.8.1
- **无线**：AirportItlwm 2.4.0、BlueToolFixup 2.7.3、IntelBTPatcher 2.5.0、IntelBluetoothFirmware 2.5.0
- **输入**：VoodooPS2Controller + VoodooPS2Keyboard 2.3.8、VoodooI2C 2.9.1（**Info.plist 补了 TGL-H ID**）、VoodooI2CHID 1、插件 VoodooInput 1.1.7 / VoodooGPIO 1.1 / VoodooI2CServices

I2C 组顺序必须是「插件 → 主 kext → 卫星」：`VoodooInput → VoodooGPIO → VoodooI2CServices →（PS2 两条）→ VoodooI2C → VoodooI2CHID`。PS/2 只注入 Keyboard 插件，不注入自带的 Mouse / Trackpad / VoodooInput，避免和 I2C 那套重复。

### 装进系统的驱动

- `WhateverXe-Graphics-0.4.3.pkg` → `/Library/Extensions/AppleIntelTGLCompat.kext`（**0.8.1**）、`AppleIntelTGLGraphics.kext`（16.0.0）、`AppleIntelTGLGraphicsFramebuffer.kext`（16.0.0），以及 `/Library/GPUBundles/` 下的 bundle（`MTLDriver`、`GLDriver`、`XeCompilerAdapter`、`VADriver`）。**`VADriver` 必须保持改名 `.disabled`**，否则开加速后一解码就 panic，见[附录 A](06-wex-upgrade.md#s6-5)
  - **Compat 0.8.1 起会检查 `WhateverXeGraphicsABI` 属性**（上游 0.8.1「只装一半组件时保留固件输出」的落地）：kext 不提供就直接 `WEX inactive; leaving firmware graphics in control`，显存掉到 7 MB。这就是"版本必须成对"从建议变成硬失败的原因，见[附录 A](06-wex-upgrade.md#s6-4) 第 5 条
- NullMoth `nvidia-macos-driver` 2.7.2 → `/Library/Extensions` 的 `NVRM`（GSP-RM 移植，管显存/中断）、`NVAccel`（注册 IOAccelerator）、`NVRMFB`、`NVRMAGDC`；外加 `/Library/GPUBundles/NVMTLDriver.bundle`

`NVMTLDriver.bundle` 除 Metal 翻译层外还带完整编解码器：`libnvdec_h264.dylib`、`libnvdec_h264_t2d.dylib`、`libnvdec_hevc.dylib`、`libnvenc_h264_ga10x.dylib`、`libnvenc_hevc_ga10x.dylib`、`libnvmtl_translate.dylib`。这些 `libnvdec_*` 会向 VideoToolbox 注册解码器，所以 **H.264 / HEVC 硬解实际走独显 NVDEC**。注册条件是宿主进程已加载 VideoToolbox；白名单 `/Library/GPUBundles/nvmtl-allow.txt` 是 `*` 加 `!WindowServer`。

### ACPI

11 个 SSDT 全部启用（下列省略 `SSDT-` 前缀与 `.aml` 后缀）：`SBUS`、`Disable_Network_RP15`、`EC`、`GPI0`、`MCHC`、`PLUG`、`RTCAWAC`、`USB-Reset`、`USBX`、`XOSI`、**`PNLF`**（即 `SSDT-PNLF.aml`，`_UID=19` / `APP0002`，管亮度快捷键）。

| 补丁 | 作用 |
| --- | --- |
| `GPI0 _STA` → `XSTA` | 让自定义 GPIO SSDT 接管 |
| `_OSI` → `XOSI` | 让 `SSDT-XOSI` 生效 |
| **`TPD0 _STA` 强制 `0x0F`** | 让 DSDT 里被 Windows 分支藏起来的 ELAN1203 现形（只针对 I2C0，`Count=1` 精确匹配） |

<a id="s2-4"></a>

### boot-args

实机 `nvram boot-args` 完整值：

```
alcid=17 alcverbs=1 -vi2c-force-polling
amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0
gfxrst=4 -allow3d -disablegfxfirmware
-wex-gt1-fb-only -wex-gt1-accel -wex-edp-keep
nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth
```

常规项：声卡 `alcid=17` + `alcverbs=1`（ALC256，扬声器要的是 verbs 通道）、I2C 轮询（本机 GPIO 中断不可用）、放行改签名的驱动、WhateverXe 官方要求的 `-allow3d -disablegfxfirmware`；末行是 NullMoth 独显参数。三个 `-wex-*` 是本机补丁：

| 参数 | 作用 |
| --- | --- |
| `-wex-gt1-fb-only` | 只跑 framebuffer，不启动 accelerator |
| `-wex-gt1-accel` | 配合 PAVP guard 放开核显 accelerator（Metal 2） |
| `-wex-edp-keep` | 保留固件已训练好的 eDP 链路，不做完整 modeset |

另有两个**必须手工做的系统级改动**：停用核显 VA 驱动、修 MTLDriver 内存泄漏，命令见[安装第 5 步](03-install.md#s3-5)。
