← [Back to English README](../README.md)

<a id="s5"></a>

## 5. Patch Notes

This repo contains **only our own changes**. Apple donor drivers, the official WhateverXe release package, and patched system binaries are not included — obtain them from the respective upstream projects.

<a id="s5-1"></a>

### 5.1 `patches/whateverxe-0.7.0-gt1.patch`

Against the official **WhateverXe 0.7.0** source, only `WhateverXe/kern_xe.cpp` and `kern_xe.hpp` change (~380 lines of diff, verified with `patch --dry-run`). Line numbers will drift after upstream updates — port it manually using the functional notes below.

- **Eligibility check**: `decodeSmallGT` originally requires `(~fuses[4]) & 0xFF ∈ {1,5}`; this machine's `video=4` is rejected and falls back to a 7MB framebuffer. The patch admits it only when `video==4 && enhance==1` and `smallGTResources()` really resolves 16EU / 4 L3 / 256KiB, publishing `XELPSmallGTFuseExtension` for verification.
- **Three new switches**: `-wex-gt1-fb-only` / `-wex-gt1-accel` / `-wex-edp-keep` (see [Chapter 2](02-drivers.md#s2-4)); their state is written to IORegistry. Also adds `-wex-skip-gputicks`, making `wrapTGLRegisterRead` return 0 for `0x2910` to avoid the 16–17s hard freeze at boot on TGL-H GT1 (see WhateverXe issue #11 and Elezorn's `gputicks-bootarg` branch).
- **Dodging two panics**: `wrapTGLPAVPCommandCallback` returns `0xe00002bc` directly when `[accel+0x1278]` (media engine) is NULL; the pure-virtual call in `AppleIntelPowerWell::init` is avoided because `-wex-edp-keep` bypasses that path.
- **eDP keep and display-sleep wake (the core)**: `wrapTGLRegsNeedUpdate` becomes a sticky suppression `keep = (pipe==2) || tglEdpKeepBroken`, with counters on all three return paths (`KeepCalls` / `KeepPassed` / `KeepAfterDoze`); `wrapTGLDisableDisplay` adds `EDP_KEEP_DOZE_HOLD` so Doze only blanks the backlight without tearing down the pipe; `wrapTGLFBSetPowerState` **records the state before calling the original** (the old order made the guards read stale state); `wrapTGLPanelPower` / `wrapTGLSetDCState` add panel-power and DC6/DC9 guards.

The `EDP_KEEP_SCOPE` / `EDP_KEEP_AFTER_DOZE` branches left over from debugging are kept in the code for comparison. Build and verification commands are in [Installation Step 3](03-install.md#s3-3).

### 5.2 The two-byte MTLDriver patch

| Item | Value |
| --- | --- |
| File | `/Library/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle/Contents/MacOS/AppleIntelTGLGraphicsMTLDriver` |
| Applies to | Sequoia donor 16.0.x, `__TEXT` fileoff = 0 (file offset equals vmaddr) |
| Offset | `0x7ed87`: `75 0d` (`jne`, skips `free` when `m_isOnlyActiveCommandBuffer` is true) → `90 90` (two NOPs, forcing the free path) |
| Finish | `codesign -f -s - <file>` (ad-hoc re-sign) |

Back up the original first and verify the original bytes at that offset (a mismatch means a different donor version — don't force it). Effect: 50 submissions, RSS 5.0→9.5MB becomes 5.0→5.7MB; 5.9MB after 500. Full commands are in [Installation Step 5](03-install.md#s3-5).

<a id="s5-3"></a>

### 5.3 `patches/whateverxe-0.8.0-gt1.patch` (in use)

Against the official **WhateverXe 0.8.0** source: 381 lines of diff touching only `kern_xe.cpp` (319 lines) and `kern_xe.hpp` (62 lines). Ported from the 5.1 functional diff with `patch -p1 -F3` — all **15 hunks applied, 0 `.rej`**. Same features as 5.1; only the line numbers changed. The new `kern_display13_*.inc` files in 0.8.0 are Display13 / DSI-only and never touch the TGL eDP path.

The resulting `WhateverXe.kext` (0.8.0 RELEASE / 1,840,416 B / sha256 `28ec9a97…82227`) is in `oc/Kexts/`. **It must be paired with WhateverXe-Graphics 0.4.1**: install the pkg, then replace the kext, then reboot.

For the upgrade procedure, the three pitfalls, why the Intel VA driver must be disabled (with panic signatures), and the verification checklist, see [Appendix A](06-wex-upgrade.md#s6).
