#!/bin/bash
# 核显加速器实验 · 开机自检
# 用法：bash tools/check-accel.sh
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

echo "===== 1. boot-args ====="
nvram -p 2>/dev/null | grep boot-args

echo
echo "===== 2. WhateverXe 根属性 ====="
for k in WhateverXeGT1AcceleratorTrial TGLWEGRoutePAVPGuard TGLWEGAcceleratorStartRouted \
         TGLWEGAcceleratorObservationsRouted TGLFramebufferStartResult \
         WEXEDPKeepReady WEXEDPKeepFirst WhateverXeBacklightProfileReady \
         WEXEDPKeepCalls WEXEDPKeepPassed WEXEDPKeepAfterDoze \
         WEXEDPDozeHold WEXEDPDozeHoldCount \
         TGLPanelPowerGuardReady TGLPanelPowerOffSkipped \
         TGLWEXFBStateRouted TGLWEXFBDoze TGLWEXFBStateLast \
         TGLWEXDozeDCGuardReady TGLWEXDozeDCGuardHits; do
  v=$(ioreg -l 2>/dev/null | grep -m1 "\"$k\"" | sed 's/.*= //')
  printf '%-38s %s\n' "$k" "${v:-<缺失>}"
done

echo
echo "===== 3. 关键 kext 加载状态 ====="
kextstat 2>/dev/null | grep -Ei "TGL|IntelAccelerator|IOAccelerator|AppleBacklight|WhateverXe" | awk '{print $6, $7}'

echo
echo "===== 4. 显示与显存 ====="
ioreg -rc IOPCIDevice 2>/dev/null | grep -Ei '"VRAM,totalMB"|IOFBMemorySize' | head -5
system_profiler SPDisplaysDataType 2>/dev/null | sed -n '1,25p'

echo
echo "===== 5. 最近 panic（若有）====="
ls -t /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -3
for f in $(ls -t /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -1); do
  echo "--- $f ---"
  grep -E "panic\(|Panic|Kernel Extensions in backtrace|@/|com\.apple\.driver|org\.b00t0x" "$f" | head -20
done

echo
echo "===== 6. MTLDriver 泄漏补丁状态 ====="
MTL="/Library/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle/Contents/MacOS/AppleIntelTGLGraphicsMTLDriver"
if [ -f "$MTL" ]; then
  /usr/bin/python3 -c "
d=open('$MTL','rb').read()
b=d[0x7ed87:0x7ed89].hex()
print('bytes@0x7ed87 =', b, '=>', 'PATCHED (90 90, 已修泄漏)' if b=='9090' else ('ORIGINAL (75 0d, 有泄漏)' if b=='750d' else 'UNKNOWN'))
"
  codesign -dv "$MTL" 2>&1 | grep -E "Signature|Authority" | head -3
else
  echo "MTLDriver 缺失"
fi

echo
echo "===== 7. 结论速判 ====="
if ioreg -rc IntelAccelerator 2>/dev/null | grep -q "IOClass"; then
  echo "IntelAccelerator: 已实例化"
else
  echo "IntelAccelerator: 未实例化（仍无加速）"
fi
if system_profiler SPDisplaysDataType 2>/dev/null | grep -qi "Metal"; then
  system_profiler SPDisplaysDataType 2>/dev/null | grep -i Metal
else
  echo "Metal: 未报告"
fi
if ioreg -l 2>/dev/null | grep -q '"TGLWEGRoutePAVPGuard" = Yes'; then
  echo "PAVP guard: 已生效"
fi
if ioreg -l 2>/dev/null | grep -q '"TGLPanelPowerGuardReady" = Yes'; then
  echo "面板电源守卫: 已生效（非上电状态 no-op）"
else
  echo "面板电源守卫: 未安装（旧版 WEX）"
fi
hold=$(ioreg -l 2>/dev/null | grep -m1 '"WEXEDPDozeHoldCount"' | sed 's/.*= //' | tr -d ' ')
afterdoze=$(ioreg -l 2>/dev/null | grep -m1 '"WEXEDPKeepAfterDoze"' | sed 's/.*= //' | tr -d ' ')
passed=$(ioreg -l 2>/dev/null | grep -m1 '"WEXEDPKeepPassed"' | sed 's/.*= //' | tr -d ' ')
if [ -n "$hold" ]; then
  echo "Doze 保管线: 已跳过 ${hold} 次 disableDisplay（链路全程未被拆除）"
elif strings -a /Volumes/EFI/EFI/OC/Kexts/WhateverXe.kext/Contents/MacOS/WhateverXe 2>/dev/null | grep -q "WEXEDPDozeHoldCount"; then
  echo "Doze 保管线: 已部署，尚未触发（还没熄过屏）"
else
  echo "Doze 保管线: 未安装（旧版 WEX）"
fi
echo "eDP keep 命中: 熄屏后抑制 ${afterdoze:-0} 次 / 放行 donor ${passed:-0} 次（放行=会触发完整 modeset+重训链路）"
dcfb=$(ioreg -l 2>/dev/null | grep -c '"TGLWEXFBStateRouted" = Yes')
dcdc=$(ioreg -l 2>/dev/null | grep -c '"TGLWEXDozeDCGuardReady" = Yes')
if [ "$dcfb" = "1" ] && [ "$dcdc" = "1" ]; then
  dchits=$(ioreg -l 2>/dev/null | grep -m1 '"TGLWEXDozeDCGuardHits"' | sed 's/.*= //' | tr -d ' ')
  echo "DC 守卫: 已就位（FB 状态跟踪 + Doze 期间不武装 DC6/DC9），累计拦截 ${dchits:-0} 次"
else
  echo "DC 守卫: 未就位（FBStateRouted=$dcfb DCGuardReady=$dcdc）——唤醒大概率仍黑屏"
fi
