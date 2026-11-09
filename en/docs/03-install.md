← [Back to English README](../README.md)

<a id="s3"></a>

## 3. Installation Steps

Generate a base EFI with any automatic configurator, or start from a ready-made EFI downloaded from the repository. Only the **extra steps required here** are listed below.

**Step 1 · Trackpad**

1. Open `VoodooI2C.kext/Contents/Info.plist` and add the TGL-H match from [VoodooI2C PR #586](https://github.com/VoodooI2C/VoodooI2C/pull/586): `VoodooI2CPCITigerLakeHController` / `IOPCIMatch = 0x43e88086&0xFFFCFFFF` / clock 133MHz, SdaHold 42, SdaFalling 171, SclFalling 208. The stock 2.9.1 binary works as-is; editing only the plist does not affect the signature, so no rebuild is needed.
2. Add `SSDT-GPI0.aml` and `SSDT-XOSI.aml`; enable the `GPI0 _STA→XSTA` and `_OSI→XOSI` renames.
3. Add the precise `TPD0 _STA` patch forcing a return of `0x0F` with `Count=1`.
4. Keep `-vi2c-force-polling`.

```bash
kextstat | grep -Ei 'voodoo|ps2'
ioreg -l | grep -E 'TPD0|PNP0C50'
```

You're done when `TPD0` shows registered / matched / active and `VoodooI2CHID` / `VoodooInput` are loaded.

**Step 2 · Install the donor drivers**

From the [WhateverXe](https://github.com/b00t0x/WhateverXe) Releases, install the `WhateverXe-Graphics` pkg (0.4.1 here; must pair with WEX 0.8.0), then run `kmutil inspect | grep -i TGL` to confirm the three kexts landed in the AuxKC.

<a id="s3-3"></a>

**Step 3 · Build the patched WhateverXe**

Stock 0.8.0 still rejects this 11400H (fuse `video=4`), so you must use [this repo's patch](05-patches.md#s5-3).

```bash
git clone https://github.com/b00t0x/WhateverXe.git && cd WhateverXe
git checkout <tag or commit corresponding to 0.8.0>
patch -p1 < /path/to/ASUS-TGL-H45-OpenCore/patches/whateverxe-0.8.0-gt1.patch
python3 tools/build.py --release --sdk /path/to/MacKernelSDK-master \
  --lilu /path/to/Lilu.kext --output build
```

Dependencies: MacKernelSDK, Lilu 1.7.2 SDK, Command Line Tools. Two gotchas: Lilu headers are symlinks, so use `cp -RL` to dereference them when assembling `Lilu.kext/Contents/Resources/{Headers,Library}`; and run `rm -rf build` before every rebuild.

After placing it in `EFI/OC/Kexts/`, **always verify the flags really made it into the binary** (one full test round was wasted on a stale binary whose boot-args were silently ignored):

```bash
strings EFI/OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe | grep -E 'wex-gt1|wex-edp-keep'
```

**Step 4 · Install the dGPU driver**

Follow [nullmoth/nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver) (2.7.2 here). It requires relaxed SIP and AMFI settings — read its README before installing.

<a id="s3-5"></a>

**Step 5 · Two manual changes**

```bash
# A. Disable the iGPU VA driver (otherwise: kernel panic)
sudo chmod 000 /Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle

# B. Fix the MTLDriver leak and re-sign (back up the original first! offset 0x7ed87: 75 0d -> 90 90)
sudo python3 - <<'PY'
p='/Library/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle/Contents/MacOS/AppleIntelTGLGraphicsMTLDriver'
d=bytearray(open(p,'rb').read())
assert d[0x7ed87:0x7ed89] == b'\x75\x0d', 'Version mismatch - check the offset first'
d[0x7ed87:0x7ed89] = b'\x90\x90'
open(p,'wb').write(d)
PY
sudo codesign -f -s - /Library/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle/Contents/MacOS/AppleIntelTGLGraphicsMTLDriver
```

A makes VideoToolbox skip the fused-off iGPU media engine so decoding falls through to the dGPU's NVDEC; B plugs a ~90KB leak on every command-buffer submission (stock: 50 submissions, RSS 5.0→9.5MB; patched: 5.0→5.7MB). **A macOS update or a donor pkg reinstall overwrites both — reapply them afterwards.**

**Rollback quick reference**

| Symptom | Action |
| --- | --- |
| Won't boot / kernel panic | Restore the stock `WhateverXe.kext` and remove the three `-wex-*` flags from boot-args |
| Only 7MB VRAM | Check the donor pkg, AuxKC validity, and whether EFI holds the patched WEX |
| Black screen but audio works | Confirm `-wex-edp-keep` is present and the binary recognizes it |
| Screen stays dark after display sleep | `strings` for `WEXEDPDozeHoldCount` to confirm the doze-hold build |
| Hardware decode panics again | Check that `AppleIntelTGLGraphicsVADriver.bundle` is renamed `.disabled` (or chmod 000); `sudo bash tools/accel-trial.sh off` rolls everything back |
| Auto-reboot at the end of the progress bar | That is the `VTDecoderXPCService` media-engine panic (CR2=`0x284`); confirm the Intel VADriver is offline — see [Appendix A](06-wex-upgrade.md#s6-5) |

Back up the whole EFI before every change, then run `plutil -lint config.plist` to validate the format.
