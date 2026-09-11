#!/bin/bash
# 构建 Chrome 扩展：生成图标、校验完整性、打 zip
set -euo pipefail

cd "$(dirname "$0")"
VERSION="${VERSION:-1.0.1}"
SRC="extension/chrome"
ZIP="dist/LDM-Mac-Chrome-Extension-${VERSION}.zip"

echo "▸ 生成扩展图标"
mkdir -p "$SRC/icons" build
swift scripts/make_icon.swift build/icon1024.png >/dev/null
for s in 16 32 48 128; do
  sips -z "$s" "$s" build/icon1024.png --out "$SRC/icons/icon${s}.png" >/dev/null
done

echo "▸ 校验 manifest 引用的文件是否齐全"
python3 - "$SRC" "$VERSION" <<'PY'
import json, os, sys
src, version = sys.argv[1], sys.argv[2]
m = json.load(open(os.path.join(src, "manifest.json")))
missing = []
def check(p):
    if not os.path.exists(os.path.join(src, p)):
        missing.append(p)
check(m["background"]["service_worker"])
check(m["action"]["default_popup"])
for p in m["icons"].values():
    check(p)
for c in m["content_scripts"]:
    for p in c.get("js", []) + c.get("css", []):
        check(p)
for loc in {m["default_locale"], "en", "zh_CN", "zh_TW"}:
    check(os.path.join("_locales", loc, "messages.json"))
if missing:
    print("❌ 缺少文件:", missing)
    sys.exit(1)
if m["version"] != version:
    print(f"❌ manifest.json 版本 {m['version']} 与构建版本 {version} 不一致")
    sys.exit(1)
print(f"  manifest 版本 {m['version']}，引用文件全部存在")
PY

echo "▸ JavaScript 语法检查"
for f in "$SRC"/*.js; do
  node --check "$f"
  echo "  ok $(basename "$f")"
done

echo "▸ 打包 zip"
mkdir -p dist
rm -f "$ZIP"
(cd extension && zip -qr "../$ZIP" chrome -x "*.DS_Store")

echo "✅ 扩展打包完成：$ZIP"
ls -lh "$ZIP" | awk '{print "   大小: " $5}'
shasum -a 256 "$ZIP" | awk '{print "   SHA256: " $1}'
