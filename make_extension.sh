#!/bin/bash
# 构建浏览器扩展：生成图标 → 组装 chrome / firefox 两套 → 校验 → 打 zip
set -euo pipefail

cd "$(dirname "$0")"
VERSION="${VERSION:-1.0.3}"
SRC="extension"
OUT="build/extensions"

echo "▸ 生成扩展图标"
mkdir -p "$SRC/shared/icons" build
swift scripts/make_icon.swift build/icon1024.png >/dev/null
for s in 16 32 48 128; do
  sips -z "$s" "$s" build/icon1024.png --out "$SRC/shared/icons/icon${s}.png" >/dev/null
done

echo "▸ 组装 chrome / firefox 两套扩展（同一套代码 + 各自 manifest）"
rm -rf "$OUT"
for browser in chrome firefox; do
  mkdir -p "$OUT/$browser"
  cp -R "$SRC/shared/." "$OUT/$browser/"
  cp "$SRC/manifests/$browser.json" "$OUT/$browser/manifest.json"
  find "$OUT/$browser" -name ".DS_Store" -delete
done

echo "▸ 校验 manifest 与文件完整性"
python3 - "$OUT" "$VERSION" <<'PY'
import json, os, sys
out, version = sys.argv[1], sys.argv[2]
locales = ["en", "zh_CN", "zh_TW", "ja", "ko"]
failed = False

for browser in ("chrome", "firefox"):
    root = os.path.join(out, browser)
    m = json.load(open(os.path.join(root, "manifest.json")))
    missing = []
    def check(p):
        if not os.path.exists(os.path.join(root, p)):
            missing.append(p)
    bg = m["background"]
    check(bg.get("service_worker") or bg.get("scripts", ["?"])[0])
    check(m["action"]["default_popup"])
    for p in m["icons"].values():
        check(p)
    for c in m["content_scripts"]:
        for p in c.get("js", []) + c.get("css", []):
            check(p)
    for loc in {m["default_locale"], *locales}:
        check(os.path.join("_locales", loc, "messages.json"))

    if missing:
        print(f"  ❌ {browser}: 缺少文件 {missing}")
        failed = True
    if m["version"] != version:
        print(f"  ❌ {browser}: manifest 版本 {m['version']} ≠ {version}")
        failed = True
    if browser == "firefox" and "service_worker" in bg:
        print("  ❌ firefox: MV3 后台必须用 background.scripts（Firefox 不支持 service_worker）")
        failed = True
    if browser == "chrome" and "scripts" in bg:
        print("  ❌ chrome: 应使用 background.service_worker")
        failed = True
    if browser == "firefox" and "gecko" not in m.get("browser_specific_settings", {}):
        print("  ❌ firefox: 缺少 browser_specific_settings.gecko.id")
        failed = True

    if not missing and m["version"] == version:
        print(f"  ✓ {browser}: v{m['version']}，后台={list(bg.keys())}，权限 {len(m['permissions'])} 项，语言 {len(locales)} 种")

sys.exit(1 if failed else 0)
PY

echo "▸ JavaScript 语法检查"
for f in "$SRC"/shared/*.js; do
  node --check "$f"
  echo "  ok $(basename "$f")"
done

echo "▸ 打包 zip"
DIST="$(pwd)/dist"
mkdir -p "$DIST"
rm -f "$DIST/LDM-Mac-Chrome-Extension-${VERSION}.zip" "$DIST/LDM-Mac-Firefox-Extension-${VERSION}.zip"
(cd "$OUT" && zip -qr "$DIST/LDM-Mac-Chrome-Extension-${VERSION}.zip" chrome -x "*.DS_Store")
(cd "$OUT" && zip -qr "$DIST/LDM-Mac-Firefox-Extension-${VERSION}.zip" firefox -x "*.DS_Store")

echo "✅ 扩展打包完成"
for f in "dist/LDM-Mac-Chrome-Extension-${VERSION}.zip" "dist/LDM-Mac-Firefox-Extension-${VERSION}.zip"; do
  printf "   %s  %s  sha256=%s\n" "$f" "$(du -h "$f" | awk '{print $1}')" "$(shasum -a 256 "$f" | awk '{print $1}')"
done
