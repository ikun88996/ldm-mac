#!/bin/bash
# 生成 Resources/AppIcon.icns
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p Resources build/icon.iconset
swift scripts/make_icon.swift build/icon1024.png >/dev/null

for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" \
            "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" \
            "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  set -- $spec
  sips -z "$1" "$1" build/icon1024.png --out "build/icon.iconset/$2" >/dev/null
done

iconutil -c icns build/icon.iconset -o Resources/AppIcon.icns
echo "✅ 图标已生成：Resources/AppIcon.icns"
