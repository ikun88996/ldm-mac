#!/bin/bash
# 打包 .dmg 安装包（拖拽到 Applications 安装）
set -euo pipefail

cd "$(dirname "$0")"
VERSION="${VERSION:-1.0.0}"
APP_NAME="LDM Mac"
DMG="dist/LDM-Mac-${VERSION}.dmg"
STAGE="build/dmg-stage"

./make_app.sh

echo "▸ 准备 DMG 内容"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "dist/${APP_NAME}.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/安装说明.txt" <<'TXT'
LDM Mac — Lightning Download Manager
macOS 原生高速多线程下载器

安装：
  把左边的「LDM Mac」拖到右边的「Applications」文件夹里即可。

首次打开被系统拦下（“无法验证开发者” / “已损坏”）时：
  方式一（推荐）：在「应用程序」里右键点 LDM Mac → 打开 → 再点「打开」
  方式二（终端执行一次）：
    xattr -dr com.apple.quarantine "/Applications/LDM Mac.app"

运行依赖（首次使用前装一次）：
    brew install aria2 yt-dlp ffmpeg
  也可以在 App 的「设置 → 引擎依赖」里点「用 Homebrew 一键安装」。

下载 YouTube 需要代理：设置里打开「使用代理」，填本机代理地址（如 http://127.0.0.1:7897）。
TXT

echo "▸ 生成 DMG"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"

echo "▸ 计算校验和"
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "$SHA  LDM-Mac-${VERSION}.dmg" > "dist/LDM-Mac-${VERSION}.dmg.sha256"

echo "✅ 安装包完成：$DMG"
echo "   SHA256: $SHA"
echo "   大小：$(du -h "$DMG" | awk '{print $1}')"
