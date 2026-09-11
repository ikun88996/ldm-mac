import Foundation
import AppKit

/// 全局调度：设置项、任务列表合并、轮询刷新
final class DownloadManager: ObservableObject {

    @Published var tasks: [DownloadTask] = []
    @Published var globalSpeed: Int64 = 0
    @Published var engineReady = false
    @Published var engineError: String?
    @Published var toast: String?

    @Published var downloadDir: String { didSet { save("downloadDir", downloadDir) } }
    @Published var maxConnections: Int { didSet { save("maxConnections", maxConnections) } }
    @Published var maxConcurrent: Int { didSet { save("maxConcurrent", maxConcurrent) } }
    @Published var proxyEnabled: Bool { didSet { save("proxyEnabled", proxyEnabled) } }
    @Published var proxyURL: String { didSet { save("proxyURL", proxyURL) } }
    @Published var videoQualityRaw: String { didSet { save("videoQuality", videoQualityRaw) } }

    var videoQuality: VideoQuality {
        get { VideoQuality(rawValue: videoQualityRaw) ?? .best }
        set { videoQualityRaw = newValue.rawValue }
    }

    let aria = AriaEngine()
    let video = VideoEngine()

    private var ariaOrder: [String] = []
    private var pollQueue = DispatchQueue(label: "ldm.poll", qos: .utility)
    private var isPolling = false
    private var timer: Timer?
    private var toastWork: DispatchWorkItem?

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

        video.onUpdate = { [weak self] in self?.poll() }
        startEngine()

        timer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
            self?.poll()
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    func shutdown() {
        timer?.invalidate()
        aria.stop()
    }

    // MARK: - 依赖检测 / 一键安装

    /// 缺失的 Homebrew 依赖包名
    var missingDependencies: [String] {
        var missing: [String] = []
        if AriaEngine.findBinary(named: "aria2c") == nil { missing.append("aria2") }
        if AriaEngine.findBinary(named: "yt-dlp") == nil { missing.append("yt-dlp") }
        if AriaEngine.findBinary(named: "ffmpeg") == nil { missing.append("ffmpeg") }
        return missing
    }

    func installDependencies() {
        let missing = missingDependencies
        guard !missing.isEmpty else { showToast("依赖已齐全"); return }
        guard AriaEngine.findBinary(named: "brew") != nil else {
            showToast("未检测到 Homebrew，请先安装 brew.sh")
            NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
            return
        }
        let cmd = "brew install " + missing.joined(separator: " ")
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(cmd)\"\nend tell"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if err == nil {
            showToast("已在终端开始安装，装完回到这里点“重启引擎”")
        } else {
            showToast("请手动在终端执行：\(cmd)")
        }
        // 复制命令到剪贴板兜底
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    func startEngine() {
        guard AriaEngine.findBinary(named: "aria2c") != nil else {
            engineError = "未找到 aria2c，请先执行：brew install aria2"
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
                    self.engineError = error.localizedDescription
                }
            }
        }
    }

    func restartEngine() {
        pollQueue.async { [weak self] in self?.aria.stop() }
        startEngine()
    }

    // MARK: - 添加任务

    static let videoHosts = ["youtube.com", "youtu.be", "bilibili.com", "b23.tv", "x.com", "twitter.com",
                             "tiktok.com", "douyin.com", "reddit.com", "vimeo.com", "twitch.tv",
                             "instagram.com", "facebook.com", "weibo.com", "kuaishou.com"]

    static func looksLikeVideo(_ url: String) -> Bool {
        let lower = url.lowercased()
        return videoHosts.contains { lower.contains($0) }
    }

    func add(_ rawInput: String, mode: DownloadMode) {
        var input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        if !input.lowercased().hasPrefix("http") { input = "https://" + input }

        try? FileManager.default.createDirectory(atPath: downloadDir, withIntermediateDirectories: true)

        let useVideo: Bool
        switch mode {
        case .video: useVideo = true
        case .file:  useVideo = false
        case .auto:  useVideo = DownloadManager.looksLikeVideo(input)
        }

        if useVideo {
            guard VideoEngine.findYtDlp() != nil else {
                showToast("未找到 yt-dlp，请先安装：brew install yt-dlp")
                return
            }
            let id = video.start(uri: input, downloadDir: downloadDir, quality: videoQuality,
                                 proxy: proxyEnabled ? proxyURL : nil)
            if id == nil {
                showToast("视频解析任务创建失败")
            } else {
                showToast("已交给 yt-dlp 解析")
                poll()
            }
        } else {
            guard engineReady else {
                showToast(engineError ?? "下载引擎未就绪")
                return
            }
            let conn = maxConnections
            let dir = downloadDir
            pollQueue.async { [weak self] in
                guard let self else { return }
                let gid = self.aria.add(uri: input, dir: dir, connections: conn)
                DispatchQueue.main.async {
                    if let gid {
                        self.ariaOrder.append(gid)
                        self.showToast("已加入多线程下载队列（\(conn) 线程）")
                        self.poll()
                    } else {
                        self.showToast("添加失败，请检查链接")
                    }
                }
            }
        }
    }

    // MARK: - 任务操作

    func pause(_ task: DownloadTask) {
        switch task.kind {
        case .file:
            pollQueue.async { [weak self] in self?.aria.pause(task.id) }
        case .video:
            showToast("视频任务只能停止后重新添加")
        }
    }

    func resume(_ task: DownloadTask) {
        switch task.kind {
        case .file:
            pollQueue.async { [weak self] in self?.aria.resume(task.id) }
        case .video:
            showToast("视频任务暂不支持续传")
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
        showToast("链接已复制")
    }

    func showToast(_ text: String) {
        toast = text
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
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

        // 视频任务（按创建顺序）
        for j in videoJobs {
            let name = j.outputPath.map { ($0 as NSString).lastPathComponent } ?? j.title
            out.append(DownloadTask(
                id: j.id, name: name, kind: .video, status: j.status,
                totalBytes: j.totalBytes, doneBytes: j.doneBytes, speed: j.speed,
                connections: 0, etaText: j.etaText,
                path: j.outputPath ?? "", uri: j.uri, message: j.message))
        }

        // 多线程任务（按加入顺序，新加入的排在前面）
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
                message: status == .error ? (t.errorMessage.isEmpty ? "下载失败" : t.errorMessage)
                                          : status.label))
        }

        let previousFinished = Set(tasks.filter { $0.isFinished }.map { $0.id })
        let newlyFinished = out.filter { $0.isFinished && !previousFinished.contains($0.id) }

        tasks = out
        globalSpeed = speed + videoJobs.filter { $0.status == .active }.reduce(0) { $0 + $1.speed }

        if let first = newlyFinished.first {
            NSSound(named: "Glass")?.play()
            showToast("「\(first.name)」已完成" + (newlyFinished.count > 1 ? " 等 \(newlyFinished.count) 个任务" : ""))
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
