# LDM Mac

> **Lightning Download Manager** —— macOS 原生高速多线程下载器，把 aria2、yt-dlp、ffmpeg 这三个命令行神器，装进一个开箱即用的中文图形界面，再配一个能嗅探网页视频的浏览器扩展。

![platform](https://img.shields.io/badge/macOS-14%2B-blue) ![swift](https://img.shields.io/badge/Swift-5.9%2B-orange) ![license](https://img.shields.io/badge/license-MIT-green) ![version](https://img.shields.io/badge/version-1.0.1-lightgrey) ![i18n](https://img.shields.io/badge/i18n-EN%20%7C%20%E7%AE%80%E4%BD%93%20%7C%20%E7%B9%81%E9%AB%94-9cf)

![界面截图](docs/screenshot-main.png)

## 这是什么

**LDM = Lightning Download Manager（闪电下载器）**。

你在 Windows 上用习惯的那类多线程下载器（IDM、TDM Fast 之类），macOS 上一直缺一个好用的原生版本。LDM Mac 就是补这个位置：

- **SwiftUI 原生界面**，不是网页套壳，启动快、占用低
- **多线程分段下载**：单文件最多 64 段并行，断点续传
- **视频一键解析**：基于 yt-dlp，支持 YouTube、B站、X、TikTok、Reddit、Vimeo、Twitch 等 1800+ 站点，自动调用 ffmpeg 合并音视频轨输出 MP4
- **浏览器扩展**：页面视频嗅探（含 HLS/m3u8 分片流）+ 右键「用 LDM 下载」，链接连同 Referer、Cookie 一键送进 App
- **三语言界面**：简体中文 / 繁體中文 / English，跟随系统或手动切换
- **大文件友好**：HuggingFace、镜像站的大文件走分段下载
- **完全免费开源**，无广告、无捆绑、无登录、无遥测

## 安装

### 方式一：下载安装包（推荐）

到 [Releases](https://github.com/xiaodong886/ldm-mac/releases/latest) 下载 `LDM-Mac-1.0.1.dmg`，打开后：

1. 把「LDM Mac」拖进「Applications」
2. 首次打开若被系统拦下（提示“无法验证开发者”或“已损坏”，因为个人开发者没有苹果公证）：
   - 推荐：在「应用程序」里**右键点 LDM Mac → 打开 → 再点「打开」**
   - 或者终端执行一次：
     ```bash
     xattr -dr com.apple.quarantine "/Applications/LDM Mac.app"
     ```
3. 装依赖：`brew install aria2 yt-dlp ffmpeg`（也可以在 App 的「设置 → 引擎依赖」里点一键安装）
4. 想用网页视频嗅探的话，再装浏览器扩展（见下方「浏览器扩展」），扩展 zip 也在 Releases 里

### 方式二：自己编译

```bash
git clone https://github.com/xiaodong886/ldm-mac.git
cd ldm-mac
./make_icon.sh                    # 生成应用图标
VERSION=1.0.1 ./make_app.sh       # 编译并打包 dist/LDM Mac.app
VERSION=1.0.1 ./make_extension.sh # 打包 Chrome 扩展 zip
VERSION=1.0.1 ./make_dmg.sh       # 打成 .dmg 安装包（内含 App + 扩展）
```

只需要 Xcode Command Line Tools（`xcode-select --install`），**不需要**创建 Xcode 工程、不需要签名证书。

## 运行依赖

LDM Mac 自己不带下载内核，它调用系统里现成的三个开源工具（这样你也能随时 `brew upgrade` 升级它们）：

```bash
brew install aria2 yt-dlp ffmpeg
```

| 组件 | 作用 | 许可 |
|---|---|---|
| [aria2](https://github.com/aria2/aria2) | 多线程分段下载、断点续传、队列 | GPL-2.0 |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | 视频站点解析 | Unlicense |
| [ffmpeg](https://ffmpeg.org/) | 音视频轨合并、格式转换 | LGPL/GPL |

## 使用

1. 把链接粘到输入框，回车或点「下载」
2. 模式三选一：
   | 模式 | 行为 |
   |---|---|
   | 自动识别 | 视频站点的链接走 yt-dlp 解析，其他链接走多线程下载 |
   | 多线程下载 | 强制分段下载（适合直链、镜像站、大模型文件） |
   | 视频解析 | 强制走 yt-dlp（适合链接长得不像视频页的站点） |
3. 任务行右侧按钮：暂停 / 继续、打开文件、在访达中显示、复制链接、删除
4. 「设置」里可以改：**界面语言**、下载目录、每任务连接数（1~64）、同时下载任务数、代理、视频画质（最高画质自动合并 MP4 / 1080p 及以下 / 仅音频 mp3）

### 界面语言

简体中文 / 繁體中文 / English 三套完整文案，「设置 → 通用 → 界面语言」里切换（默认跟随系统），切换后立即生效、无需重启。

| English | 繁體中文 |
|---|---|
| ![English](docs/screenshot-en.png) | ![繁體中文](docs/screenshot-zh-hant.png) |

### 关于代理

- **B站、微博、国内镜像站**：直连即可，不用开代理
- **YouTube、X 等**：需要在「设置 → 网络」里打开「使用代理」，填本机代理地址（如 `http://127.0.0.1:7897`），然后点「重启引擎」生效

## 浏览器扩展

支持 Chrome / Edge 等 Chromium 内核浏览器，功能：

- **页面视频嗅探**：右下角浮出按钮显示检测到的媒体数量，点开是候选列表（HLS 分片流优先），逐项下载
- **右键菜单**：链接 / 视频 / 选中文本 / 整页，四种上下文都能「用 LDM Mac 下载」
- **整页交给 yt-dlp**：B站、YouTube 这类页面直接解析，拿到最高画质
- **弹窗面板**：看 App 连接状态、任务进度，能暂停 / 继续 / 删除
- **自动带上 Referer 与 Cookie**：很多站点的媒体直链需要登录态才能下，扩展会自动把当前站点的 Cookie 一起送给 App

### 安装步骤

1. 先启动 **LDM Mac.app**（扩展需要 App 在运行）
2. Chrome 打开 `chrome://extensions`（Edge 是 `edge://extensions`）
3. 打开右上角 **开发者模式**
4. 点 **加载已解压的扩展程序**，选中扩展文件夹里的 **`chrome`** 子目录
   - 从 DMG 安装的：选 `LDM-Mac-Chrome-Extension/chrome`
   - 也可以直接点 App 里「设置 → 浏览器扩展 → 打开扩展文件夹」

详细说明见 [`extension/README.md`](extension/README.md)。

## 本机接口（扩展与 App 怎么通信）

App 启动后会在 `127.0.0.1:47823` 起一个只监听本机的 HTTP 接口（被占用时顺延到 47824/47825），扩展通过它下发任务。接口很简单，你也可以用 curl 或自己的脚本调：

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/ping` | 探活，返回 `{ok, name, version}` |
| POST | `/add` | 添加任务，body：`{url, kind: auto\|file\|video, referer?, cookies?, filename?}` |
| GET | `/tasks` | 当前任务列表（含进度、速度、连接数） |
| POST | `/task` | 任务操作，body：`{id, action: pause\|resume\|remove\|open\|reveal}` |

```bash
# 探活
curl http://127.0.0.1:47823/ping
# 让 App 多线程下载一个文件（16 连接）
curl -X POST http://127.0.0.1:47823/add \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/big.zip","kind":"file"}'
```

> 接口只绑定回环地址、不对外网开放；请求里的 Cookie 只会留在本机，用于你正在下载的那个站点。

## 命令行自检

App 二进制内置了无界面自检入口，方便验证内核与文案：

```bash
# 多线程下载测试（打印实时进度、连接数、速度，并校验落盘大小）
./.build/release/LdmMac --selftest "https://example.com/big-file.zip" --dir /tmp/test --conn 16

# 视频解析测试（可用 LDM_TEST_PROXY 指定代理）
LDM_TEST_PROXY=http://127.0.0.1:7897 ./.build/release/LdmMac --selftest "https://www.youtube.com/watch?v=xxxx" --video --dir /tmp/test

# 三语言文案完整性检查
./.build/release/LdmMac --i18n-check

# 扩展测试：纯函数 + 「扩展 → 本机接口 → aria2/yt-dlp」整条链路（需 App 在运行）
node scripts/test-extension.js

# 扩展的 DOM 级测试（需要 jsdom）：媒体嗅探 → 浮层 → 点击下载真的进 App
npm install --prefix /tmp/ldm-ext-test jsdom && node scripts/test-content-dom.js
```

实测数据（40MB 文件、16 线程、家用宽带）：**1.6 秒完成，峰值 34.9 MB/s**。

## 技术实现

```
SwiftUI 界面（三语言）
   └─ DownloadManager   设置持久化 · 任务列表合并 · 0.9s 轮询刷新 · 链接类型自动识别
        ├─ AriaEngine          aria2c 子进程 + JSON-RPC(127.0.0.1 随机端口 + token 鉴权)
        ├─ VideoEngine         yt-dlp 子进程 + stdout 进度解析 + ffmpeg 合并
        └─ LocalAPIServer      本机 HTTP 接口（浏览器扩展入口，只监听回环）

Chrome 扩展 (MV3)
   ├─ background.js   右键菜单 · Cookie/Referer 收集 · 与 App 通信 · 角标
   ├─ content.js      媒体嗅探（DOM + performance + 页面源码）· 浮层 UI
   └─ popup.html/js   App 状态 · 任务进度 · 当前页媒体列表
```

几个实现上的取舍：

- **内核用 aria2 而不是自己写**：分段、续传、重试、磁盘预分配、并发队列它都做得很成熟，自己写容易在边角情况下出错
- **用子进程 + JSON-RPC 而不是链接 aria2 的库**：进程隔离，aria2 崩了不会带走 App；同时用 `--stop-with-process` 保证 App 退出时内核一起退出，不留孤儿进程
- **不打包内核**：避免 GPL 传染与体积膨胀，用户自己 brew 装、自己升级
- **多语言用内置字典而不是 .lproj**：不需要 Xcode 的本地化工程，`--i18n-check` 还能自动查出漏翻的字段

## 项目结构

```
Sources/LdmMac/
├── LdmMacApp.swift        App 入口、菜单、退出确认
├── Views.swift            界面：任务列表、进度条、设置面板
├── Localization.swift     三语言文案表（81 条 key）
├── DownloadManager.swift  调度中枢：设置、轮询、任务合并、扩展接口处理
├── AriaEngine.swift       aria2c 子进程 + JSON-RPC 客户端
├── VideoEngine.swift      yt-dlp 子进程 + 进度解析
├── LocalAPIServer.swift   本机 HTTP 接口
├── Models.swift           数据模型与格式化
└── SelfTest.swift         --selftest / --i18n-check 入口

extension/chrome/          Chrome MV3 扩展（含 en / zh_CN / zh_TW 三语言）
scripts/test-extension.js  扩展集成测试（Node）
scripts/test-content-dom.js 扩展 DOM 级测试（jsdom）
make_app.sh / make_dmg.sh / make_extension.sh / make_icon.sh
```

## 常见问题

**Q：提示“已损坏，无法打开”？**
不是文件坏了，是系统对未公证应用的拦截。右键 → 打开，或执行 `xattr -dr com.apple.quarantine "/Applications/LDM Mac.app"`。

**Q：扩展里显示「LDM Mac 未运行」？**
先启动 App；扩展只连本机 `127.0.0.1:47823`，如果 App 报「本机接口未启动」，多半是端口被别的程序占了，重启 App 会自动顺延到 47824。

**Q：网页视频点下载后失败？**
很多站点的媒体地址需要登录态或短时效签名。扩展会自动带上当前站点 Cookie；若是签名过期（返回 403），重新在页面上播放一下再点下载。

**Q：引擎未就绪 / 找不到 aria2c？**
`brew install aria2 yt-dlp ffmpeg`，或在设置里点一键安装，装完点「重启引擎」。

**Q：下载速度没有跑满？**
先看任务行显示的连接数。若一直是 1 连接，说明该服务器不支持分段（不少网盘/限速站点如此），这不是线程数能解决的。支持分段的站点把连接数设到 8~16 通常就能跑满带宽，再往上收益很小。

**Q：YouTube 报错？**
YouTube 需要代理，且 yt-dlp 需要保持较新版本（`brew upgrade yt-dlp`）。站点规则变化频繁，遇到解析失败先升级 yt-dlp。

**Q：视频任务为什么不能暂停续传？**
yt-dlp 本身不支持暂停恢复，只能停止后重新添加。多线程文件任务支持完整的暂停/续传。

**Q：关掉窗口下载会中断吗？**
有任务在下载时点关闭或退出，会弹确认框；退出会导致下载中断（重新添加同一链接可断点续传）。

## 更新日志

### v1.0.1
- ✨ 新增 Chrome 浏览器扩展：页面视频嗅探（含 HLS）、右键菜单、任务弹窗，自动携带 Referer/Cookie
- ✨ App 内置本机 HTTP 接口（`127.0.0.1:47823`），扩展与脚本都可通过它下发任务
- ✨ 三语言界面：简体中文 / 繁體中文 / English，可跟随系统或手动切换
- ✨ 设置面板新增「浏览器扩展」区（接口状态、一键打开扩展文件夹）
- ✨ 新增 `--i18n-check` 文案完整性自检、扩展的 Node/jsdom 测试
- 🐛 修复退出后残留孤儿 aria2c 进程的问题（改用 `--stop-with-process`）

### v1.0.0
- 首个公开版本：多线程分段下载、断点续传、YouTube/B站等视频解析合并 MP4、依赖一键安装

## Roadmap

- [ ] Firefox 扩展（MV3）
- [ ] 下载完成系统通知（通知中心）
- [ ] 更多语言（日本語 / 한국어）
- [ ] Homebrew Cask 分发：`brew install --cask ldm-mac`
- [ ] 应用公证（Developer ID）

## English

**LDM Mac — a native macOS download manager** (Lightning Download Manager), built with SwiftUI, powered by aria2 (multi-threaded segmented download), yt-dlp + ffmpeg (video extraction, 1800+ sites) — plus a Chrome extension that sniffs page videos and sends links (with Referer & cookies) straight into the app.

```bash
brew install aria2 yt-dlp ffmpeg   # required runtime dependencies
```

1. Download `LDM-Mac-1.0.1.dmg` from [Releases](https://github.com/xiaodong886/ldm-mac/releases/latest), drag the app into Applications.
2. First launch blocked by Gatekeeper? Right-click → Open, or `xattr -dr com.apple.quarantine "/Applications/LDM Mac.app"`.
3. Optional: install the browser extension (`chrome://extensions` → Developer mode → Load unpacked → pick the `chrome` folder) and keep the app running — it listens on `http://127.0.0.1:47823`.
4. UI available in English, Simplified and Traditional Chinese.

## 致谢

灵感来自 Windows 上那些经典的多线程下载器。本项目为独立实现，基于以下开源项目构建：aria2（GPL-2.0）、yt-dlp（Unlicense）、ffmpeg（LGPL/GPL）。它们以独立进程方式被调用，不随本项目分发。

## License

[MIT](LICENSE) © 2026
