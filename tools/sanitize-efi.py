#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
sanitize-efi.py — 生成一份可以公开分享的 OpenCore EFI 副本。

做三件事：
  1. 把 SMBIOS 的四项标识（SystemSerialNumber / MLB / SystemUUID / ROM）
     替换成明显的占位值；
  2. 不复制本地备份、日志、系统垃圾文件；
  3. 全量复扫，确认输出目录里没有任何真实值残留。

源 EFI 只读，绝不修改。真实值不会出现在任何输出、报告或日志里。

用法：
  # 只检查源 EFI 里哪些文件含三码，不写任何文件
  python3 tools/sanitize-efi.py --check-only

  # 生成脱敏副本
  python3 tools/sanitize-efi.py \
      --source /Volumes/EFI/EFI \
      --output ~/Desktop/tianxuan2-EFI

  # 若 EFI 挂载点不同，或用别的 config.plist 取三码
  python3 tools/sanitize-efi.py --source <路径> --config <config.plist 路径> --output <目录>
"""

import argparse
import base64
import fnmatch
import os
import plistlib
import shutil
import sys
from datetime import datetime

# SMBIOS「三码」+ ROM（网卡 MAC）。上传 EFI 时四码都要处理。
SENSITIVE_KEYS = ("SystemSerialNumber", "MLB", "SystemUUID", "ROM")

# 占位值刻意写成一眼能认出来的形式，避免别人直接拿去开机却撞三码。
PLACEHOLDER = {
    "SystemSerialNumber": "REPLACE-WITH-YOUR-SERIAL",
    "MLB": "REPLACE-WITH-YOUR-MLB",
    "SystemUUID": "00000000-0000-0000-0000-000000000000",
    "ROM": b"\x00\x00\x00\x00\x00\x00",
}

# 不该出现在公开仓库里的本地文件。
SKIP_PATTERNS = (
    ".DS_Store", "._*", ".fseventsd", ".Trashes", ".Spotlight-V100",
    "*.txt", "*.log",                      # OpenCore DEBUG 启动日志
    "*.bak", "*.backup", "*backup*", "*.before-*", "config.plist.*",
    "oldConfig.plist", "config-safe-*.plist",
    "*.zip", "*.pkg", "*.dmg", "*.7z",
)


def log(msg):
    print(msg)


def find_config(source, explicit=None):
    """找到用来读取三码的 config.plist。"""
    if explicit:
        if not os.path.isfile(explicit):
            sys.exit("错误：指定的 config.plist 不存在")
        return explicit
    for name in ("config.plist",):
        for dirpath, _dirs, files in os.walk(source):
            for f in files:
                if f.lower() == name and os.path.basename(dirpath).lower() in ("oc", "opencore"):
                    return os.path.join(dirpath, f)
    # 退而求其次：任意 config.plist
    for dirpath, _dirs, files in os.walk(source):
        for f in files:
            if f.lower() == "config.plist":
                return os.path.join(dirpath, f)
    sys.exit("错误：源目录里找不到 config.plist，请用 --config 指定")


def read_sensitive(config_path):
    """从 PlatformInfo/Generic 读四项真实值（仅内存使用，绝不输出）。"""
    with open(config_path, "rb") as f:
        obj = plistlib.load(f)
    g = obj.get("PlatformInfo", {}).get("Generic", {})
    vals = {k: g.get(k) for k in SENSITIVE_KEYS}
    missing = [k for k, v in vals.items() if not v]
    if missing:
        sys.exit("错误：config.plist 里缺少字段：" + ", ".join(missing))
    return vals


def needles_for(key, value):
    """一个真实值在文件里可能的各种写法，用于扫描与字节级兜底替换。"""
    out = set()
    if isinstance(value, bytes):
        # 全零 / 全 FF 的值太常见，不做 needle，避免误伤正常二进制
        if all(b == 0 for b in value) or all(b == 0xFF for b in value):
            return []
        out.add(value)
        out.add(value.hex().encode())
        out.add(value.hex().upper().encode())
        out.add(":".join("%02x" % b for b in value).encode())
        out.add(":".join("%02X" % b for b in value).encode())
        out.add("-".join("%02x" % b for b in value).encode())
        out.add(base64.b64encode(value))          # XML plist 里 <data> 是 base64
    else:
        out.add(value.encode())
        out.add(value.lower().encode())
        out.add(value.upper().encode())
    return [n for n in out if len(n) >= 5]


def build_needle_map(vals):
    """needle bytes -> 占位值 bytes"""
    m = {}
    for k, v in vals.items():
        ph = PLACEHOLDER[k]
        ph_b = ph if isinstance(ph, bytes) else ph.encode()
        for n in needles_for(k, v):
            m[n] = ph_b
    return m


def has_sensitive_value(obj, vals):
    """只在「键名 + 值」都匹配本机真实值时才认定，避免误伤 kext 里同名的 ROM 键。"""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in SENSITIVE_KEYS and v == vals.get(k):
                return True
            if has_sensitive_value(v, vals):
                return True
        return False
    if isinstance(obj, list):
        return any(has_sensitive_value(v, vals) for v in obj)
    return False


def replace_in_obj(obj, vals):
    """递归替换任意 plist 层级（Generic / DataHub / 旧版 SMBIOS 段都覆盖）。"""
    if isinstance(obj, dict):
        return {k: (PLACEHOLDER[k] if k in SENSITIVE_KEYS and v == vals.get(k)
                    else replace_in_obj(v, vals))
                for k, v in obj.items()}
    if isinstance(obj, list):
        return [replace_in_obj(v, vals) for v in obj]
    return obj


def should_skip(relpath):
    name = os.path.basename(relpath)
    for part in relpath.split(os.sep):
        if any(fnmatch.fnmatch(part.lower(), pat.lower()) for pat in SKIP_PATTERNS):
            return True
    return False


def iter_files(root):
    for dirpath, _dirs, files in os.walk(root):
        for f in sorted(files):
            yield os.path.join(dirpath, f)


def scan(root, needles_by_key, label):
    """返回 [(相对路径, 字段名)]，不返回也不打印真实值。"""
    hits = []
    for p in iter_files(root):
        try:
            raw = open(p, "rb").read()
        except OSError:
            continue
        for k, ns in needles_by_key.items():
            if any(n in raw for n in ns):
                hits.append((os.path.relpath(p, root), k))
    return hits


def sanitize_file(path, needle_map, vals):
    """结构化替换 plist + 字节级兜底。返回是否改动。"""
    try:
        raw = open(path, "rb").read()
    except OSError:
        return False
    changed = False

    # 1) plist：用 plistlib 重写，保持 XML / binary 原格式和键顺序
    try:
        obj = plistlib.loads(raw)
    except Exception:
        obj = None
    if isinstance(obj, (dict, list)) and has_sensitive_value(obj, vals):
        obj = replace_in_obj(obj, vals)
        fmt = plistlib.FMT_BINARY if raw.startswith(b"bplist00") else plistlib.FMT_XML
        with open(path, "wb") as f:
            plistlib.dump(obj, f, fmt=fmt, sort_keys=False)
        changed = True

    # 2) 非 plist 文件 / plist 里的字面量残留，做字节兜底
    cur = open(path, "rb").read()
    for n, ph in needle_map.items():
        if n in cur:
            cur = cur.replace(n, ph)
            changed = True
    if changed:
        with open(path, "wb") as f:
            f.write(cur)
    return changed


def main():
    ap = argparse.ArgumentParser(description="生成脱敏后的可公开 EFI 副本")
    ap.add_argument("--source", default="/Volumes/EFI/EFI", help="源 EFI 目录（只读）")
    ap.add_argument("--config", help="用来读三码的 config.plist，默认自动查找")
    ap.add_argument("--output", default=os.path.expanduser("~/Desktop/tianxuan2-EFI"),
                    help="脱敏副本输出目录")
    ap.add_argument("--check-only", action="store_true", help="只扫描源 EFI，不写任何文件")
    ap.add_argument("--force", action="store_true", help="输出目录已存在时清空重建")
    args = ap.parse_args()

    source = os.path.abspath(os.path.expanduser(args.source))
    if not os.path.isdir(source):
        sys.exit("错误：源目录不存在（EFI 分区挂载了吗？）：" + source)

    cfg = find_config(source, args.config)
    vals = read_sensitive(cfg)
    needles_by_key = {k: needles_for(k, v) for k, v in vals.items()}
    needle_map = build_needle_map(vals)

    log("源目录: " + source)
    log("三码来源: " + os.path.relpath(cfg, source))
    log("已读取 4 项标识（真实值不会输出）: " + ", ".join(SENSITIVE_KEYS))

    if args.check_only:
        log("\n=== 源 EFI 中含真实标识的文件 ===")
        hits = scan(source, needles_by_key, "source")
        for path, k in hits:
            log("  %-58s %s" % (path, k))
        log("\n命中文件数: %d" % len(set(p for p, _ in hits)))
        log("提示：上传前请运行不带 --check-only 的命令生成脱敏副本。")
        return 0

    out = os.path.abspath(os.path.expanduser(args.output))
    if os.path.exists(out):
        if not args.force:
            sys.exit("错误：输出目录已存在，请换路径或加 --force：" + out)
        if os.path.abspath(out) == os.path.abspath(source):
            sys.exit("错误：输出目录不能等于源目录")
        shutil.rmtree(out)
    os.makedirs(out)

    # 复制目录树，跳过本地垃圾/备份
    copied, skipped = [], []
    for dirpath, dirs, files in os.walk(source):
        rel_dir = os.path.relpath(dirpath, source)
        dirs[:] = [d for d in dirs if not should_skip(os.path.join(rel_dir, d))]
        for f in files:
            rel = os.path.normpath(os.path.join(rel_dir, f))
            if should_skip(rel):
                skipped.append(rel)
                continue
            src_p = os.path.join(dirpath, f)
            dst_p = os.path.join(out, rel)
            os.makedirs(os.path.dirname(dst_p), exist_ok=True)
            shutil.copy2(src_p, dst_p)
            copied.append(rel)

    log("\n复制 %d 个文件，跳过 %d 个本地备份/垃圾文件" % (len(copied), len(skipped)))

    changed_files = []
    for rel in copied:
        if sanitize_file(os.path.join(out, rel), needle_map, vals):
            changed_files.append(rel)
    log("脱敏改写 %d 个文件:" % len(changed_files))
    for rel in changed_files:
        log("  " + rel)

    # 全量复扫：任何真实值残留都算失败
    leftovers = scan(out, needles_by_key, "output")
    if leftovers:
        log("\n❌ 输出目录里仍有真实标识残留（请勿上传）:")
        for path, k in leftovers:
            log("  %-58s %s" % (path, k))
        log("\n请删除该目录后排查，或补进 SKIP_PATTERNS。")
        return 1
    log("\n✅ 复扫通过：输出目录无真实标识残留")

    # 报告
    report = [
        "# EFI 脱敏报告",
        "",
        "生成时间：" + datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "",
        "本目录由 `tools/sanitize-efi.py` 从本机 EFI 只读复制生成，",
        "已替换 **SystemSerialNumber / MLB / SystemUUID / ROM** 四项，",
        "并全量复扫确认无真实值残留。真实值不在任何文件中。",
        "",
        "## 使用前必须做",
        "",
        "把 `OC/config.plist`（或 `oc/config.plist`）里 `PlatformInfo/Generic` 下的",
        "四个占位值换成**你自己生成的**三码和 ROM，否则不要用于引导：",
        "",
        "| 字段 | 当前占位值 |",
        "| --- | --- |",
        "| `SystemSerialNumber` | `REPLACE-WITH-YOUR-SERIAL` |",
        "| `MLB` | `REPLACE-WITH-YOUR-MLB` |",
        "| `SystemUUID` | `00000000-0000-0000-0000-000000000000` |",
        "| `ROM` | `00 00 00 00 00 00` |",
        "",
        "## 处理明细",
        "",
        "- 复制文件：%d 个" % len(copied),
        "- 跳过本地备份 / 日志 / 系统垃圾：%d 个" % len(skipped),
        "- 脱敏改写：%d 个" % len(changed_files),
        "",
        "改写的文件：",
        "",
    ] + ["- `" + r + "`" for r in changed_files] + [
        "",
        "跳过示例：" + ", ".join("`" + s + "`" for s in skipped[:12]),
        "",
        "## 注意",
        "",
        "- 本仓库只含开源 kext 与引导器，第三方固件 / 驱动的著作权归各自项目所有。",
        "- 换回自己的三码后，请自行核对 config.plist 能否正常引导。",
        "- 不要把未脱敏的原始 config.plist 覆盖进本目录。",
        "",
    ]
    with open(os.path.join(out, "SANITIZE-REPORT.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(report))

    gitignore = """# 本地垃圾与日志
.DS_Store
._*
.fseventsd/
.Trashes/
*.txt
*.log

# 本地备份配置（常含未脱敏三码，绝不要覆盖进来）
*.bak
*.backup
*backup*
*.before-*
config.plist.*
oldConfig.plist
config-safe-*.plist
*.zip
*.pkg
*.dmg
"""
    with open(os.path.join(out, ".gitignore"), "w", encoding="utf-8") as f:
        f.write(gitignore)

    log("已生成 SANITIZE-REPORT.md 与 .gitignore")
    log("\n输出目录: " + out)
    log("下一步: cd %s && git init && git add . && git commit -m 'Initial EFI commit'" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
