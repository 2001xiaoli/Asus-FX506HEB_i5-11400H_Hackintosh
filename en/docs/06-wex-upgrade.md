← [Back to English README](../README.md)

<a id="s6"></a>

## Appendix A. WhateverXe 0.7.0 → 0.8.0 Upgrade Notes

Recorded 2026-11-09 on the ASUS TUF Gaming F15 / Tianxuan 2 (i5-11400H, UHD 9A68, RTX 3050 Ti). This is a reusable checklist for the **next driver upgrade**, not a narrative of the debugging.

<a id="s6-1"></a>

### A.1 Version pairing is mandatory

| Component | Version | Notes |
| --- | --- | --- |
| WhateverXe kext | **0.8.0** (patched build here) | Upstream release 2026-11-07 |
| WhateverXe Graphics pkg | **0.4.1** | 95,200,578 B |
| donor (`/Library/Extensions`) | Graphics / Framebuffer **16.0.32**, Compat **0.8.0** | Installed by the pkg |

- **0.8.0 must be paired with 0.4.1.** Install the pkg first, then the kext, then reboot — otherwise you get a "0.8.0 kext + 0.4.0 payload" mismatch.
- 0.4.1 differs from 0.4.0 by only **217 B**; the donor binaries did not change. Only the generic compatibility component changed (no exact kernel build string required).
- Official device IDs are still `9A40 / 9A49 / 9A78` — **this machine's `9A68` is not supported**, so the stock binary is never an option.

<a id="s6-2"></a>

### A.2 What upstream 0.8.0 changed

| Kind | Change | Relevance |
| --- | --- | --- |
| Added | Raptor Lake-U support | none |
| Added | Experimental system sleep / wake | **none** — MIPI DSI laptops with specific ACPI only; this is an eDP panel |
| Added | MiniBook X 60 Hz mode | none |
| Fixed | Regression in 0.7.0 that dropped graphics acceleration on some supported Tiger Lake configs | relevant |
| Fixed | Restart / shutdown issues | relevant |
| Fixed | Compatibility with kernel/driver code relocation after macOS updates | relevant |
| Requires | Latest WhateverXe Graphics | see A.1 |

<a id="s6-3"></a>

### A.3 Patch porting result

- `patches/whateverxe-0.8.0-gt1.patch`: **381 lines**, only `kern_xe.cpp` (319 lines) and `kern_xe.hpp` (62 lines).
- Ported from the 0.7.0 functional diff; `patch -p1 -F3` applied **all 15 hunks, 0 `.rej`**. Line numbers will drift on the next upstream release — port by function, not by position.
- The new `kern_display13_*.inc` files are Display13 / DSI-only and never touch the TGL eDP path. `-wex-edp-keep` hooks by symbol name (not a hardcoded offset), so those refactors were harmless here.
- Build (29 s, 0 errors):

```bash
cd <WhateverXe-0.8.0-source-with-our-patch> && rm -rf build
python3 tools/build.py --release \
  --sdk /path/to/MacKernelSDK-master \
  --lilu /path/to/Lilu.kext --output build
```

- Output: `WhateverXe.kext` **0.8.0 RELEASE / x86_64 / 1,840,416 B / sha256 `28ec9a97…82227`** (stock is 1,720,264 B). Unsigned — OpenCore injection does not need a signature.
- Always `rm -rf build` before rebuilding. Lilu headers are symlinks; dereference them with `cp -RL` before using them as an SDK.

The patched source tree itself is **not in this repo** (we only ship our own changes) — apply the patch to a fresh upstream 0.8.0 checkout.

<a id="s6-4"></a>

### A.4 Three pitfalls you will hit again

1. **A stock kext in EFI drops VRAM to 7 MB.** Symptoms: `Intel UHD Graphics 7 MB`, no `AppleIntelTGLGraphicsFramebuffer` instance, `IOFBMemorySize = 8294400` (exactly one 1920×1080×4 frame → `IONDRVFramebuffer` fallback). Cause: stock `decodeSmallGT` accepts only `video ∈ {1,5}`; this machine reports `video=4`, so every `-wex-gt1-*` boot-arg becomes a no-op. Quick check: `strings` on the patched binary finds 8 `-wex-gt1-*` / `WEXEDPKeep` entries; the stock one finds 0.

2. **Writing `config.plist` on FAT32 can silently fail.** `Path.write_bytes()` returned but the byte count did not change. Use `open(...,"wb") + flush + os.fsync()`, then **read back and compare in the same function**.

3. **Never remove `-wex-gt1-fb-only`.** The fuse override that admits `video=4` lives on that path. To enable acceleration, **add** `-wex-gt1-accel`; the working combination is:

```
-wex-gt1-fb-only -wex-gt1-accel -wex-edp-keep
```

`WhateverXeGT1FramebufferOnly=Yes` and `WhateverXeGT1AcceleratorTrial=Yes` **coexisting is normal**: the former enables the fuse override, the latter actually releases the accelerator.

<a id="s6-5"></a>

### A.5 Key finding: Intel hardware decode must be disabled for Metal to survive

- GT1 fuses `[1,1,0,f0,e00fb]` → `video = (~0xE00FB) & 0xFF = 4`: **only VD2 is exposed, no VCS0/VECS0**.
- Once the accelerator is up, any Intel decode request goes `VTDecoderXPCService` → `IGAccelVideoContextMedia::processDataBuffers` → `IGHardwareRingBufferMedia::init` → `IGScheduler5::bind`, where `scheduler->cs[1]` (the media command streamer) **is always NULL** → page fault, CR2=`0x284`.
- This is silicon fuse programming, **not a driver bug**; patching WhateverXe cannot fix it. Every panic we saw had the same signature:

| Report | Uptime | Meaning |
| --- | --- | --- |
| `Kernel-2026-11-08-120030.panic` | **1230 s** | The machine ran 20.5 minutes with acceleration and only died on a decode → Metal itself is fine |
| `Kernel-2026-11-09-130741 / 132535 / 133712 / 135934` | 70–95 s | Decode triggered late in boot → "progress bar completes then auto-reboots" |

- **Fix**: take the Intel VA driver offline and let VDA fall through to the dGPU (`com.nullmoth.NVMTLDriver` ships `libnvdec_h264/hevc`) or software. `/Library/GPUBundles` is outside the SSV, so a simple rename is reversible:

```bash
sudo mv /Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle \
        /Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle.disabled
```

- Cost: **Intel Quick Sync is unavailable**. That is a hard silicon limit — do not spend more time on it.
- Panic triage: check only three things — is the process `VTDecoderXPCService`, is `CR2` `0x284`, is `AppleIntelTGLGraphics(16.0)` in the backtrace. If all three, it is the media engine and has nothing to do with the framebuffer, Metal, or edp-keep.

<a id="s6-6"></a>

### A.6 Post-upgrade verification

```bash
# 1) is the patched 0.8.0 kext loaded?
kextstat | grep -i whateverxe

# 2) fuse override, eDP keep, PAVP guard all Ready?
ioreg -l | grep -E "XELPSmallGTFuseExtension|WEXEDPKeepReady|TGLWEGRoutePAVPGuard|WhateverXeGT1"

# 3) should be 2 accelerators (iGPU + dGPU)
ioreg -rc IOAccelerator | grep -c IOClass

# 4) iGPU Metal + resolution / refresh rate
system_profiler SPDisplaysDataType | head -25

# 5) any new panic?
ls -lat /Library/Logs/DiagnosticReports/*.panic | head -3
```

Verified values on the passing boot:

| Item | Value |
| --- | --- |
| iGPU accelerator | `IOClass = IntelAccelerator`, `MetalPluginName = AppleIntelTGLGraphicsMTLDriver`, `IOGVACodec = Gen10` |
| Actually doing work | `textureCount = 1644`, `contextGLCount = 2`, `context2DCount = 3`, `gartUsedBytes ≈ 318 MB` |
| Metal | iGPU **Metal 2** (that MTLDriver tops out at Metal 2; the dGPU is Metal 3) |
| VRAM / display | 1536 MB, 1920×1080@144 Hz, `IOFBMemorySize = 268435456` |
| WEX state | `XELPSmallGTFuseExtension=Yes`, `WEXEDPKeepReady=Yes`, `TGLWEGRoutePAVPGuard=Yes` |

<a id="s6-7"></a>

### A.7 Upgrade order for next time

1. **Back up** the whole `/Volumes/EFI/EFI/OC` into a timestamped directory, with the old kext kept separately.
2. **Install the matching Graphics pkg first**, then swap the kext — do it before rebooting.
3. **Replace only** `Kexts/WhateverXe.kext`'s `Info.plist` and binary; verify sha256 against the build output.
4. **Sync the `V0.x.y` Comment** in `Kernel/Add` (cosmetic, but saves confusion).
5. **Confirm boot-args** still contain `-wex-gt1-fb-only -wex-gt1-accel -wex-edp-keep` (plus `nvfb=1 nvaccel=1 nvfbheads=4`).
6. **Check the VA driver is still `.disabled`** — reinstalling the Graphics pkg can put the bundle back.
7. **Reboot → run the five commands in A.6.**
8. **Rollback**: keep `config.plist.good` in EFI (same content but `-wex-noaccel`). The `Rescue: UEFI Shell` entry in the OpenCore picker restores it in one command:

```
cp fs0:\EFI\OC\config.plist.good fs0:\EFI\OC\config.plist
reset
```

`tools/accel-trial.sh on|off|status` automates steps 5–8 (`off` also restores the VA bundle).

<a id="s6-8"></a>

### A.8 Remaining limitations

| Item | Status |
| --- | --- |
| Lid-close / S3 sleep | Still broken; test with `pmset displaysleepnow` |
| Intel Quick Sync | Intentionally disabled (no VCS0 in fuses); decode via dGPU NVDEC or software |
| iGPU Metal version | Metal 2; UI is hardware accelerated, Metal 3-only features are not |
| Thunderbolt / USB4 | Controller present, no macOS driver |

<a id="s6-9"></a>

### A.9 What is in this repo

| Path | Notes |
| --- | --- |
| `oc/config.plist` | Matches the working machine, but the four SMBIOS identifiers are **placeholders** — generate your own before booting |
| `oc/config.plist.good` | Same config with `-wex-noaccel`, also sanitized; this is what the Rescue shell restores |
| `oc/Kexts/WhateverXe.kext` | Patched 0.8.0 binary (sha256 `28ec9a97…82227`) |
| `patches/whateverxe-0.8.0-gt1.patch` | The patch from A.3; the 0.7.0 one is kept for reference |
| `tools/accel-trial.sh` | `on` / `off` / `status` toggle for acceleration and the Intel VA driver |
| `tools/sanitize-efi.py` | Produces a sanitized EFI copy and rescans for the four identifiers |

**Never copy your real `config.plist` (with the real serial / MLB / UUID / ROM) into `oc/`.** Re-run the identifier scan after every sync and confirm zero hits among the files that will be committed.
