#!/bin/bash
# 打包 .dmg 安装包（App + Chrome/Firefox 扩展 + 拖拽安装）
set -euo pipefail

cd "$(dirname "$0")"
VERSION="${VERSION:-1.0.3}"
APP_NAME="LDM Mac"
DMG="dist/LDM-Mac-${VERSION}.dmg"
STAGE="build/dmg-stage"

./make_extension.sh
./make_app.sh

echo "▸ 准备 DMG 内容"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "dist/${APP_NAME}.app" "$STAGE/"
cp -R build/extensions "$STAGE/LDM-Mac-Browser-Extensions"
find "$STAGE" -name ".DS_Store" -delete
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/安装说明.txt" <<'TXT'
LDM Mac — Lightning Download Manager
macOS 原生高速多线程下载器

【1】安装 App
  把左边的「LDM Mac」拖到右边的「Applications」文件夹里即可。

【2】首次打开被系统拦下（“无法验证开发者” / “已损坏”）时
  方式一（推荐）：在「应用程序」里右键点 LDM Mac → 打开 → 再点「打开」
  方式二（终端执行一次）：
    xattr -dr com.apple.quarantine "/Applications/LDM Mac.app"

【3】运行依赖（首次使用前装一次）
    brew install aria2 yt-dlp ffmpeg
  也可以在 App 的「设置 → 引擎依赖」里点「用 Homebrew 一键安装」。

【4】下载完成通知
  首次启动会申请通知权限，允许后下载完成会在通知中心提醒；
  也可以在「设置 → 通用」里关掉。

【5】安装浏览器扩展（可选，装了才能嗅探网页视频）
  先把 LDM Mac.app 拖进应用程序并启动它（扩展需要 App 在运行）。
  · Chrome / Edge：地址栏输入 chrome://extensions → 打开右上角「开发者模式」
    → 点「加载已解压的扩展程序」→ 选中 LDM-Mac-Browser-Extensions/chrome 文件夹
  · Firefox：地址栏输入 about:debugging#/runtime/this-firefox
    → 点「临时载入附加组件」→ 选中 LDM-Mac-Browser-Extensions/firefox/manifest.json
  · 或者直接在 App 的「设置 → 浏览器扩展」里点「打开扩展文件夹」

【6】下载 YouTube 需要代理
  设置里打开「使用代理」，填本机代理地址（如 http://127.0.0.1:7897）。

界面语言：简体中文 / 繁體中文 / English / 日本語 / 한국어
  默认跟随系统，也可在「设置 → 通用 → 界面语言」里手动切换。

---

LDM Mac — Lightning Download Manager (macOS)
1. Drag "LDM Mac" into Applications.
2. First launch blocked? Right-click the app → Open, or run:
   xattr -dr com.apple.quarantine "/Applications/LDM Mac.app"
3. Dependencies: brew install aria2 yt-dlp ffmpeg
4. Browser extensions (launch the app first):
   Chrome: chrome://extensions → Developer mode → Load unpacked → LDM-Mac-Browser-Extensions/chrome
   Firefox: about:debugging → Load Temporary Add-on → LDM-Mac-Browser-Extensions/firefox/manifest.json
5. UI languages: English / 简体中文 / 繁體中文 / 日本語 / 한국어
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
