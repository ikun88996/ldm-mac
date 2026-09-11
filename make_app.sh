#!/bin/bash
# 构建 LDM Mac.app（原生 macOS 应用）
set -euo pipefail

cd "$(dirname "$0")"
VERSION="${VERSION:-1.0.5}"
APP_NAME="LDM Mac"
BUNDLE="dist/${APP_NAME}.app"
EXT_SRC="build/extensions"

echo "▸ 编译 Swift 包（release）"
swift build -c release

echo "▸ 组装 .app 包（版本 ${VERSION}）"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp .build/release/LdmMac "$BUNDLE/Contents/MacOS/LdmMac"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>LDM Mac</string>
    <key>CFBundleDisplayName</key>       <string>LDM Mac</string>
    <key>CFBundleExecutable</key>        <string>LdmMac</string>
    <key>CFBundleIdentifier</key>        <string>com.ldmmac.app</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key>           <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key> <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
        <string>zh-Hant</string>
        <string>ja</string>
        <string>ko</string>
    </array>
    <key>NSHumanReadableCopyright</key>  <string>LDM Mac · 基于 aria2 / yt-dlp / ffmpeg</string>
</dict>
</plist>
PLIST

if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

# 把浏览器扩展（chrome + firefox 两套）放进 App 包，设置里能直接打开这个文件夹
if [ -d "$EXT_SRC" ]; then
  rm -rf "$BUNDLE/Contents/Resources/LDM-Mac-Browser-Extensions"
  cp -R "$EXT_SRC" "$BUNDLE/Contents/Resources/LDM-Mac-Browser-Extensions"
  find "$BUNDLE/Contents/Resources/LDM-Mac-Browser-Extensions" -name ".DS_Store" -delete

  # 兼容旧名字：1.0.1 时叫 LDM-Mac-Chrome-Extension，已有用户的浏览器扩展正是从
  # 这个路径加载的，改名会让扩展失效。保留一份同内容副本，旧路径继续可用。
  rm -rf "$BUNDLE/Contents/Resources/LDM-Mac-Chrome-Extension"
  cp -R "$BUNDLE/Contents/Resources/LDM-Mac-Browser-Extensions" "$BUNDLE/Contents/Resources/LDM-Mac-Chrome-Extension"
else
  echo "⚠️  未找到 $EXT_SRC，先跑 ./make_extension.sh 才能把扩展打进 App 包"
fi

echo "▸ 临时签名（ad-hoc）"
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true

echo "✅ 构建完成：$BUNDLE"
echo "   双击打开，或：open \"$BUNDLE\""
