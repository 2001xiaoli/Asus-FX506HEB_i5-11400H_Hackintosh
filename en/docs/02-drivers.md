← [Back to English README](../README.md)

<a id="s2"></a>

## 2. EFI Drivers

Three layers: kexts injected via `config.plist → Kernel/Add`, donor / NVIDIA drivers installed into the system, and binaries patched by hand.

### Injected kexts (all enabled)

Grouped by function, versions in parentheses; the `.kext` suffix is omitted throughout:

- **Base**: Lilu 1.7.3, VirtualSMC 1.3.9, AMFIPass 1.4.1, **WhateverXe 0.8.0 (patched build, the core of this setup)**
- **Display / audio / power**: AppleALC 1.9.9, BrightnessKeys 1.0.4, CpuTscSync 1.1.3, RestrictEvents 1.1.7, SMCBatteryManager / SMCLightSensor / SMCProcessor 1.3.9
- **USB / storage**: USBToolBox 1.2.0, UTBMap 1.1, XHCI-unsupported 0.9.2, NVMeFix 1.1.4, PC711Probe 1.8.1
- **Wireless**: AirportItlwm 2.4.0, BlueToolFixup 2.7.3, IntelBTPatcher 2.5.0, IntelBluetoothFirmware 2.5.0
- **Input**: VoodooPS2Controller + VoodooPS2Keyboard 2.3.8, VoodooI2C 2.9.1 (**Info.plist patched with the TGL-H ID**), VoodooI2CHID 1, plugins VoodooInput 1.1.7 / VoodooGPIO 1.1 / VoodooI2CServices

The I2C group must be ordered "plugins → main kext → satellite": `VoodooInput → VoodooGPIO → VoodooI2CServices → (the two PS/2 kexts) → VoodooI2C → VoodooI2CHID`. For PS/2, inject only the Keyboard plugin — not its bundled Mouse / Trackpad / VoodooInput — to avoid duplicating the I2C stack.

### Drivers installed into the system

- `WhateverXe-Graphics-0.4.1.pkg` → `/Library/Extensions/AppleIntelTGLCompat.kext` (0.8.0), `AppleIntelTGLGraphics.kext` (16.0.32), `AppleIntelTGLGraphicsFramebuffer.kext` (16.0.32), plus four bundles under `/Library/GPUBundles/` (`MTLDriver`, `GLDriver`, `XeCompilerAdapter`, `VADriver`). **`VADriver` must stay renamed to `.disabled`**, otherwise enabling acceleration panics on the first decode — see [Appendix A](06-wex-upgrade.md#s6-5)
- NullMoth `nvidia-macos-driver` 2.7.2 → `NVRM` (GSP-RM port; manages VRAM and interrupts), `NVAccel` (registers IOAccelerator), `NVRMFB`, `NVRMAGDC` in `/Library/Extensions`; plus `/Library/GPUBundles/NVMTLDriver.bundle`

Besides the Metal translation layer, `NVMTLDriver.bundle` ships a full codec set: `libnvdec_h264.dylib`, `libnvdec_h264_t2d.dylib`, `libnvdec_hevc.dylib`, `libnvenc_h264_ga10x.dylib`, `libnvenc_hevc_ga10x.dylib`, `libnvmtl_translate.dylib`. These `libnvdec_*` libraries register decoders with VideoToolbox, so **H.264 / HEVC hardware decode actually runs on the dGPU's NVDEC**. Registration requires the host process to have VideoToolbox loaded; the allowlist `/Library/GPUBundles/nvmtl-allow.txt` contains `*` and `!WindowServer`.

### ACPI

All 11 SSDTs are enabled (the `SSDT-` prefix and `.aml` suffix are omitted below): `SBUS`, `Disable_Network_RP15`, `EC`, `GPI0`, `MCHC`, `PLUG`, `RTCAWAC`, `USB-Reset`, `USBX`, `XOSI`, **`PNLF`** (i.e. `SSDT-PNLF.aml`, `_UID=19` / `APP0002`, handles the brightness keys).

| Patch | Purpose |
| --- | --- |
| `GPI0 _STA` → `XSTA` | Lets the custom GPIO SSDT take over |
| `_OSI` → `XOSI` | Enables `SSDT-XOSI` |
| **`TPD0 _STA` forced to `0x0F`** | Exposes the ELAN1203 that the DSDT hides behind its Windows branch (I2C0 only, `Count=1` exact match) |

<a id="s2-4"></a>

### boot-args

Full value of `nvram boot-args` on this machine:

```
alcid=48 debug=0x100 keepsyms=1 -vi2c-force-polling
amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0
gfxrst=4 -allow3d -disablegfxfirmware
-wex-gt1-fb-only -wex-gt1-accel -wex-edp-keep
nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth
```

Standard items: audio layout, keep panic symbols, I2C polling (GPIO interrupts do not work here), allow re-signed drivers, and WhateverXe's required `-allow3d -disablegfxfirmware`. The last line belongs to NullMoth's dGPU. The three `-wex-*` flags come from our patch:

| Flag | Purpose |
| --- | --- |
| `-wex-gt1-fb-only` | Run the framebuffer only; do not start the accelerator |
| `-wex-gt1-accel` | Re-enable the iGPU accelerator together with the PAVP guard (Metal 2) |
| `-wex-edp-keep` | Keep the firmware-trained eDP link; skip the full modeset |

Two **system-level changes must be made by hand**: disable the iGPU VA driver and fix the MTLDriver leak. Commands are in [Installation Step 5](03-install.md#s3-5).
