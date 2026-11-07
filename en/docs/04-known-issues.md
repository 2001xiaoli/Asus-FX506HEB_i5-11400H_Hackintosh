← [Back to English README](../README.md)

<a id="s4"></a>

## 4. Known Issues & Limitations

⚠️ **S3 system sleep cannot wake; closing the lid hangs the machine**: after `pmset sleepnow` or closing the lid, neither the keys nor the power button respond — hold the power button to force a reboot. `pmset -g log` shows no Wake entries at all, only `Failure during sleep: 0x5F9100000012`. Display sleep only exercises the GPU Doze/Wake state machine (already fixed); S3 involves PCI D3, GPU power wells, and a full framebuffer rebuild — a completely different path. **Workaround: disable automatic sleep and shut down before closing the lid.**

| Limitation | Details |
| --- | --- |
| No VP9 / AV1 hardware decode | `VTIsHardwareDecodeSupported()` reports only H.264 / HEVC; the bundle has no matching decoders. 4K AV1 is CPU-only — prefer HEVC / H.264 sources for streaming |
| iGPU media engine fused off | `video=4` → VCS0 / VECS0 do not exist. Forcing the iGPU accelerator through VideoToolbox panicked twice, both in `IGHardwareRingBufferMedia::init` with `scheduler->cs[1]` == NULL. It's a silicon-level gap a patch cannot fake; the price is keeping VADriver at `chmod 000` |
| Internal panel wired to the iGPU only | Optimus has no MUX; the eDP panel runs on the iGPU and the dGPU never drives a display |
| Thunderbolt / USB4 | Hardware present, no driver on the macOS side |
| MTLDriver is ad-hoc signed | Re-signed after the leak fix, loads under `amfi=0x80`; a macOS update or donor reinstall overwrites the patch and the 90KB-per-submission leak returns |
| iGPU is Metal 2 only | A 4096-thread compute kernel ran with 0 errors; Metal 3 comes from the dGPU but is not used for desktop compositing |
