← [Back to English README](../README.md)

<a id="s6"></a>

## Appendix A. WhateverXe Upgrade Notes (0.7.0 → 0.8.0 → 0.8.2)

<a id="s6-1"></a>

### A.1 Version pairing is mandatory

| Component | Version | Notes |
| --- | --- | --- |
| WhateverXe kext | **0.8.2** (patched build here) | 1,845,040 B / sha256 `e0bbc744…4026` |
| WhateverXe Graphics pkg | **0.4.3** | ships Compat **0.8.1** plus GLDriver / XeCompilerAdapter |
| donor (`/Library/Extensions`) | Graphics / Framebuffer **16.0.0**, Compat **0.8.1** | Installed by the pkg; measured 16.0.0, not the 16.0.32 older docs claimed |

- **0.8.2 must be paired with 0.4.3, and a mismatch is a hard failure.** Install the pkg first, then the kext, then reboot; reverse order or "only half the upgrade" drops VRAM to 7 MB.
- The reason is Compat 0.8.1 implementing upstream's "preserve firmware display output when only one of the two graphics components is installed": it checks whether WEX publishes `WhateverXeGraphicsABI`, and if not, logs `WEX inactive; leaving firmware graphics in control` and never takes over. The 0.8.0 kext has no such property, so "new Compat + old kext" = 7 MB.
- Official device IDs are still `9A40 / 9A49 / 9A78` — **this machine's `9A68` is not supported**, so the stock binary is never an option.
- Historical pairs: 0.7.0 ↔ 0.4.0, 0.8.0 ↔ 0.4.1 (their Compat was 0.8.0 with no ABI check, so a mismatch only lost features instead of instantly dropping the driver).

<a id="s6-2"></a>

### A.2 What upstream changed (0.8.0 → 0.8.2, only what matters here)

0.8.0:

| Kind | Change | Relevance |
| --- | --- | --- |
| Added | Raptor Lake-U support | none |
| Added | Experimental system sleep / wake | **none** — MIPI DSI laptops with specific ACPI only; this is an eDP panel |
| Added | MiniBook X 60 Hz mode | none |
| Fixed | Regression in 0.7.0 that dropped graphics acceleration on some supported Tiger Lake configs | relevant |
| Fixed | Restart / shutdown issues | relevant |
| Fixed | Compatibility with kernel/driver code relocation after macOS updates | relevant |
| Requires | Latest WhateverXe Graphics | see A.1 |

0.8.1 / 0.8.2 (CHANGELOG has no separate 0.8.2 entry; the substance comes from 0.8.1 plus its matching Compat):

| Kind | Change | Relevance |
| --- | --- | --- |
| Changed | **Preserve firmware display output when only one component is installed** (`WEX inactive; leaving firmware graphics in control`) | **critical** — this is where the 7 MB fallback comes from, together with Compat 0.8.1's `WhateverXeGraphicsABI` check |
| Added | Experimental 10-bit framebuffer for MIPI DSI panels | none (eDP) |
| Fixed | Missing / duplicate display-wake notifications after sleep | none (S3 is dead on this machine anyway) |
| Fixed | Graphics memory mapping at buffer boundaries | possibly relevant, not verified separately |
| Requires | Graphics 0.4.3 | see A.1 |

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

The patched source tree itself is **not in this repo** (we only ship our own changes) — apply the patch to a fresh checkout of the matching upstream version.

> This section records the **0.8.0** round. Since 0.8.2 the combined patch `patches/whateverxe-0.8.2-gt1-backlight.patch` is used (16 hunks: GT1 series + backlight duty fix), producing 1,845,040 B / sha256 `e0bbc744…4026`; details in [5.4](05-patches.md#s5-4) and [A.10](#s6-10). The porting method is unchanged: upstream source plus this repo's patch, never just part of it.

<a id="s6-4"></a>

### A.4 Six pitfalls

1. **A stock kext in EFI drops VRAM to 7 MB.** Symptoms: `Intel UHD Graphics 7 MB`, no `AppleIntelTGLGraphicsFramebuffer` instance, `IOFBMemorySize = 8294400` (exactly one 1920×1080×4 frame → `IONDRVFramebuffer` fallback). Cause: stock `decodeSmallGT` accepts only `video ∈ {1,5}`; this machine reports `video=4`, so every `-wex-gt1-*` boot-arg becomes a no-op. Quick check: `strings` on the patched binary finds 8 `-wex-gt1-*` / `WEXEDPKeep` entries; the stock one finds 0.

2. **Writing `config.plist` on FAT32 can silently fail.** `Path.write_bytes()` returned but the byte count did not change. Use `open(...,"wb") + flush + os.fsync()`, then **read back and compare in the same function**.

3. **Never remove `-wex-gt1-fb-only`.** The fuse override that admits `video=4` lives on that path. To enable acceleration, **add** `-wex-gt1-accel`; the working combination is:

```
-wex-gt1-fb-only -wex-gt1-accel -wex-edp-keep
```

`WhateverXeGT1FramebufferOnly=Yes` and `WhateverXeGT1AcceleratorTrial=Yes` **coexisting is normal**: the former enables the fuse override, the latter actually releases the accelerator.

4. **Porting only the new patch and forgetting the old one also gives 7 MB.**

   Hit during the 0.8.2 upgrade: the fresh upstream tree received only the "backlight hook" change, while the 15 hunks of `patches/whateverxe-0.8.0-gt1.patch` were dropped.
   Symptoms are **identical to pitfall 1** (7 MB, no framebuffer instance), but the cause is "a partially patched build" rather than "a stock build".
   The check is the same: `strings` must show **8** `-wex-gt1-*` + `WEXEDPKeep` entries; 0 means no patch at all, 1–7 means a partial one.

5. **A Graphics pkg upgrade can raise the Compat ABI requirement → 7 MB.**

   0.4.3 installs `AppleIntelTGLCompat 0.8.1`, which adds the `WhateverXeGraphicsABI` check and the log line `WEX inactive; leaving firmware graphics in control`: **without that property WEX never takes over and graphics fall back to firmware**.
   So "new Compat + old kext" is 7 MB even with a fully patched binary. Check: `strings <WEX> | grep -c WhateverXeGraphicsABI`; 0 means the kext is too old, and in a healthy boot `ioreg` shows `<01000000>`.
   **This turns A.1's "versions must pair" from advice into a hard failure: a mismatch no longer just loses features, it drops the driver.**

6. **The Graphics pkg restores the Intel VA driver → panic late in boot.**

   The pkg payload contains `AppleIntelTGLGraphicsVADriver.bundle`, so every install puts it back; with `video=4` (no VCS0/VECS0 here), an enabled VA driver plus an active accelerator means the system's own decode at login crashes the machine.
   Signature: `Panicked task: VTDecoderXPCService`, `Fault CR2: 0x284`, backtrace containing `AppleIntelTGLGraphics → IOAcceleratorFamily2`, uptime 60–70 s ("progress bar completes then auto-reboots").
   **After every pkg install, confirm `AppleIntelTGLGraphicsVADriver.bundle` is gone and only `.disabled` remains.**

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
# 1) is the patched 0.8.2 kext loaded?
kextstat | grep -i whateverxe

# 2) fuse override, eDP keep, PAVP guard, ABI, backlight hook all Ready?
ioreg -l | grep -E "XELPSmallGTFuseExtension|WEXEDPKeepReady|TGLWEGRoutePAVPGuard|WhateverXeGT1|WhateverXeGraphicsABI|TGLPanelBacklightReady"

# 3) should be 2 accelerators (iGPU + dGPU)
ioreg -rc IOAccelerator | grep -c IOClass

# 4) iGPU Metal + resolution / refresh rate
system_profiler SPDisplaysDataType | head -25

# 5) any new panic?
ls -lat /Library/Logs/DiagnosticReports/*.panic | head -3

# 6) does full brightness really reach ~100%? (99.8% with our fix; check-brightness-kext.sh lives in the local workspace, not in this repo)
bash tools/check-brightness-kext.sh
```

Verified values on the passing 0.8.2 boot:

| Item | Value |
| --- | --- |
| iGPU accelerator | `IOClass = IntelAccelerator`, `MetalPluginName = AppleIntelTGLGraphicsMTLDriver`, `IOGVACodec = Gen10` |
| Actually doing work | `textureCount = 1644`, `contextGLCount = 2`, `context2DCount = 3`, `gartUsedBytes ≈ 318 MB` |
| Metal | iGPU **Metal 2** (that MTLDriver tops out at Metal 2; the dGPU is Metal 3) |
| VRAM / display | 1536 MB, 1920×1080@144 Hz, `IOFBMemorySize = 268435456` |
| WEX state | `XELPSmallGTFuseExtension=Yes`, `WEXEDPKeepReady=Yes`, `TGLWEGRoutePAVPGuard=Yes`, `WhateverXeGraphicsABI=<01000000>` |
| Backlight | `TGLPanelBacklightReady=Yes`, full-brightness duty `95806 / 96000 = 99.8%` |

<a id="s6-7"></a>

### A.7 Upgrade order for next time

**Rule: the order is fixed and the gates are enforced by a script, not by "remember to also run this".**

#### Phase 0 — preparation (before touching anything)

1. **Back up the whole `/Volumes/EFI/EFI/OC`** into `backups/EFI-OC-before-WEX-<version>-<time>/`.
2. **Record the baseline**: current `CFBundleVersion`, binary sha256, the three `strings` counts (GT1 / ABI / backlight), Compat version, whether the VA bundle exists.
3. **Confirm the rescue path**: `config.plist.good` exists with `-wex-noaccel`, and the OpenCore picker has `Rescue: UEFI Shell`.

#### Phase 1 — build (all patches in the source tree)

4. Take the new upstream tree and **replay every in-house patch** before anything else:

```bash
patch -p1 -F3 < patches/whateverxe-0.8.2-gt1-backlight.patch   # 16 hunks, 0 .rej
grep -c 'wrapTGLPanelBacklight' WhateverXe/kern_xe.cpp          # backlight hook must be there too
```

5. **Build + string gate** (do not proceed if this fails):

```bash
python3 tools/build.py --release --sdk /path/to/MacKernelSDK-master \
  --lilu /path/to/Lilu.kext --output build

K=build/WhateverXe.kext/Contents/MacOS/WhateverXe
strings -a $K | grep -c -E '\-wex-gt1|WEXEDPKeep'   # must be 8
strings -a $K | grep -c WhateverXeGraphicsABI        # must be >= 1
strings -a $K | grep -c TGLPanelBacklightReady       # must be >= 1
shasum -a 256 $K                                     # record it
```

#### Phase 2 — install the pkg first

6. `sudo installer -pkg WhateverXe-Graphics-<version>.pkg -target /` and let it rebuild the aux kernel collection.
7. **Immediately disable the VA driver** (A.4-6): `sudo mv /Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle{,.disabled}`, then confirm only `.disabled*` entries remain.
8. Confirm the actual Compat version with `PlistBuddy -c 'Print :CFBundleVersion' /Library/Extensions/AppleIntelTGLCompat.kext/Contents/Info.plist`.

#### Phase 3 — swap the kext and refresh the rescue config

9. Deploy the new kext into `Kexts/WhateverXe.kext` and **read it back byte-for-byte** (FAT32 silently lies, A.4-2).
10. Assert version / sha256 / GT1=8 / ABI / backlight hook; on any mismatch restore the Phase 0 backup immediately.
11. Sync the `Comment` in `Kernel/Add` to `V<version>`.
12. **Regenerate `config.plist.good`**: same config with `-wex-gt1-accel` replaced by `-wex-noaccel`, so a bootable path always exists.

> Steps 7 and 10–12 are chained by `finish-wex-0.8.2.sh` in the local workspace (**not in this repo**, it contains machine-specific absolute paths): any failure aborts via `set -e` and leaves EFI untouched; only a full pass prints "safe to reboot". On another machine, do 7–12 by hand as listed.

#### Phase 4 — reboot and verify

13. Reboot and run the A.6 checklist (the local workspace has an automated `check-wex-0.8.2.sh`, not in this repo).
14. Pass criteria: `VRAM 1536 MB`, `IOFBMemorySize=268435456`, `WhateverXeGraphicsABI=<01000000>`, `WEXEDPKeepReady=Yes`, `TGLPanelBacklightReady=Yes`, full-brightness duty ≈99.8%, no new panic.

#### Phase 5 — when it fails (triage by symptom, do not guess)

| Symptom | Cause | Action |
| --- | --- | --- |
| 7 MB VRAM but it boots | GT1 patch incomplete (A.4-1/4), or Compat is newer than the kext (A.4-5) | `strings` for GT1=8 and ABI≥1, then check the Compat version; both must hold |
| Auto-reboot at the end of the progress bar (~68 s) | VA driver restored and the accelerator enabled (A.4-6) | See A.5; restore `config.plist.good` from the UEFI Shell, then disable VA |
| Black screen, no panic | eDP re-train failed | Check `-wex-edp-keep` and `WEXEDPKeepReady` |

Roll back with a whole-package script (Compat + GPUBundles + kext + KC rebuild together), never by hand-editing a single piece; `rollback-wex-0.8.2.sh` in the local workspace does that.

<a id="s6-8"></a>

### A.8 Remaining limitations

| Item | Status |
| --- | --- |
| Lid-close / S3 sleep | Still broken; test with `pmset displaysleepnow` |
| Intel Quick Sync | Intentionally disabled (no VCS0 in fuses); decode via dGPU NVDEC or software |
| iGPU Metal version | Metal 2; UI is hardware accelerated, Metal 3-only features are not |
| HDMI | Still broken — abnormal output or black screen |

<a id="s6-9"></a>

### A.9 What is in this repo

| Path | Notes |
| --- | --- |
| `oc/config.plist` | Matches the working machine, but the four SMBIOS identifiers are **placeholders** — generate your own before booting |
| `oc/config.plist.good` | Same config with `-wex-noaccel`, also sanitized; this is what the Rescue shell restores |
| `oc/Kexts/WhateverXe.kext` | Patched 0.8.2 binary (1,845,040 B / sha256 `e0bbc744…4026`) |
| `patches/whateverxe-0.8.2-gt1-backlight.patch` | In use: GT1 series + backlight duty fix, 16 hunks against stock 0.8.2 |
| `patches/whateverxe-0.8.0-gt1.patch` | 0.8.0-era patch, kept as the porting baseline; `whateverxe-0.7.0-gt1.patch` likewise |
| `tools/accel-trial.sh` | `on` / `off` / `status` toggle for acceleration and the Intel VA driver |
| `tools/sanitize-efi.py` | Produces a sanitized EFI copy and rescans for the four identifiers |

<a id="s6-10"></a>

#### Final state (measured on the successful boot)

| Item | Value |
| --- | --- |
| WhateverXe | **0.8.2**, 1,845,040 B, sha256 `e0bbc744…4026` |
| Binary gates | GT1 strings **8**, `WhateverXeGraphicsABI` **1**, `TGLPanelBacklightReady` **1** |
| Compat | **0.8.1** |
| VA driver | only `.disabled` entries |
| Accelerator | `VRAM 1536 MB`, `Metal 2`, `IOFBMemorySize = 268435456` |
| WEX state | `WhateverXeGraphicsABI=<01000000>`, `WEXEDPKeepReady=Yes`, `TGLPanelBacklightReady=Yes` |
| Backlight | full-brightness duty `95806 / 96000 = 99.8%` |
| boot-args | unchanged: `-wex-gt1-fb-only -wex-gt1-accel -wex-edp-keep` |

> Note: older docs said the donor was `16.0.32`; the machine actually has **16.0.0** for both `AppleIntelTGLGraphics` and `Framebuffer`, and A.1 has been corrected. The backlight hook's entry bytes `55 48 89 e5 41 56 53 48 ff 05 90 44 09 00` (offset `0x4A56A`) match 16.0.0 exactly; if the donor ever changes, re-verify those bytes — if they do not match, the hook is not installed (brightness falls back to 18.5%, but nothing crashes).
