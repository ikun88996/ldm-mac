import Foundation
import AppKit

/// 全局调度：设置项、任务列表合并、轮询刷新、浏览器扩展接口
final class DownloadManager: ObservableObject {

    @Published var tasks: [DownloadTask] = []
    @Published var globalSpeed: Int64 = 0
    @Published var engineReady = false
    @Published var engineError: String?
    @Published var toast: String?
    @Published var apiPort: Int = 0

    @Published var downloadDir: String { didSet { save("downloadDir", downloadDir) } }
    @Published var maxConnections: Int { didSet { save("maxConnections", maxConnections) } }
    @Published var maxConcurrent: Int { didSet { save("maxConcurrent", maxConcurrent) } }
    @Published var proxyEnabled: Bool { didSet { save("proxyEnabled", proxyEnabled) } }
    @Published var proxyURL: String { didSet { save("proxyURL", proxyURL) } }
    @Published var videoQualityRaw: String { didSet { save("videoQuality", videoQualityRaw) } }
    @Published var notifyOnComplete: Bool {
        didSet {
            save("notifyOnComplete", notifyOnComplete)
            if notifyOnComplete { Notifier.shared.setupIfNeeded() }
        }
    }

    var videoQuality: VideoQuality {
        get { VideoQuality(rawValue: videoQualityRaw) ?? .best }
        set { videoQualityRaw = newValue.rawValue }
    }

    let aria = AriaEngine()
    let video = VideoEngine()
    let api = LocalAPIServer()

    private var ariaOrder: [String] = []
    private var pollQueue = DispatchQueue(label: "ldm.poll", qos: .utility)
    private var isPolling = false
    private var timer: Timer?
    private var toastWork: DispatchWorkItem?
    private var lastError: String = ""
    /// 已经因为「下到网页」而重试过的链接，避免死循环
    private var retriedURLs: Set<String> = []

    // MARK: - 生命周期

    init() {
        let d = UserDefaults.standard
        let defaultDir = (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")
        downloadDir = d.string(forKey: "downloadDir") ?? defaultDir
        maxConnections = d.object(forKey: "maxConnections") as? Int ?? 16
        maxConcurrent = d.object(forKey: "maxConcurrent") as? Int ?? 5
        proxyEnabled = d.bool(forKey: "proxyEnabled")
        proxyURL = d.string(forKey: "proxyURL") ?? "http://127.0.0.1:7897"
        videoQualityRaw = d.string(forKey: "videoQuality") ?? VideoQuality.best.rawValue
        notifyOnComplete = d.object(forKey: "notifyOnComplete") as? Bool ?? true

        if notifyOnComplete { Notifier.shared.setupIfNeeded() }

        video.onUpdate = { [weak self] in self?.poll() }
        startEngine()
        startAPI()

        timer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
            self?.poll()
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    func shutdown() {
        timer?.invalidate()
        aria.stop()
        api.stop()
    }

    // MARK: - 依赖检测 / 一键安装

    var missingDependencies: [String] {
        var missing: [String] = []
        if AriaEngine.findBinary(named: "aria2c") == nil { missing.append("aria2") }
        if AriaEngine.findBinary(named: "yt-dlp") == nil { missing.append("yt-dlp") }
        if AriaEngine.findBinary(named: "ffmpeg") == nil { missing.append("ffmpeg") }
        return missing
    }

    func installDependencies() {
        let missing = missingDependencies
        guard !missing.isEmpty else { showToast(L("toast.depsOk")); return }
        guard AriaEngine.findBinary(named: "brew") != nil else {
            showToast("Homebrew not found — https://brew.sh")
            NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
            return
        }
        let cmd = "brew install " + missing.joined(separator: " ")
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(cmd)\"\nend tell"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if err == nil {
            showToast(L("toast.depsInstalling"))
        } else {
            showToast(cmd)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }

    // MARK: - 浏览器扩展

    /// 扩展文件夹：优先取与 App 同级的 DMG 目录，其次取 App 包内置的副本
    var extensionFolder: String? {
        let bundled = Bundle.main.bundleURL
        var candidates = [
            bundled.deletingLastPathComponent().appendingPathComponent("LDM-Mac-Browser-Extensions").path,
            bundled.deletingLastPathComponent().appendingPathComponent("LDM-Mac-Chrome-Extension").path
        ]
        if let res = Bundle.main.resourceURL?.appendingPathComponent("LDM-Mac-Browser-Extensions").path {
            candidates.append(res)
        }
        candidates.append(FileManager.default.currentDirectoryPath + "/extension")
        candidates.append(FileManager.default.currentDirectoryPath + "/build/extensions")

        for c in candidates where !c.isEmpty {
            if FileManager.default.fileExists(atPath: c + "/chrome/manifest.json")
                || FileManager.default.fileExists(atPath: c + "/firefox/manifest.json") { return c }
        }
        return nil
    }

    func openExtensionFolder() {
        guard let path = extensionFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - 引擎

    func startEngine() {
        guard AriaEngine.findBinary(named: "aria2c") != nil else {
            engineError = L("toast.depMissing", "aria2c", "aria2")
            engineReady = false
            return
        }
        let dir = downloadDir
        let conn = maxConnections
        let conc = maxConcurrent
        let proxy = proxyEnabled ? proxyURL : nil
        pollQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.aria.start(downloadDir: dir, proxy: proxy, maxConnections: conn, maxConcurrent: conc)
                DispatchQueue.main.async { self.engineReady = true; self.engineError = nil }
            } catch {
                DispatchQueue.main.async {
                    self.engineReady = false
                    self.engineError = L("toast.startEngine", error.localizedDescription)
                }
            }
        }
    }

    func restartEngine() {
        pollQueue.async { [weak self] in self?.aria.stop() }
        startEngine()
    }

    // MARK: - 本地 API（浏览器扩展）

    private func startAPI() {
        api.handler = { [weak self] method, path, query, body, origin in
            guard let self else { return (503, ["ok": false, "error": "app unavailable"]) }
            return self.handleAPI(method: method, path: path, query: query, body: body, origin: origin)
        }
        if api.start() {
            apiPort = api.port
        } else {
            apiPort = 0
            showToast(L("toast.apiFailed"))
        }
    }

    private func handleAPI(method: String, path: String, query: [String: String],
                           body: Data, origin: String) -> (Int, [String: Any]) {
        if method == "OPTIONS" { return (204, [:]) }

        switch (method, path) {
        case ("GET", "/ping"):
            return (200, ["ok": true, "name": "LDM Mac", "version": AppInfo.version, "api": 1])

        case ("POST", "/add"):
            guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let url = (obj["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !url.isEmpty else {
                return (400, ["ok": false, "error": "url required"])
            }
            let kind = (obj["kind"] as? String) ?? "auto"
            let referer = obj["referer"] as? String
            let cookies = obj["cookies"] as? String
            let filename = obj["filename"] as? String
            let mode: DownloadMode = kind == "video" ? .video : (kind == "file" ? .file : .auto)

            var response: [String: Any] = ["ok": false, "error": "timeout"]
            let sem = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { [weak self] in
                guard let self else { sem.signal(); return }
                if let id = self.add(url, mode: mode, referer: referer, cookies: cookies,
                                     outName: filename, quiet: true) {
                    response = ["ok": true, "id": id]
                } else {
                    response = ["ok": false, "error": self.lastError.isEmpty ? "add failed" : self.lastError]
                }
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 10)
            return (200, response)

        case ("GET", "/tasks"):
            var list: [[String: Any]] = []
            var speed: Int64 = 0
            let sem = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { [weak self] in
                guard let self else { sem.signal(); return }
                list = self.tasks.map { $0.json }
                speed = self.globalSpeed
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 3)
            return (200, ["ok": true, "tasks": list, "globalSpeed": speed])

        case ("POST", "/task"):
            guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let id = obj["id"] as? String,
                  let action = obj["action"] as? String else {
                return (400, ["ok": false, "error": "id and action required"])
            }
            var found = false
            let sem = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { [weak self] in
                guard let self, let task = self.tasks.first(where: { $0.id == id }) else { sem.signal(); return }
                found = true
                switch action {
                case "pause":  self.pause(task)
                case "resume": self.resume(task)
                case "remove": self.remove(task)
                case "reveal": self.reveal(task)
                case "open":   self.openFile(task)
                default:       found = false
                }
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 3)
            return found ? (200, ["ok": true]) : (404, ["ok": false, "error": "task not found"])

        default:
            return (404, ["ok": false, "error": "not found"])
        }
    }

    // MARK: - 添加任务

    static let videoHosts = ["youtube.com", "youtu.be", "bilibili.com", "b23.tv", "x.com", "twitter.com",
                             "tiktok.com", "douyin.com", "reddit.com", "vimeo.com", "twitch.tv",
                             "instagram.com", "facebook.com", "weibo.com", "kuaishou.com", "v.qq.com",
                             "youku.com", "iqiyi.com", "ixigua.com", "weibo.cn"]
    /// 常见媒体后缀：扩展嗅探到的直链按多线程下载处理
    static let mediaExtensions = [".mp4", ".m4v", ".mov", ".mkv", ".webm", ".flv", ".ts", ".m3u8", ".mpd",
                                  ".mp3", ".m4a", ".aac", ".flac", ".wav", ".ogg",
                                  ".zip", ".rar", ".7z", ".dmg", ".pkg", ".exe", ".iso", ".apk",
                                  ".gguf", ".safetensors", ".bin", ".pdf", ".epub"]

    static func looksLikeVideo(_ url: String) -> Bool {
        let lower = url.lowercased()
        return videoHosts.contains { lower.contains($0) }
    }

    static func looksLikeMedia(_ url: String) -> Bool {
        let lower = url.lowercased()
        let path = lower.split(separator: "?").first.map(String.init) ?? lower
        return mediaExtensions.contains { path.hasSuffix($0) }
    }

    /// 添加任务，返回任务 id（扩展/界面共用）
    @discardableResult
    func add(_ rawInput: String, mode: DownloadMode,
             referer: String? = nil, cookies: String? = nil, outName: String? = nil,
             quiet: Bool = false) -> String? {
        var input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { lastError = "empty url"; return nil }
        if !input.lowercased().hasPrefix("http") { input = "https://" + input }

        try? FileManager.default.createDirectory(atPath: downloadDir, withIntermediateDirectories: true)

        /// 视频页面（B站/YouTube/微博这类），而不是媒体直链
        let isVideoPage = DownloadManager.looksLikeVideo(input) && !DownloadManager.looksLikeMedia(input)

        let useVideo: Bool
        switch mode {
        case .video:
            useVideo = true
        case .file:
            // 页面链接交给 aria2 只会下到一个网页（微博甚至会被跳转到访客登录页），自动改用视频解析
            useVideo = isVideoPage
            if useVideo && !quiet { showToast(L("toast.videoPageReroute")) }
        case .auto:
            useVideo = isVideoPage
        }

        if useVideo {
            guard VideoEngine.findYtDlp() != nil else {
                lastError = "yt-dlp missing"
                if !quiet { showToast(L("toast.depMissing", "yt-dlp", "yt-dlp")) }
                return nil
            }
            guard let id = video.start(uri: input, downloadDir: downloadDir, quality: videoQuality,
                                       proxy: proxyEnabled ? proxyURL : nil,
                                       referer: referer, cookies: cookies) else {
                lastError = "yt-dlp start failed"
                return nil
            }
            if !quiet { showToast(L("toast.addedVideo")) }
            poll()
            return id
        }

        guard engineReady else {
            lastError = engineError ?? "engine not ready"
            if !quiet { showToast(L("toast.engineBusy")) }
            return nil
        }
        let conn = maxConnections
        let dir = downloadDir
        var gid: String?
        let sem = DispatchSemaphore(value: 0)
        pollQueue.async { [weak self] in
            guard let self else { sem.signal(); return }
            let result = self.aria.add(uri: input, dir: dir, connections: conn,
                                       referer: referer, cookies: cookies, outName: outName)
            gid = result
            DispatchQueue.main.async {
                if let g = result {
                    self.ariaOrder.append(g)
                    if !quiet { self.showToast(L("toast.addedFile", conn)) }
                    self.poll()
                } else if !quiet {
                    self.showToast(L("toast.addFailed"))
                }
            }
            sem.signal()   // 在后台线程唤醒，避免与主线程互等
        }
        _ = sem.wait(timeout: .now() + 8)
        if gid == nil { lastError = "aria2 add failed" }
        return gid
    }

    // MARK: - 任务操作

    func pause(_ task: DownloadTask) {
        switch task.kind {
        case .file:  pollQueue.async { [weak self] in self?.aria.pause(task.id) }
        case .video: showToast(L("toast.videoNoPause"))
        }
    }

    func resume(_ task: DownloadTask) {
        switch task.kind {
        case .file:  pollQueue.async { [weak self] in self?.aria.resume(task.id) }
        case .video: showToast(L("toast.videoNoPause"))
        }
    }

    func remove(_ task: DownloadTask) {
        switch task.kind {
        case .file:
            ariaOrder.removeAll { $0 == task.id }
            pollQueue.async { [weak self] in self?.aria.remove(task.id) }
        case .video:
            video.cancel(task.id)
        }
        tasks.removeAll { $0.id == task.id }
    }

    func pauseAll()  { pollQueue.async { [weak self] in self?.aria.pauseAll() } }
    func resumeAll() { pollQueue.async { [weak self] in self?.aria.resumeAll() } }

    func clearFinished() {
        tasks.filter { $0.isFinished }.forEach { remove($0) }
    }

    func reveal(_ task: DownloadTask) {
        guard !task.path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: task.path)])
    }

    func openFile(_ task: DownloadTask) {
        guard !task.path.isEmpty, FileManager.default.fileExists(atPath: task.path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: task.path))
    }

    func openDownloadDir() {
        NSWorkspace.shared.open(URL(fileURLWithPath: downloadDir))
    }

    func copyLink(_ task: DownloadTask) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(task.uri, forType: .string)
        showToast(L("toast.copied"))
    }

    func showToast(_ text: String) {
        toast = text
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
    }

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: - 轮询刷新

    private func poll() {
        if isPolling { return }
        isPolling = true
        pollQueue.async { [weak self] in
            guard let self else { return }
            let result: ([AriaTask], Int64) = self.aria.isRunning ? self.aria.snapshot() : ([], 0)
            let videoJobs = self.video.snapshot()
            DispatchQueue.main.async {
                self.apply(aria: result.0, speed: result.1, video: videoJobs)
                self.isPolling = false
            }
        }
    }

    private func apply(aria list: [AriaTask], speed: Int64, video videoJobs: [VideoEngine.Job]) {
        var out: [DownloadTask] = []

        for j in videoJobs {
            let name = j.outputPath.map { ($0 as NSString).lastPathComponent } ?? j.title
            out.append(DownloadTask(
                id: j.id, name: name, kind: .video, status: j.status,
                totalBytes: j.totalBytes, doneBytes: j.doneBytes, speed: j.speed,
                connections: 0, etaText: j.etaText,
                path: j.outputPath ?? "", uri: j.uri, message: j.message))
        }

        let byGid = Dictionary(uniqueKeysWithValues: list.map { ($0.gid, $0) })
        var gids = ariaOrder.filter { byGid[$0] != nil }
        for t in list where !gids.contains(t.gid) { gids.append(t.gid) }
        ariaOrder = gids

        for gid in gids {
            guard let t = byGid[gid] else { continue }
            let status = mapStatus(t.status)
            let name = t.path.isEmpty ? t.uri : (t.path as NSString).lastPathComponent
            var eta = "--:--"
            if t.speed > 0, t.totalBytes > t.doneBytes {
                eta = Fmt.eta(Int(Double(t.totalBytes - t.doneBytes) / Double(t.speed)))
            }
            out.append(DownloadTask(
                id: gid, name: name, kind: .file, status: status,
                totalBytes: t.totalBytes, doneBytes: t.doneBytes, speed: t.speed,
                connections: t.connections, etaText: eta,
                path: t.path, uri: t.uri,
                message: status == .error ? (t.errorMessage.isEmpty ? "failed" : t.errorMessage)
                                          : status.label))
        }

        let previousFinished = Set(tasks.filter { $0.isFinished }.map { $0.id })
        var newlyFinished = out.filter { $0.isFinished && !previousFinished.contains($0.id) }

        // 揪出「下到的其实是网页」的假成功（微博页面链接被跳转到访客登录页就是这么来的）
        let bogus = newlyFinished.filter { isBogusWebPage($0) }
        if !bogus.isEmpty {
            newlyFinished.removeAll { t in bogus.contains { $0.id == t.id } }
        }

        tasks = out
        globalSpeed = speed + videoJobs.filter { $0.status == .active }.reduce(0) { $0 + $1.speed }

        for b in bogus { recoverFromWebPage(b) }

        if let first = newlyFinished.first {
            NSSound(named: "Glass")?.play()
            let extra = newlyFinished.count > 1 ? " " + L("toast.completedMany", newlyFinished.count) : ""
            showToast(L("toast.completed", first.name) + extra)

            if notifyOnComplete {
                Notifier.shared.notify(title: L("notify.title"),
                                       body: L("notify.body", first.name, Fmt.bytes(first.totalBytes)))
            }
        }
    }

    /// 内容是 HTML 的「文件」任务 —— 基本可以断定是把网页当文件下了
    private func isBogusWebPage(_ task: DownloadTask) -> Bool {
        guard task.kind == .file, task.status == .complete, !task.path.isEmpty else { return false }

        // 用户明确要下文档时不动它
        let urlPath = task.uri.lowercased().split(separator: "?").first.map(String.init) ?? ""
        let docExts = [".html", ".htm", ".xhtml", ".txt", ".json", ".xml", ".md", ".csv", ".srt", ".vtt"]
        if docExts.contains(where: { urlPath.hasSuffix($0) }) { return false }

        guard let fh = FileHandle(forReadingAtPath: task.path) else { return false }
        defer { try? fh.close() }
        let data = fh.readData(ofLength: 1024)
        guard !data.isEmpty else { return false }
        let head = String(decoding: data, as: UTF8.self).lowercased()
        return head.contains("<!doctype html") || head.contains("<html")
    }

    /// 删掉误下的网页文件，能识别的就改用 yt-dlp 重试
    private func recoverFromWebPage(_ task: DownloadTask) {
        if !task.path.isEmpty { try? FileManager.default.removeItem(atPath: task.path) }
        remove(task)

        if DownloadManager.looksLikeVideo(task.uri), !retriedURLs.contains(task.uri) {
            retriedURLs.insert(task.uri)
            showToast(L("toast.pageRetryVideo"))
            _ = add(task.uri, mode: .video, quiet: true)
        } else {
            showToast(L("toast.pageNotFile"))
        }
    }

    private func mapStatus(_ s: String) -> TaskStatus {
        switch s {
        case "active":   return .active
        case "waiting":  return .waiting
        case "paused":   return .paused
        case "complete": return .complete
        case "error", "removed": return .error
        default: return .waiting
        }
    }
}
