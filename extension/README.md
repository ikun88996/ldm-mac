# LDM Mac 浏览器扩展 / Browser Extensions

把网页里的视频和任意链接一键送到 [LDM Mac](../README.md) 下载。同一套代码，支持 **Chrome / Edge**（Manifest V3 + service worker）和 **Firefox**（Manifest V3 + background scripts）。

## 安装

先装好 **LDM Mac.app** 并启动它（扩展需要 App 在运行，本机接口默认在 `127.0.0.1:47823`）。

### Chrome / Edge

1. 地址栏打开 `chrome://extensions`（Edge 是 `edge://extensions`）
2. 打开右上角的 **开发者模式 / Developer mode**
3. 点 **加载已解压的扩展程序 / Load unpacked**
4. 选中 **`chrome`** 子目录
5. 完成后浏览器工具栏出现蓝色下载图标

### Firefox

1. 地址栏打开 `about:debugging#/runtime/this-firefox`
2. 点 **临时载入附加组件 / Load Temporary Add-on**
3. 选中 **`firefox/manifest.json`**
4. 工具栏出现扩展图标

> Firefox 的「临时载入」在浏览器重启后失效，需要重新载入一次；想让它常驻可以自行打包签名。

## 用法

| 场景 | 操作 |
|---|---|
| 下载页面上的视频 | 点右下角浮出的 **⬇** 按钮 → 选一条媒体 → 下载 |
| 整页交给 yt-dlp 解析（B站/YouTube 等） | 浮层里点「整页交给 LDM 解析」 |
| 下载一个普通链接/文件 | 在链接上**右键 → 用 LDM 下载** |
| 下载页面上正在播放的 video/audio | 在播放器上**右键 → 用 LDM 下载这个视频** |
| 下载选中的文本链接 | 选中 URL → 右键 → 用 LDM 下载这段链接 |
| 看进度、暂停、删除 | 点工具栏扩展图标，弹窗里能看到任务进度 |

## 说明

- 扩展会把当前页面的 **Referer** 和站点 **Cookie** 一并带给 App，这样需要登录态的媒体直链（很多站点的 CDN）才能下载成功。所有数据只发往本机 `127.0.0.1`，不上传任何服务器，扩展也不收集任何数据。
- 显示的语言跟随浏览器语言：简体中文 / 繁體中文 / English / 日本語 / 한국어。
- 连接不上时，先确认 LDM Mac 正在运行；若改了 App 的本地接口端口，可在 `shared/background.js` 顶部的 `CANDIDATE_PORTS` 里调整。

## 开发

```bash
VERSION=1.0.5 ./make_extension.sh        # 组装 chrome/ + firefox/ 两套并打 zip
node scripts/test-extension.js           # 纯函数 + 「扩展 → 本机接口 → aria2」全链路
node scripts/test-content-dom.js         # jsdom 里的 DOM 级测试（嗅探 → 浮层 → 入库）
npx web-ext lint --source-dir build/extensions/firefox   # Mozilla 官方校验
```

目录结构：

```
extension/
├── shared/               两个浏览器共用的代码
│   ├── background.js     右键菜单 / Cookie 收集 / 与 App 通信 / 角标
│   ├── content.js        媒体嗅探 + 页面浮层
│   ├── content.css
│   ├── popup.html/js/css 弹窗：App 状态 + 任务列表 + 本页媒体
│   ├── icons/            构建时生成
│   └── _locales/         en / zh_CN / zh_TW / ja / ko
└── manifests/
    ├── chrome.json       background.service_worker
    └── firefox.json      background.scripts + gecko.id
```

---

## English

Sends videos and any link from your browser straight into LDM Mac.

1. Install and **launch LDM Mac** first (the extension talks to its local API on `127.0.0.1:47823`).
2. Install the extension:
   - **Chrome/Edge**: `chrome://extensions` → enable **Developer mode** → **Load unpacked** → pick the `chrome` folder
   - **Firefox**: `about:debugging#/runtime/this-firefox` → **Load Temporary Add-on** → pick `firefox/manifest.json`
3. Use the floating **⬇** button on pages with media, or right-click a link/video → **Download with LDM Mac**.

Referer and cookies are forwarded to the local app only (never uploaded anywhere), and the extension collects no data.
