import Foundation

// MARK: - 支持的语言

enum AppLang: String, CaseIterable, Identifiable {
    case system = "system"
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en = "en"
    case ja = "ja"
    case ko = "ko"

    var id: String { rawValue }

    /// 设置里显示的名字（用该语言自己的写法，避免用户看不懂）
    var displayName: String {
        switch self {
        case .system: return "跟随系统 / Follow system"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en:     return "English"
        case .ja:     return "日本語"
        case .ko:     return "한국어"
        }
    }
}

// MARK: - 本地化

final class L10n: ObservableObject {
    static let shared = L10n()

    /// 所有支持的语言（不含 system）
    static let allLangs: [AppLang] = [.zhHans, .zhHant, .en, .ja, .ko]

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
            if c.hasPrefix("ja") { return .ja }
            if c.hasPrefix("ko") { return .ko }
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

    /// 取某个 key 在指定语言下的文案
    func t(_ key: String, lang: AppLang) -> String {
        table[key]?[lang.rawValue] ?? table[key]?["en"] ?? key
    }

    // MARK: - 自检用

    var allKeys: [String] { Array(table.keys).sorted() }

    /// 返回缺失的翻译，形如 "key [ja]"
    func missingTranslations() -> [String] {
        var missing: [String] = []
        for (key, langs) in table {
            for lang in L10n.allLangs where (langs[lang.rawValue] ?? "").isEmpty {
                missing.append("\(key) [\(lang.rawValue)]")
            }
        }
        return missing.sorted()
    }
}

/// 简写：L("key") / L("key", 参数)
func L(_ key: String, _ args: CVarArg...) -> String {
    L10n.shared.t(key, args)
}

// MARK: - 文案表（5 种语言）

private let table: [String: [String: String]] = [
    // 状态
    "status.waiting":  ["zh-Hans": "排队中", "zh-Hant": "排隊中", "en": "Queued", "ja": "待機中", "ko": "대기 중"],
    "status.active":   ["zh-Hans": "下载中", "zh-Hant": "下載中", "en": "Downloading", "ja": "ダウンロード中", "ko": "다운로드 중"],
    "status.paused":   ["zh-Hans": "已暂停", "zh-Hant": "已暫停", "en": "Paused", "ja": "一時停止", "ko": "일시정지됨"],
    "status.complete": ["zh-Hans": "已完成", "zh-Hant": "已完成", "en": "Completed", "ja": "完了", "ko": "완료"],
    "status.error":    ["zh-Hans": "出错", "zh-Hant": "出錯", "en": "Failed", "ja": "エラー", "ko": "오류"],

    // 模式
    "mode.auto":  ["zh-Hans": "自动识别", "zh-Hant": "自動識別", "en": "Auto", "ja": "自動判定", "ko": "자동 감지"],
    "mode.file":  ["zh-Hans": "多线程下载", "zh-Hant": "多執行緒下載", "en": "Multi-thread", "ja": "マルチスレッド", "ko": "멀티스레드"],
    "mode.video": ["zh-Hans": "视频解析", "zh-Hant": "影片解析", "en": "Video", "ja": "動画解析", "ko": "동영상 분석"],

    // 画质
    "quality.best":  ["zh-Hans": "最高画质（自动合并 MP4）", "zh-Hant": "最高畫質（自動合併 MP4）", "en": "Best quality (merge to MP4)", "ja": "最高画質（MP4 に結合）", "ko": "최고 화질(MP4 병합)"],
    "quality.1080":  ["zh-Hans": "1080p 及以下", "zh-Hant": "1080p 及以下", "en": "Up to 1080p", "ja": "1080p 以下", "ko": "1080p 이하"],
    "quality.audio": ["zh-Hans": "仅音频（mp3）", "zh-Hant": "僅音訊（mp3）", "en": "Audio only (mp3)", "ja": "音声のみ（mp3）", "ko": "오디오만(mp3)"],

    // 主界面
    "app.subtitle": ["zh-Hans": "闪电下载器 · Lightning Download Manager",
                     "zh-Hant": "閃電下載器 · Lightning Download Manager",
                     "en": "Lightning Download Manager",
                     "ja": "Lightning Download Manager",
                     "ko": "Lightning Download Manager"],
    "engine.ready":     ["zh-Hans": "引擎就绪", "zh-Hant": "引擎就緒", "en": "Engine ready", "ja": "エンジン準備完了", "ko": "엔진 준비됨"],
    "engine.starting":  ["zh-Hans": "引擎启动中", "zh-Hant": "引擎啟動中", "en": "Starting engine", "ja": "エンジン起動中", "ko": "엔진 시작 중"],
    "btn.pauseAll":     ["zh-Hans": "暂停全部", "zh-Hant": "暫停全部", "en": "Pause all", "ja": "すべて一時停止", "ko": "모두 일시정지"],
    "btn.resumeAll":    ["zh-Hans": "继续全部", "zh-Hant": "繼續全部", "en": "Resume all", "ja": "すべて再開", "ko": "모두 재개"],
    "btn.clearFinished":["zh-Hans": "清除已完成", "zh-Hant": "清除已完成", "en": "Clear finished", "ja": "完了を消去", "ko": "완료 항목 지우기"],
    "btn.settings":     ["zh-Hans": "设置", "zh-Hant": "設定", "en": "Settings", "ja": "設定", "ko": "설정"],
    "placeholder.url":  ["zh-Hans": "粘贴链接：直链文件 / YouTube / B站 / HuggingFace 大模型…",
                         "zh-Hant": "貼上連結：直鏈檔案 / YouTube / B站 / HuggingFace 大模型…",
                         "en": "Paste a link: direct file / YouTube / Bilibili / HuggingFace model…",
                         "ja": "リンクを貼り付け：直接リンク / YouTube / Bilibili / HuggingFace…",
                         "ko": "링크 붙여넣기: 직접 링크 / YouTube / Bilibili / HuggingFace…"],
    "btn.download":     ["zh-Hans": "下载", "zh-Hant": "下載", "en": "Download", "ja": "ダウンロード", "ko": "다운로드"],
    "empty.title":      ["zh-Hans": "还没有任务", "zh-Hant": "還沒有任務", "en": "No tasks yet", "ja": "タスクはまだありません", "ko": "아직 작업이 없습니다"],
    "empty.hint":       ["zh-Hans": "把文件直链或视频页面链接粘到上面的输入框，回车即可",
                         "zh-Hant": "把檔案直鏈或影片頁面連結貼到上面的輸入框，按 Enter 即可",
                         "en": "Paste a direct file link or a video page URL above and press Enter",
                         "ja": "上の入力欄にファイルの直リンクか動画ページの URL を貼り、Enter を押してください",
                         "ko": "위 입력란에 파일 직접 링크나 동영상 페이지 URL을 붙여넣고 Enter를 누르세요"],
    "btn.openDir":      ["zh-Hans": "打开目录", "zh-Hant": "打開目錄", "en": "Open folder", "ja": "フォルダを開く", "ko": "폴더 열기"],
    "tasks.count":      ["zh-Hans": "%d 个任务", "zh-Hant": "%d 個任務", "en": "%d task(s)", "ja": "%d 件のタスク", "ko": "작업 %d개"],

    // 任务行
    "row.pause":       ["zh-Hans": "暂停", "zh-Hant": "暫停", "en": "Pause", "ja": "一時停止", "ko": "일시정지"],
    "row.resume":      ["zh-Hans": "继续", "zh-Hant": "繼續", "en": "Resume", "ja": "再開", "ko": "재개"],
    "row.openFile":    ["zh-Hans": "打开文件", "zh-Hant": "打開檔案", "en": "Open file", "ja": "ファイルを開く", "ko": "파일 열기"],
    "row.reveal":      ["zh-Hans": "在访达中显示", "zh-Hant": "在 Finder 中顯示", "en": "Show in Finder", "ja": "Finder で表示", "ko": "Finder에서 보기"],
    "row.copyLink":    ["zh-Hans": "复制链接", "zh-Hant": "複製連結", "en": "Copy link", "ja": "リンクをコピー", "ko": "링크 복사"],
    "row.remove":      ["zh-Hans": "删除任务", "zh-Hant": "刪除任務", "en": "Remove task", "ja": "タスクを削除", "ko": "작업 삭제"],
    "row.connections": ["zh-Hans": "%d 连接", "zh-Hant": "%d 連線", "en": "%d conn", "ja": "%d 接続", "ko": "연결 %d개"],
    "row.remaining":   ["zh-Hans": "剩余 %@", "zh-Hant": "剩餘 %@", "en": "%@ left", "ja": "残り %@", "ko": "남음 %@"],
    "row.existing":    ["zh-Hans": "文件已存在，已跳过", "zh-Hant": "檔案已存在，已跳過", "en": "File exists, skipped", "ja": "ファイルが存在するためスキップ", "ko": "파일이 이미 있어 건너뜀"],

    // 设置
    "settings.title":          ["zh-Hans": "设置", "zh-Hant": "設定", "en": "Settings", "ja": "設定", "ko": "설정"],
    "settings.general":        ["zh-Hans": "通用", "zh-Hant": "一般", "en": "General", "ja": "一般", "ko": "일반"],
    "settings.language":       ["zh-Hans": "界面语言", "zh-Hant": "介面語言", "en": "Language", "ja": "表示言語", "ko": "언어"],
    "settings.languageHint":   ["zh-Hans": "切换后界面立即生效，不需要重启。",
                                "zh-Hant": "切換後介面立即生效，不需重新啟動。",
                                "en": "Takes effect immediately, no restart needed.",
                                "ja": "切り替えるとすぐ反映されます（再起動は不要）。",
                                "ko": "변경하면 즉시 적용됩니다(재시작 불필요)."],
    "settings.notify":         ["zh-Hans": "下载完成后发送系统通知", "zh-Hant": "下載完成後傳送系統通知", "en": "Notify me when a download finishes",
                                "ja": "ダウンロード完了時に通知する", "ko": "다운로드 완료 시 알림 받기"],
    "notify.title":            ["zh-Hans": "下载完成", "zh-Hant": "下載完成", "en": "Download finished", "ja": "ダウンロード完了", "ko": "다운로드 완료"],
    "notify.body":             ["zh-Hans": "%@ · %@", "zh-Hant": "%@ · %@", "en": "%@ · %@", "ja": "%@ · %@", "ko": "%@ · %@"],
    "settings.downloads":      ["zh-Hans": "下载", "zh-Hant": "下載", "en": "Downloads", "ja": "ダウンロード", "ko": "다운로드"],
    "settings.chooseDir":      ["zh-Hans": "选择目录…", "zh-Hant": "選擇目錄…", "en": "Choose…", "ja": "フォルダを選択…", "ko": "폴더 선택…"],
    "settings.connections":    ["zh-Hans": "每任务连接数：%d", "zh-Hant": "每任務連線數：%d", "en": "Connections per task: %d",
                                "ja": "タスクごとの接続数：%d", "ko": "작업당 연결 수: %d"],
    "settings.connectionsHint":["zh-Hans": "服务器支持分段时，线程越多通常越快；8~16 线程已能跑满大多数带宽。",
                                "zh-Hant": "伺服器支援分段時，執行緒越多通常越快；8~16 執行緒已能跑滿大多數頻寬。",
                                "en": "More connections help only when the server supports ranges; 8–16 usually saturates home bandwidth.",
                                "ja": "サーバーが分割ダウンロードに対応しているほど効果的です。8〜16 接続で大半の回線を使い切れます。",
                                "ko": "서버가 분할 다운로드를 지원할 때 효과적이며, 8~16개 연결이면 대부분의 회선을 채웁니다."],
    "settings.concurrent":     ["zh-Hans": "同时下载任务数：%d", "zh-Hant": "同時下載任務數：%d", "en": "Concurrent tasks: %d",
                                "ja": "同時ダウンロード数：%d", "ko": "동시 다운로드 수: %d"],
    "settings.video":          ["zh-Hans": "视频", "zh-Hant": "影片", "en": "Video", "ja": "動画", "ko": "동영상"],
    "settings.quality":        ["zh-Hans": "画质", "zh-Hant": "畫質", "en": "Quality", "ja": "画質", "ko": "화질"],
    "settings.network":        ["zh-Hans": "网络", "zh-Hant": "網路", "en": "Network", "ja": "ネットワーク", "ko": "네트워크"],
    "settings.proxyToggle":    ["zh-Hans": "使用代理（YouTube 等需要）", "zh-Hant": "使用代理（YouTube 等需要）",
                                "en": "Use proxy (required for YouTube)", "ja": "プロキシを使う（YouTube などで必要）",
                                "ko": "프록시 사용(YouTube 등 필요)"],
    "settings.proxyAddr":      ["zh-Hans": "代理地址", "zh-Hant": "代理位址", "en": "Proxy address", "ja": "プロキシアドレス", "ko": "프록시 주소"],
    "settings.proxyHint":      ["zh-Hans": "修改后点“重启引擎”生效。", "zh-Hant": "修改後點「重新啟動引擎」生效。",
                                "en": "Click “Restart engine” after changing.", "ja": "変更後は「エンジン再起動」を押してください。",
                                "ko": "변경 후 “엔진 재시작”을 누르세요."],
    "settings.deps":           ["zh-Hans": "引擎依赖", "zh-Hant": "引擎相依", "en": "Engine dependencies", "ja": "エンジンの依存関係", "ko": "엔진 의존성"],
    "settings.depsOk":         ["zh-Hans": "aria2c / yt-dlp / ffmpeg 已就绪", "zh-Hant": "aria2c / yt-dlp / ffmpeg 已就緒",
                                "en": "aria2c / yt-dlp / ffmpeg ready", "ja": "aria2c / yt-dlp / ffmpeg 準備完了",
                                "ko": "aria2c / yt-dlp / ffmpeg 준비됨"],
    "settings.depsMissing":    ["zh-Hans": "缺少：%@", "zh-Hant": "缺少：%@", "en": "Missing: %@", "ja": "不足：%@", "ko": "누락: %@"],
    "settings.installDeps":    ["zh-Hans": "用 Homebrew 一键安装", "zh-Hant": "用 Homebrew 一鍵安裝", "en": "Install via Homebrew",
                                "ja": "Homebrew で一括インストール", "ko": "Homebrew로 설치"],
    "settings.installDepsHint":["zh-Hans": "会打开「终端」执行 brew install %@，装完回来点“重启引擎”。",
                                "zh-Hant": "會打開「終端機」執行 brew install %@，裝完回來點「重新啟動引擎」。",
                                "en": "Opens Terminal and runs: brew install %@. Then click “Restart engine”.",
                                "ja": "ターミナルで brew install %@ を実行します。完了後に「エンジン再起動」を押してください。",
                                "ko": "터미널에서 brew install %@ 을 실행합니다. 완료 후 “엔진 재시작”을 누르세요."],
    "settings.engine":         ["zh-Hans": "引擎", "zh-Hant": "引擎", "en": "Engine", "ja": "エンジン", "ko": "엔진"],
    "settings.restart":        ["zh-Hans": "重启引擎（应用线程数 / 代理改动）", "zh-Hant": "重新啟動引擎（套用執行緒數 / 代理變更）",
                                "en": "Restart engine (apply connection/proxy changes)",
                                "ja": "エンジン再起動（接続数・プロキシの変更を反映）",
                                "ko": "엔진 재시작(연결 수·프록시 변경 적용)"],
    "settings.extension":      ["zh-Hans": "浏览器扩展", "zh-Hant": "瀏覽器擴充功能", "en": "Browser extension",
                                "ja": "ブラウザ拡張", "ko": "브라우저 확장"],
    "settings.extStatus":      ["zh-Hans": "本机接口：localhost:%d（扩展靠它把链接送进来）",
                                "zh-Hant": "本機介面：localhost:%d（擴充功能靠它把連結送進來）",
                                "en": "Local API: localhost:%d (the extension sends links here)",
                                "ja": "ローカル API：localhost:%d（拡張はここにリンクを送ります）",
                                "ko": "로컬 API: localhost:%d (확장이 여기로 링크를 보냅니다)"],
    "settings.extNotRunning":  ["zh-Hans": "本机接口未启动，扩展将无法连接", "zh-Hant": "本機介面未啟動，擴充功能將無法連線",
                                "en": "Local API not running — the extension cannot connect",
                                "ja": "ローカル API が起動していません。拡張は接続できません",
                                "ko": "로컬 API가 실행되지 않아 확장이 연결할 수 없습니다"],
    "settings.extOpenFolder":  ["zh-Hans": "打开扩展文件夹", "zh-Hant": "打開擴充功能資料夾", "en": "Open extension folder",
                                "ja": "拡張フォルダを開く", "ko": "확장 폴더 열기"],
    "settings.extHint":        ["zh-Hans": "Chrome：chrome://extensions → 开发者模式 → 加载已解压的扩展程序，选 chrome 子目录。Firefox：about:debugging → 临时载入附加组件，选 firefox 子目录里的 manifest.json。",
                                "zh-Hant": "Chrome：chrome://extensions → 開發人員模式 → 載入未封裝項目，選 chrome 子目錄。Firefox：about:debugging → 載入臨時附加元件，選 firefox 子目錄裡的 manifest.json。",
                                "en": "Chrome: chrome://extensions → Developer mode → Load unpacked → pick the chrome folder. Firefox: about:debugging → Load Temporary Add-on → pick manifest.json in the firefox folder.",
                                "ja": "Chrome：chrome://extensions → デベロッパーモード → パッケージ化されていない拡張機能を読み込む（chrome フォルダ）。Firefox：about:debugging → 一時的なアドオンを読み込む（firefox フォルダの manifest.json）。",
                                "ko": "Chrome: chrome://extensions → 개발자 모드 → 압축해제된 확장 프로그램 로드 → chrome 폴더 선택. Firefox: about:debugging → 임시 부가 기능 로드 → firefox 폴더의 manifest.json 선택."],
    "settings.extMissing":     ["zh-Hans": "未找到扩展文件夹（请从 DMG 的扩展目录里加载）", "zh-Hant": "未找到擴充功能資料夾（請從 DMG 的擴充功能目錄載入）",
                                "en": "Extension folder not found (load it from the DMG folder)",
                                "ja": "拡張フォルダが見つかりません（DMG の拡張フォルダから読み込んでください）",
                                "ko": "확장 폴더를 찾을 수 없습니다(DMG의 확장 폴더에서 로드하세요)"],
    "btn.done":                ["zh-Hans": "完成", "zh-Hant": "完成", "en": "Done", "ja": "完了", "ko": "완료"],

    // 提示
    "toast.addedFile":     ["zh-Hans": "已加入多线程下载队列（%d 线程）", "zh-Hant": "已加入多執行緒下載佇列（%d 執行緒）",
                            "en": "Added to queue (%d connections)", "ja": "キューに追加しました（%d 接続）",
                            "ko": "대기열에 추가됨(%d개 연결)"],
    "toast.addedVideo":    ["zh-Hans": "已交给 yt-dlp 解析", "zh-Hant": "已交給 yt-dlp 解析", "en": "Handed to yt-dlp",
                            "ja": "yt-dlp に渡しました", "ko": "yt-dlp로 전달했습니다"],
    "toast.fromExtension": ["zh-Hans": "来自浏览器扩展", "zh-Hant": "來自瀏覽器擴充功能", "en": "From browser extension",
                            "ja": "ブラウザ拡張から", "ko": "브라우저 확장에서"],
    "toast.depMissing":    ["zh-Hans": "未找到 %@，请先安装：brew install %@", "zh-Hant": "未找到 %@，請先安裝：brew install %@",
                            "en": "%@ not found. Install it: brew install %@", "ja": "%@ が見つかりません：brew install %@",
                            "ko": "%@ 을(를) 찾을 수 없습니다: brew install %@"],
    "toast.engineBusy":    ["zh-Hans": "下载引擎未就绪", "zh-Hant": "下載引擎未就緒", "en": "Engine not ready",
                            "ja": "エンジンの準備ができていません", "ko": "엔진이 준비되지 않았습니다"],
    "toast.addFailed":     ["zh-Hans": "添加失败，请检查链接", "zh-Hant": "新增失敗，請檢查連結", "en": "Failed to add — check the link",
                            "ja": "追加に失敗しました。リンクを確認してください", "ko": "추가 실패, 링크를 확인하세요"],
    "toast.copied":        ["zh-Hans": "链接已复制", "zh-Hant": "連結已複製", "en": "Link copied", "ja": "リンクをコピーしました",
                            "ko": "링크를 복사했습니다"],
    "toast.completed":     ["zh-Hans": "「%@」已完成", "zh-Hant": "「%@」已完成", "en": "“%@” completed",
                            "ja": "「%@」が完了しました", "ko": "“%@” 완료"],
    "toast.completedMany": ["zh-Hans": "等 %d 个任务", "zh-Hant": "等 %d 個任務", "en": "and %d more", "ja": "ほか %d 件",
                            "ko": "외 %d개"],
    "toast.depsInstalling":["zh-Hans": "已在终端开始安装，装完回到这里点“重启引擎”", "zh-Hant": "已在終端機開始安裝，裝完回到這裡點「重新啟動引擎」",
                            "en": "Installing in Terminal — come back and click “Restart engine”",
                            "ja": "ターミナルでインストールを開始しました。完了後に「エンジン再起動」を押してください",
                            "ko": "터미널에서 설치를 시작했습니다. 완료 후 “엔진 재시작”을 누르세요"],
    "toast.depsOk":        ["zh-Hans": "依赖已齐全", "zh-Hant": "相依套件已齊全", "en": "Dependencies already installed",
                            "ja": "依存関係はすべて揃っています", "ko": "의존성이 모두 준비되었습니다"],
    "toast.startEngine":   ["zh-Hans": "引擎启动失败：%@", "zh-Hant": "引擎啟動失敗：%@", "en": "Engine failed to start: %@",
                            "ja": "エンジン起動に失敗：%@", "ko": "엔진 시작 실패: %@"],
    "toast.videoNoPause":  ["zh-Hans": "视频任务只能停止后重新添加", "zh-Hant": "影片任務只能停止後重新新增",
                            "en": "Video tasks can only be stopped and re-added", "ja": "動画タスクは停止して再追加のみ可能です",
                            "ko": "동영상 작업은 중지 후 다시 추가할 수 있습니다"],
    "toast.apiFailed":     ["zh-Hans": "本地接口启动失败（浏览器扩展将不可用）", "zh-Hant": "本機介面啟動失敗（瀏覽器擴充功能將無法使用）",
                            "en": "Local API failed to start (extension unavailable)",
                            "ja": "ローカル API の起動に失敗（ブラウザ拡張は使えません）",
                            "ko": "로컬 API 시작 실패(브라우저 확장 사용 불가)"],
    "toast.videoPageReroute": ["zh-Hans": "检测到这是视频页面，已自动改用「视频解析」",
                               "zh-Hant": "偵測到這是影片頁面，已自動改用「影片解析」",
                               "en": "Video page detected — switched to Video mode automatically",
                               "ja": "動画ページと判定したため「動画解析」に切り替えました",
                               "ko": "동영상 페이지로 판단되어 '동영상 분석'으로 전환했습니다"],
    "toast.pageRetryVideo":   ["zh-Hans": "下到的是网页，已删除并改用「视频解析」重试",
                               "zh-Hant": "下到的是網頁，已刪除並改用「影片解析」重試",
                               "en": "That was a web page — deleted, retrying as video",
                               "ja": "取得できたのは Web ページだったため削除し、動画解析で再試行します",
                               "ko": "웹 페이지가 내려받아져 삭제하고 동영상 분석으로 다시 시도합니다"],
    "toast.pageNotFile":      ["zh-Hans": "这个链接是网页而不是文件，请改用「视频解析」模式",
                               "zh-Hant": "這個連結是網頁而不是檔案，請改用「影片解析」模式",
                               "en": "That link is a web page, not a file — try Video mode",
                               "ja": "このリンクはファイルではなく Web ページです。「動画解析」をお試しください",
                               "ko": "이 링크는 파일이 아니라 웹 페이지입니다. '동영상 분석'을 사용하세요"],
    "toast.linkUnwrapped":    ["zh-Hans": "已从微博登录跳转地址中取出真实视频地址",
                               "zh-Hant": "已從微博登入跳轉網址中取出真實影片網址",
                               "en": "Extracted the real video URL from Weibo's login redirect",
                               "ja": "Weibo のログインリダイレクトから実際の動画 URL を取り出しました",
                               "ko": "Weibo 로그인 리디렉션에서 실제 동영상 URL을 추출했습니다"],
    "toast.linkRecovered":    ["zh-Hans": "已从跳转地址还原真实视频地址，自动重试",
                               "zh-Hant": "已從跳轉網址還原真實影片網址，自動重試",
                               "en": "Recovered the real video URL from the redirect — retrying",
                               "ja": "リダイレクトから実際の動画 URL を復元し、再試行します",
                               "ko": "리디렉션에서 실제 동영상 URL을 복원해 다시 시도합니다"],
    "toast.failed":           ["zh-Hans": "「%@」下载失败", "zh-Hant": "「%@」下載失敗", "en": "“%@” failed",
                               "ja": "「%@」のダウンロードに失敗しました", "ko": "“%@” 다운로드 실패"],
    "notify.failedTitle":     ["zh-Hans": "下载失败", "zh-Hant": "下載失敗", "en": "Download failed",
                               "ja": "ダウンロード失敗", "ko": "다운로드 실패"],
    "video.parsingTitle":     ["zh-Hans": "解析中…", "zh-Hant": "解析中…", "en": "Resolving…", "ja": "解析中…", "ko": "분석 중…"],
    "video.resolving":        ["zh-Hans": "正在解析视频信息…", "zh-Hant": "正在解析影片資訊…", "en": "Resolving video info…",
                               "ja": "動画情報を解析中…", "ko": "동영상 정보 분석 중…"],
    "video.merging":          ["zh-Hans": "正在合并音视频…", "zh-Hant": "正在合併音視訊…", "en": "Merging audio and video…",
                               "ja": "音声と映像を結合中…", "ko": "오디오와 비디오 병합 중…"],
    "video.converting":       ["zh-Hans": "正在转换格式…", "zh-Hant": "正在轉換格式…", "en": "Converting…", "ja": "形式を変換中…", "ko": "형식 변환 중…"],
    "video.finalizing":       ["zh-Hans": "下载完成，处理中…", "zh-Hant": "下載完成，處理中…", "en": "Downloaded, processing…",
                               "ja": "ダウンロード完了、処理中…", "ko": "다운로드 완료, 처리 중…"],
    "video.exitCode":         ["zh-Hans": "yt-dlp 退出码 %d（可能不支持该链接或网络受限）",
                               "zh-Hant": "yt-dlp 退出碼 %d（可能不支援該連結或網路受限）",
                               "en": "yt-dlp exited with code %d (unsupported link or network blocked)",
                               "ja": "yt-dlp が終了コード %d で終了（非対応リンクかネットワーク制限の可能性）",
                               "ko": "yt-dlp 종료 코드 %d(지원하지 않는 링크이거나 네트워크 제한)"],
    "video.startFailed":      ["zh-Hans": "yt-dlp 启动失败：%@", "zh-Hant": "yt-dlp 啟動失敗：%@", "en": "Failed to start yt-dlp: %@",
                               "ja": "yt-dlp の起動に失敗：%@", "ko": "yt-dlp 시작 실패: %@"],
    "video.doneMissing":      ["zh-Hans": "已完成（文件未找到，可能被移动）", "zh-Hant": "已完成（檔案未找到，可能被移動）",
                               "en": "Done (file not found — it may have been moved)",
                               "ja": "完了（ファイルが見つかりません。移動された可能性）",
                               "ko": "완료(파일을 찾을 수 없음, 이동되었을 수 있음)"],
    "quit.title":          ["zh-Hans": "还有 %d 个任务在下载", "zh-Hant": "還有 %d 個任務在下載", "en": "%d task(s) still downloading",
                            "ja": "まだ %d 件のタスクをダウンロード中です", "ko": "아직 %d개 작업이 다운로드 중입니다"],
    "quit.body":           ["zh-Hans": "退出会中断下载，重新添加同一链接可断点续传。",
                            "zh-Hant": "退出會中斷下載，重新新增同一連結可斷點續傳。",
                            "en": "Quitting interrupts downloads; re-adding the same link resumes.",
                            "ja": "終了すると中断されます。同じリンクを再追加すると続きから再開できます。",
                            "ko": "종료하면 중단됩니다. 같은 링크를 다시 추가하면 이어받기 됩니다."],
    "quit.confirm":        ["zh-Hans": "退出并中断", "zh-Hant": "退出並中斷", "en": "Quit anyway", "ja": "終了する", "ko": "그래도 종료"],
    "quit.cancel":         ["zh-Hans": "继续下载", "zh-Hant": "繼續下載", "en": "Keep downloading", "ja": "ダウンロードを続ける",
                            "ko": "계속 다운로드"],

    // 菜单
    "menu.openDownloadDir": ["zh-Hans": "打开下载目录", "zh-Hant": "打開下載目錄", "en": "Open Downloads Folder",
                             "ja": "ダウンロードフォルダを開く", "ko": "다운로드 폴더 열기"],
]
