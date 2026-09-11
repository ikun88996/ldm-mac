import Foundation

// MARK: - 支持的语言

enum AppLang: String, CaseIterable, Identifiable {
    case system = "system"
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en = "en"

    var id: String { rawValue }

    /// 设置里显示的名字（用该语言自己的写法，避免用户看不懂）
    var displayName: String {
        switch self {
        case .system: return "跟随系统 / Follow system"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en:     return "English"
        }
    }
}

// MARK: - 本地化

final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var setting: String {
        didSet { UserDefaults.standard.set(setting, forKey: "language") }
    }

    init() {
        setting = UserDefaults.standard.string(forKey: "language") ?? AppLang.system.rawValue
    }

    /// 当前实际生效的语言（setting 为 system 时跟随系统）
    var current: AppLang {
        if let l = AppLang(rawValue: setting), l != .system { return l }
        return L10n.systemPreferred
    }

    static var systemPreferred: AppLang {
        for code in Locale.preferredLanguages {
            let c = code.lowercased()
            if c.hasPrefix("zh-hant") || c.hasPrefix("zh-tw") || c.hasPrefix("zh-hk") || c.hasPrefix("zh-mo") { return .zhHant }
            if c.hasPrefix("zh") { return .zhHans }
            if c.hasPrefix("en") { return .en }
        }
        return .en
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        let lang = current
        var s = table[key]?[lang.rawValue] ?? table[key]?["en"] ?? key
        if !args.isEmpty { s = String(format: s, arguments: args) }
        return s
    }

    /// 取某个 key 在指定语言下的文案（给扩展导出等场景用）
    func t(_ key: String, lang: AppLang) -> String {
        table[key]?[lang.rawValue] ?? table[key]?["en"] ?? key
    }

    // MARK: - 自检用

    var allKeys: [String] { Array(table.keys).sorted() }

    /// 返回缺失的翻译，形如 "key [zh-Hant]"
    func missingTranslations() -> [String] {
        let required = [AppLang.zhHans.rawValue, AppLang.zhHant.rawValue, AppLang.en.rawValue]
        var missing: [String] = []
        for (key, langs) in table {
            for lang in required where langs[lang] == nil || (langs[lang] ?? "").isEmpty {
                missing.append("\(key) [\(lang)]")
            }
        }
        return missing.sorted()
    }
}

/// 简写：L("key") / L("key", 参数)
func L(_ key: String, _ args: CVarArg...) -> String {
    L10n.shared.t(key, args)
}

// MARK: - 文案表

private let table: [String: [String: String]] = [
    // 状态
    "status.waiting":  ["zh-Hans": "排队中", "zh-Hant": "排隊中", "en": "Queued"],
    "status.active":   ["zh-Hans": "下载中", "zh-Hant": "下載中", "en": "Downloading"],
    "status.paused":   ["zh-Hans": "已暂停", "zh-Hant": "已暫停", "en": "Paused"],
    "status.complete": ["zh-Hans": "已完成", "zh-Hant": "已完成", "en": "Completed"],
    "status.error":    ["zh-Hans": "出错", "zh-Hant": "出錯", "en": "Failed"],

    // 模式
    "mode.auto":  ["zh-Hans": "自动识别", "zh-Hant": "自動識別", "en": "Auto"],
    "mode.file":  ["zh-Hans": "多线程下载", "zh-Hant": "多執行緒下載", "en": "Multi-thread"],
    "mode.video": ["zh-Hans": "视频解析", "zh-Hant": "影片解析", "en": "Video"],

    // 画质
    "quality.best":  ["zh-Hans": "最高画质（自动合并 MP4）", "zh-Hant": "最高畫質（自動合併 MP4）", "en": "Best quality (merge to MP4)"],
    "quality.1080":  ["zh-Hans": "1080p 及以下", "zh-Hant": "1080p 及以下", "en": "Up to 1080p"],
    "quality.audio": ["zh-Hans": "仅音频（mp3）", "zh-Hant": "僅音訊（mp3）", "en": "Audio only (mp3)"],

    // 主界面
    "app.subtitle":     ["zh-Hans": "闪电下载器 · Lightning Download Manager", "zh-Hant": "閃電下載器 · Lightning Download Manager", "en": "Lightning Download Manager"],
    "engine.ready":     ["zh-Hans": "引擎就绪", "zh-Hant": "引擎就緒", "en": "Engine ready"],
    "engine.starting":  ["zh-Hans": "引擎启动中", "zh-Hant": "引擎啟動中", "en": "Starting engine"],
    "btn.pauseAll":     ["zh-Hans": "暂停全部", "zh-Hant": "暫停全部", "en": "Pause all"],
    "btn.resumeAll":    ["zh-Hans": "继续全部", "zh-Hant": "繼續全部", "en": "Resume all"],
    "btn.clearFinished":["zh-Hans": "清除已完成", "zh-Hant": "清除已完成", "en": "Clear finished"],
    "btn.settings":     ["zh-Hans": "设置", "zh-Hant": "設定", "en": "Settings"],
    "placeholder.url":  ["zh-Hans": "粘贴链接：直链文件 / YouTube / B站 / HuggingFace 大模型…",
                         "zh-Hant": "貼上連結：直鏈檔案 / YouTube / B站 / HuggingFace 大模型…",
                         "en": "Paste a link: direct file / YouTube / Bilibili / HuggingFace model…"],
    "btn.download":     ["zh-Hans": "下载", "zh-Hant": "下載", "en": "Download"],
    "empty.title":      ["zh-Hans": "还没有任务", "zh-Hant": "還沒有任務", "en": "No tasks yet"],
    "empty.hint":       ["zh-Hans": "把文件直链或视频页面链接粘到上面的输入框，回车即可",
                         "zh-Hant": "把檔案直鏈或影片頁面連結貼到上面的輸入框，按 Enter 即可",
                         "en": "Paste a direct file link or a video page URL above and press Enter"],
    "btn.openDir":      ["zh-Hans": "打开目录", "zh-Hant": "打開目錄", "en": "Open folder"],
    "tasks.count":      ["zh-Hans": "%d 个任务", "zh-Hant": "%d 個任務", "en": "%d task(s)"],

    // 任务行
    "row.pause":       ["zh-Hans": "暂停", "zh-Hant": "暫停", "en": "Pause"],
    "row.resume":      ["zh-Hans": "继续", "zh-Hant": "繼續", "en": "Resume"],
    "row.openFile":    ["zh-Hans": "打开文件", "zh-Hant": "打開檔案", "en": "Open file"],
    "row.reveal":      ["zh-Hans": "在访达中显示", "zh-Hant": "在 Finder 中顯示", "en": "Show in Finder"],
    "row.copyLink":    ["zh-Hans": "复制链接", "zh-Hant": "複製連結", "en": "Copy link"],
    "row.remove":      ["zh-Hans": "删除任务", "zh-Hant": "刪除任務", "en": "Remove task"],
    "row.connections": ["zh-Hans": "%d 连接", "zh-Hant": "%d 連線", "en": "%d conn"],
    "row.remaining":   ["zh-Hans": "剩余 %@", "zh-Hant": "剩餘 %@", "en": "%@ left"],
    "row.existing":    ["zh-Hans": "文件已存在，已跳过", "zh-Hant": "檔案已存在，已跳過", "en": "File exists, skipped"],

    // 设置
    "settings.title":          ["zh-Hans": "设置", "zh-Hant": "設定", "en": "Settings"],
    "settings.general":        ["zh-Hans": "通用", "zh-Hant": "一般", "en": "General"],
    "settings.language":       ["zh-Hans": "界面语言", "zh-Hant": "介面語言", "en": "Language"],
    "settings.languageHint":   ["zh-Hans": "切换后界面立即生效，不需要重启。", "zh-Hant": "切換後介面立即生效，不需重新啟動。", "en": "Takes effect immediately, no restart needed."],
    "settings.downloads":      ["zh-Hans": "下载", "zh-Hant": "下載", "en": "Downloads"],
    "settings.chooseDir":      ["zh-Hans": "选择目录…", "zh-Hant": "選擇目錄…", "en": "Choose…"],
    "settings.connections":    ["zh-Hans": "每任务连接数：%d", "zh-Hant": "每任務連線數：%d", "en": "Connections per task: %d"],
    "settings.connectionsHint":["zh-Hans": "服务器支持分段时，线程越多通常越快；8~16 线程已能跑满大多数带宽。",
                                "zh-Hant": "伺服器支援分段時，執行緒越多通常越快；8~16 執行緒已能跑滿大多數頻寬。",
                                "en": "More connections help only when the server supports ranges; 8–16 usually saturates home bandwidth."],
    "settings.concurrent":     ["zh-Hans": "同时下载任务数：%d", "zh-Hant": "同時下載任務數：%d", "en": "Concurrent tasks: %d"],
    "settings.video":          ["zh-Hans": "视频", "zh-Hant": "影片", "en": "Video"],
    "settings.quality":        ["zh-Hans": "画质", "zh-Hant": "畫質", "en": "Quality"],
    "settings.network":        ["zh-Hans": "网络", "zh-Hant": "網路", "en": "Network"],
    "settings.proxyToggle":    ["zh-Hans": "使用代理（YouTube 等需要）", "zh-Hant": "使用代理（YouTube 等需要）", "en": "Use proxy (required for YouTube)"],
    "settings.proxyAddr":      ["zh-Hans": "代理地址", "zh-Hant": "代理位址", "en": "Proxy address"],
    "settings.proxyHint":      ["zh-Hans": "修改后点“重启引擎”生效。", "zh-Hant": "修改後點「重新啟動引擎」生效。", "en": "Click “Restart engine” after changing."],
    "settings.deps":           ["zh-Hans": "引擎依赖", "zh-Hant": "引擎相依", "en": "Engine dependencies"],
    "settings.depsOk":         ["zh-Hans": "aria2c / yt-dlp / ffmpeg 已就绪", "zh-Hant": "aria2c / yt-dlp / ffmpeg 已就緒", "en": "aria2c / yt-dlp / ffmpeg ready"],
    "settings.depsMissing":    ["zh-Hans": "缺少：%@", "zh-Hant": "缺少：%@", "en": "Missing: %@"],
    "settings.installDeps":    ["zh-Hans": "用 Homebrew 一键安装", "zh-Hant": "用 Homebrew 一鍵安裝", "en": "Install via Homebrew"],
    "settings.installDepsHint":["zh-Hans": "会打开「终端」执行 brew install %@，装完回来点“重启引擎”。",
                                "zh-Hant": "會打開「終端機」執行 brew install %@，裝完回來點「重新啟動引擎」。",
                                "en": "Opens Terminal and runs: brew install %@. Then click “Restart engine”."],
    "settings.engine":         ["zh-Hans": "引擎", "zh-Hant": "引擎", "en": "Engine"],
    "settings.restart":        ["zh-Hans": "重启引擎（应用线程数 / 代理改动）", "zh-Hant": "重新啟動引擎（套用執行緒數 / 代理變更）", "en": "Restart engine (apply connection/proxy changes)"],
    "settings.extension":      ["zh-Hans": "浏览器扩展", "zh-Hant": "瀏覽器擴充功能", "en": "Browser extension"],
    "settings.extStatus":      ["zh-Hans": "本机接口：localhost:%d（扩展靠它把链接送进来）",
                                "zh-Hant": "本機介面：localhost:%d（擴充功能靠它把連結送進來）",
                                "en": "Local API: localhost:%d (the extension sends links here)"],
    "settings.extNotRunning":  ["zh-Hans": "本机接口未启动，扩展将无法连接", "zh-Hant": "本機介面未啟動，擴充功能將無法連線", "en": "Local API not running — the extension cannot connect"],
    "settings.extOpenFolder":  ["zh-Hans": "打开扩展文件夹", "zh-Hant": "打開擴充功能資料夾", "en": "Open extension folder"],
    "settings.extHint":        ["zh-Hans": "装法：Chrome 打开 chrome://extensions → 打开右上角「开发者模式」→ 点「加载已解压的扩展程序」→ 选中扩展文件夹里的 chrome 子目录。",
                                "zh-Hant": "安裝方式：Chrome 開啟 chrome://extensions → 打開右上角「開發人員模式」→ 點「載入未封裝項目」→ 選取擴充功能資料夾裡的 chrome 子目錄。",
                                "en": "Install: open chrome://extensions → enable “Developer mode” → “Load unpacked” → pick the chrome folder inside."],
    "settings.extMissing":     ["zh-Hans": "未找到扩展文件夹（请从 DMG 的扩展目录里加载）", "zh-Hant": "未找到擴充功能資料夾（請從 DMG 的擴充功能目錄載入）", "en": "Extension folder not found (load it from the DMG folder)"],
    "btn.done":                ["zh-Hans": "完成", "zh-Hant": "完成", "en": "Done"],

    // 提示
    "toast.addedFile":     ["zh-Hans": "已加入多线程下载队列（%d 线程）", "zh-Hant": "已加入多執行緒下載佇列（%d 執行緒）", "en": "Added to queue (%d connections)"],
    "toast.addedVideo":    ["zh-Hans": "已交给 yt-dlp 解析", "zh-Hant": "已交給 yt-dlp 解析", "en": "Handed to yt-dlp"],
    "toast.fromExtension": ["zh-Hans": "来自浏览器扩展", "zh-Hant": "來自瀏覽器擴充功能", "en": "From browser extension"],
    "toast.depMissing":    ["zh-Hans": "未找到 %@，请先安装：brew install %@", "zh-Hant": "未找到 %@，請先安裝：brew install %@", "en": "%@ not found. Install it: brew install %@"],
    "toast.engineBusy":    ["zh-Hans": "下载引擎未就绪", "zh-Hant": "下載引擎未就緒", "en": "Engine not ready"],
    "toast.addFailed":     ["zh-Hans": "添加失败，请检查链接", "zh-Hant": "新增失敗，請檢查連結", "en": "Failed to add — check the link"],
    "toast.copied":        ["zh-Hans": "链接已复制", "zh-Hant": "連結已複製", "en": "Link copied"],
    "toast.completed":     ["zh-Hans": "「%@」已完成", "zh-Hant": "「%@」已完成", "en": "“%@” completed"],
    "toast.completedMany": ["zh-Hans": "等 %d 个任务", "zh-Hant": "等 %d 個任務", "en": "and %d more"],
    "toast.depsInstalling":["zh-Hans": "已在终端开始安装，装完回到这里点“重启引擎”", "zh-Hant": "已在終端機開始安裝，裝完回到這裡點「重新啟動引擎」", "en": "Installing in Terminal — come back and click “Restart engine”"],
    "toast.depsOk":        ["zh-Hans": "依赖已齐全", "zh-Hant": "相依套件已齊全", "en": "Dependencies already installed"],
    "toast.startEngine":   ["zh-Hans": "引擎启动失败：%@", "zh-Hant": "引擎啟動失敗：%@", "en": "Engine failed to start: %@"],
    "toast.videoNoPause":  ["zh-Hans": "视频任务只能停止后重新添加", "zh-Hant": "影片任務只能停止後重新新增", "en": "Video tasks can only be stopped and re-added"],
    "toast.apiFailed":     ["zh-Hans": "本地接口启动失败（浏览器扩展将不可用）", "zh-Hant": "本機介面啟動失敗（瀏覽器擴充功能將無法使用）", "en": "Local API failed to start (extension unavailable)"],
    "quit.title":          ["zh-Hans": "还有 %d 个任务在下载", "zh-Hant": "還有 %d 個任務在下載", "en": "%d task(s) still downloading"],
    "quit.body":           ["zh-Hans": "退出会中断下载，重新添加同一链接可断点续传。", "zh-Hant": "退出會中斷下載，重新新增同一連結可斷點續傳。", "en": "Quitting interrupts downloads; re-adding the same link resumes."],
    "quit.confirm":        ["zh-Hans": "退出并中断", "zh-Hant": "退出並中斷", "en": "Quit anyway"],
    "quit.cancel":         ["zh-Hans": "继续下载", "zh-Hant": "繼續下載", "en": "Keep downloading"],

    // 菜单
    "menu.openDownloadDir": ["zh-Hans": "打开下载目录", "zh-Hant": "打開下載目錄", "en": "Open Downloads Folder"],
]
