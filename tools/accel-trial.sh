#!/bin/bash
# 核显 Metal 加速开关（GT1 9A68，WhateverXe 0.8.0 补丁版）
# 用法: sudo bash accel-trial.sh on|off|status
#   on     = 关掉 Intel VDA 解码（改名 bundle）+ EFI 切到 -wex-gt1-accel
#   off    = 恢复 Intel VDA bundle + EFI 切回 -wex-noaccel（亮屏保底版）
#   status = 只读检查，不改任何东西
#
# 背景：Intel GT1 fuse video=4 没有 VCS0，媒体命令流永远是 NULL；
# 只要 VideoToolbox 走 Intel 硬解就会 CR2=0x284 空指针 panic。
# 所以开加速必须同时把 AppleIntelTGLGraphicsVADriver.bundle 下线。
#
# 脚本不依赖本机专用模板文件，只以当前 config.plist 文本为基准做替换。
set -uo pipefail

EFI_OC="/Volumes/EFI/EFI/OC"
CFG="$EFI_OC/config.plist"
CFG_GOOD="$EFI_OC/config.plist.good"
VA="/Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle"
VA_OFF="$VA.disabled"
MODE="${1:-status}"

say() { printf '%s\n' "$*"; }
die() { printf '出错: %s\n' "$*" >&2; exit 1; }

# 切换 boot-args，并同步生成 config.plist.good（永远是 -wex-noaccel 救援版）。
set_args() {
  /usr/bin/python3 - "$CFG" "$CFG_GOOD" "$1" <<'PY'
import os, sys
cfg, good, want = sys.argv[1], sys.argv[2], sys.argv[3].encode()
ACC, NOA = b"-wex-gt1-accel", b"-wex-noaccel"
raw = open(cfg, "rb").read()
out = raw.replace(NOA, ACC) if want == ACC else raw.replace(ACC, NOA)
assert out.count(want) == 1, "目标参数命中次数异常（config 被人改过？）"
assert (ACC if want == NOA else NOA) not in out, "另一个开关还残留"
keep = out.replace(ACC, NOA)
assert keep.count(NOA) == 1
for dst, data in ((cfg, out), (good, keep)):
    with open(dst, "wb") as f:
        f.write(data); f.flush(); os.fsync(f.fileno())
    back = open(dst, "rb").read()
    print(f"{os.path.basename(dst)}: 回读一致={back == data} 大小={len(back)}")
    if back != data:
        sys.exit(1)
PY
}

check_cfg() {
  /usr/bin/plutil -lint "$CFG" >/dev/null || die "config.plist 校验失败"
  local args tools
  args=$(/usr/bin/plutil -p "$CFG" | /usr/bin/grep '"boot-args"' | head -1)
  tools=$(/usr/bin/plutil -extract Misc.Tools raw -o - "$CFG" 2>/dev/null)
  say "boot-args: $args"
  say "Misc/Tools 条目数: ${tools:-?}  (含 Rescue: UEFI Shell 才能自救)"
}

status() {
  say "== /Library =="
  if [ -d "$VA" ]; then say "Intel VDA bundle: 在位（会被 VT 使用 → accel 下必崩）"
  elif [ -d "$VA_OFF" ]; then say "Intel VDA bundle: 已禁用 (.disabled)"
  else say "Intel VDA bundle: 未找到"; fi
  say "== EFI =="
  [ -f "$CFG" ] && check_cfg || say "找不到 $CFG（EFI 没挂载？）"
  [ -f "$CFG_GOOD" ] && say "config.plist.good: 存在（救援版）" || say "config.plist.good: 缺失"
  say "== 本次启动参数 =="
  /usr/sbin/sysctl -n kern.bootargs 2>/dev/null
}

case "$MODE" in
status)
  status ;;

on)
  [ "$(id -u)" = "0" ] || die "on 要写 /Library，请用 sudo 运行"
  [ -f "$CFG" ] || die "EFI 未挂载"
  if [ -d "$VA" ]; then
    mv "$VA" "$VA_OFF" || die "改名失败"
    say "[1/2] 已禁用 Intel VDA: $(basename "$VA_OFF")"
  elif [ -d "$VA_OFF" ]; then
    say "[1/2] Intel VDA 已是禁用状态，跳过"
  else
    die "Intel VDA bundle 既不在原位也不在 .disabled"
  fi
  set_args "-wex-gt1-accel" || die "写 config 失败"
  say "[2/2] config.plist → 加速版；config.plist.good → 救援版"
  /usr/bin/plutil -lint "$CFG" "$CFG_GOOD"
  status
  say ""
  say "完成，可以重启。" ;;

off)
  [ "$(id -u)" = "0" ] || die "off 要写 /Library，请用 sudo 运行"
  [ -f "$CFG" ] || die "EFI 未挂载"
  if [ -d "$VA_OFF" ]; then
    mv "$VA_OFF" "$VA" || die "恢复失败"
    say "[1/2] Intel VDA bundle 已恢复"
  else
    say "[1/2] Intel VDA bundle 本来就是开启状态，跳过"
  fi
  set_args "-wex-noaccel" || die "写 config 失败"
  say "[2/2] config.plist → 救援版（无加速）"
  /usr/bin/plutil -lint "$CFG" "$CFG_GOOD"
  status
  say ""
  say "完成，可以重启。" ;;

*)
  die "用法: accel-trial.sh on|off|status" ;;
esac
