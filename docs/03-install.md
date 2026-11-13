← [返回 README](../README.md)

<a id="s3"></a>

## 3. 安装步骤

基础 EFI 用任意自动配置工具生成，或从仓库下载现成 EFI 起步。下面只列**必须额外做的部分**。

**第 1 步 · 触摸板**

1. 打开 `VoodooI2C.kext/Contents/Info.plist`，按 [VoodooI2C PR #586](https://github.com/VoodooI2C/VoodooI2C/pull/586) 补 TGL-H 匹配：`VoodooI2CPCITigerLakeHController` / `IOPCIMatch = 0x43e88086&0xFFFCFFFF` / 时钟 133MHz、SdaHold 42、SdaFalling 171、SclFalling 208。官方 2.9.1 二进制本身能用，只改 plist 不影响签名，不用重编译。
2. 加 `SSDT-GPI0.aml` + `SSDT-XOSI.aml`，启用 `GPI0 _STA→XSTA`、`_OSI→XOSI` 两条 rename。
3. 加 `TPD0 _STA` 精确补丁，强制返回 `0x0F`，`Count=1`。
4. 保留 `-vi2c-force-polling`。

```bash
kextstat | grep -Ei 'voodoo|ps2'
ioreg -l | grep -E 'TPD0|PNP0C50'
```

看到 `TPD0` registered / matched / active，且 `VoodooI2CHID`、`VoodooInput` 已加载即成。

**第 2 步 · 装 donor 驱动**

从 [WhateverXe](https://github.com/b00t0x/WhateverXe) Release 装 `WhateverXe-Graphics` pkg（本机 **0.4.3**，与 WEX **0.8.2** 必须配套），再 `kmutil inspect | grep -i TGL` 确认三个 kext 进了 AuxKC。

装完**立刻**把 VA 驱动改回 `.disabled`（pkg 的 payload 会把它装回来），否则下一步开加速后一解码就 panic：

```bash
sudo mv /Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle \
        /Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle.disabled
ls -ld /Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle*   # 只应剩 .disabled*
```

<a id="s3-3"></a>

**第 3 步 · 编译补丁版 WhateverXe**

官方 0.8.2 仍不认这颗 11400H（fuse `video=4`），必须用[本仓库补丁](05-patches.md#s5-4)。

```bash
git clone https://github.com/b00t0x/WhateverXe.git && cd WhateverXe
git checkout <0.8.2 对应的 tag 或 commit>
patch -p1 < /path/to/ASUS-TGL-H45-OpenCore/patches/whateverxe-0.8.2-gt1-backlight.patch
python3 tools/build.py --release --sdk /path/to/MacKernelSDK-master \
  --lilu /path/to/Lilu.kext --output build
```

补丁是**合并版**：GT1 系列（fuse 放行 / 三开关 / PAVP 守卫 / doze-hold）与**背光 duty 修正**在同一份文件里，`patch -p1` 应 **16 个 hunk 全过、0 个 `.rej`**。不要只挑其中一部分——0.8.2 升级时试过只搬背光 hook，结果又是 7 MB。

依赖 MacKernelSDK、Lilu 1.7.2 SDK、Command Line Tools。两个坑：Lilu 头文件是符号链接，组装 `Lilu.kext/Contents/Resources/{Headers,Library}` 时必须 `cp -RL` 解引用；重编译前 `rm -rf build`。

放进 `EFI/OC/Kexts/` 后**务必验证参数真的编进去了**（曾因放了旧二进制、boot-args 被静默忽略而白测一轮）：

```bash
K=EFI/OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe
strings -a $K | grep -c -E '\-wex-gt1|WEXEDPKeep'   # 必须 8
strings -a $K | grep -c WhateverXeGraphicsABI        # 必须 ≥1（Compat 0.8.1 的门槛）
strings -a $K | grep -c TGLPanelBacklightReady       # 必须 ≥1（背光修正）
```

**第 4 步 · 装独显驱动**

按 [nullmoth/nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver) 说明安装（本机 2.7.2）。需要降低 SIP 和 AMFI 限制，装前看清它的 README。

<a id="s3-5"></a>

**第 5 步 · 两个手工改动**

```bash
# A. 停用核显 VA 驱动（不做会 kernel panic）
sudo chmod 000 /Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle

# B. 修 MTLDriver 内存泄漏并重新签名（先备份原文件！偏移 0x7ed87: 75 0d -> 90 90）
sudo python3 - <<'PY'
p='/Library/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle/Contents/MacOS/AppleIntelTGLGraphicsMTLDriver'
d=bytearray(open(p,'rb').read())
assert d[0x7ed87:0x7ed89] == b'\x75\x0d', '版本不匹配，请先核对偏移'
d[0x7ed87:0x7ed89] = b'\x90\x90'
open(p,'wb').write(d)
PY
sudo codesign -f -s - /Library/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle/Contents/MacOS/AppleIntelTGLGraphicsMTLDriver
```

A 让 VideoToolbox 绕开熔断的核显媒体引擎，解码落到独显 NVDEC；B 堵掉每次提交命令缓冲漏约 90KB 的问题（原版 50 次提交 RSS 5.0→9.5MB，改后 5.0→5.7MB）。**系统更新或重装 donor 包会覆盖这两处，届时要重打。**

**回滚速查**

| 症状                 | 动作                                                      |
| ------------------ | ------------------------------------------------------- |
| 不开机 / kernel panic | 换回官方 `WhateverXe.kext`，boot-args 去掉三个 `-wex-*`          |
| 只有 7MB 显存          | 三查：donor pkg 是否装好且 AuxKC 有效、`strings` 里 GT1 字符串是否 8 个、kext 是否带 `WhateverXeGraphicsABI`（Compat 0.8.1 会检查它） |
| 全黑但有声音             | 确认 `-wex-edp-keep` 在、且二进制认这个参数                          |
| 熄屏后不亮              | `strings` 搜 `WEXEDPDozeHoldCount`，确认是带 doze-hold 的补丁版   |
| 硬解又 panic 了        | 检查 `AppleIntelTGLGraphicsVADriver.bundle` 是否已改名 `.disabled`（或 `chmod 000`）；`sudo bash tools/accel-trial.sh off` 可一键回退 |
| 开机到进度条尽头自动重启 | 这是 `VTDecoderXPCService` 的媒体引擎 panic（CR2=`0x284`），确认 Intel VADriver 已下线，见[附录 A](06-wex-upgrade.md#s6-5) |

每次改 EFI 前留一份备份，改完用 `plutil -lint config.plist` 检查格式。
