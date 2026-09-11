# LDM Mac 浏览器扩展 / Browser Extension

把网页里的视频和任意链接一键送到 [LDM Mac](../README.md) 下载。支持 Chrome、Edge 等 Chromium 内核浏览器。

## 安装（Chrome / Edge）

1. 先装好 **LDM Mac.app** 并启动它（扩展需要 App 在运行，本机接口默认在 `127.0.0.1:47823`）
2. 浏览器地址栏打开 `chrome://extensions`（Edge 是 `edge://extensions`）
3. 打开右上角的 **开发者模式 / Developer mode**
4. 点 **加载已解压的扩展程序 / Load unpacked**
5. 选中本文件夹里的 **`chrome`** 子目录（不是外层的 LDM-Mac-Chrome-Extension）
6. 完成后浏览器工具栏出现蓝色下载图标

## 用法

| 场景 | 操作 |
|---|---|
| 下载页面上的视频 | 点右下角浮出的 **⬇** 按钮 → 选一条媒体 → 下载 |
| 整页交给 yt-dlp 解析（B站/YouTube 等） | 浮层里点「整页交给 LDM 解析」 |
| 下载一个普通链接/文件 | 在链接上**右键 → 用 LDM Mac 下载** |
| 下载页面上正在播放的 video/audio | 在播放器上**右键 → 用 LDM Mac 下载这个视频** |
| 下载选中的文本链接 | 选中 URL → 右键 → 用 LDM Mac 下载这段链接 |
| 看进度、暂停、删除 | 点工具栏扩展图标，弹窗里能看到任务进度 |

## 说明

- 扩展会把当前页面的 **Referer** 和站点 **Cookie** 一并带给 App，这样需要登录态的媒体直链（很多站点的 CDN）才能下载成功。所有数据只发往本机 `127.0.0.1`，不上传任何服务器。
- 显示的语言跟随浏览器语言（中文简体 / 中文繁體 / English）。
- 连接不上时，先确认 LDM Mac 正在运行；若改了 App 的本地接口端口，可在 `background.js` 顶部的 `CANDIDATE_PORTS` 里调整。

---

## English

Sends videos and any link from your browser straight into LDM Mac.

1. Install and **launch LDM Mac** first (the extension talks to its local API on `127.0.0.1:47823`).
2. Open `chrome://extensions` → enable **Developer mode**.
3. Click **Load unpacked** and pick the **`chrome`** folder inside this directory.
4. Use the floating **⬇** button on pages with media, or right-click a link/video → **Download with LDM Mac**.

Referer and cookies are forwarded to the local app only (never uploaded anywhere).
