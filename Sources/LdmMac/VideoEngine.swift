import Foundation

/// yt-dlp 视频解析引擎：嗅探页面视频、选最高画质、自动调用 ffmpeg 合并音视频轨。
final class VideoEngine {

    struct Job {
        var id: String
        var title: String
        var uri: String
        var status: TaskStatus = .waiting
        var progress: Double = 0
        var doneBytes: Int64 = 0
        var totalBytes: Int64 = 0
        var speed: Int64 = 0
        var etaText: String = "--:--"
        var message: String = ""
        var outputPath: String?
    }

    private var jobs: [String: Job] = [:]
    private var order: [String] = []
    private var processes: [String: Process] = [:]
    private var cookieFiles: [String: String] = [:]
    private let lock = NSLock()
    var onUpdate: (() -> Void)?

    /// 把扩展送来的 Cookie 字符串写成 yt-dlp 能读的 Netscape 格式文件
    static func writeCookieFile(_ cookies: String, for url: String) -> String? {
        let host = URL(string: url)?.host ?? ""
        var domain = host
        if let dot = host.firstIndex(of: ".") { domain = String(host[dot...]) }   // 保留 .weibo.com 这种一级后缀
        var lines = ["# Netscape HTTP Cookie File", "# 由 LDM Mac 临时生成，任务结束即删除"]
        for pair in cookies.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let name = kv[0].trimmingCharacters(in: .whitespaces)
            let value = kv[1].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            lines.append("\(domain)\tTRUE\t/\tFALSE\t0\t\(name)\t\(value)")
        }
        guard lines.count > 2 else { return nil }
        let path = NSTemporaryDirectory() + "ldm-cookies-\(UUID().uuidString).txt"
        do {
            try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            return path
        } catch {
            return nil
        }
    }

    static func findYtDlp() -> String? { AriaEngine.findBinary(named: "yt-dlp") }

    /// 把长链接缩成「域名/末段」，用于失败任务的可读标题
    static func shortURL(_ url: String) -> String {
        guard let u = URL(string: url), let host = u.host else { return url }
        let tail = (u.path as NSString).lastPathComponent
        return tail.isEmpty ? host : "\(host)/\(tail)"
    }

    /// 所有变动都在锁内完成，回调在锁外触发，避免死锁
    private func mutate(_ block: (inout [String: Job]) -> Void) {
        lock.lock()
        block(&jobs)
        lock.unlock()
        onUpdate?()
    }

    func snapshot() -> [Job] {
        lock.lock(); defer { lock.unlock() }
        return order.compactMap { jobs[$0] }
    }

    @discardableResult
    func start(uri: String, downloadDir: String, quality: VideoQuality,
               proxy: String? = nil, referer: String? = nil, cookies: String? = nil) -> String? {
        guard let ytdlp = VideoEngine.findYtDlp() else { return nil }

        let id = UUID().uuidString
        jobs[id] = Job(id: id, title: L("video.parsingTitle"), uri: uri, message: L("video.resolving"))
        order.append(id)

        var args = ["--newline", "--no-warnings", "--no-playlist", "--progress", "--progress-delta", "0.5",
                    "-o", "\(downloadDir)/%(title)s.%(ext)s"]
        switch quality {
        case .best:
            args += ["-f", "bv*+ba/b", "--merge-output-format", "mp4"]
        case .p1080:
            args += ["-f", "bv*[height<=1080]+ba/b[height<=1080]", "--merge-output-format", "mp4"]
        case .audioOnly:
            args += ["-f", "bestaudio/best", "-x", "--audio-format", "mp3"]
        }
        if let referer, !referer.isEmpty {
            args += ["--add-headers", "Referer: \(referer)"]
        }
        if let cookies, !cookies.isEmpty, let cookiePath = VideoEngine.writeCookieFile(cookies, for: uri) {
            args += ["--cookies", cookiePath]
            cookieFiles[id] = cookiePath
        }
        if let proxy, !proxy.isEmpty { args += ["--proxy", proxy] }
        args.append(uri)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: ytdlp)
        p.arguments = args

        // 给子进程补全 PATH，保证 yt-dlp 能找到 ffmpeg
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            guard let self else { return }
            let data = fh.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                self.parse(String(line), id: id)
            }
        }

        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            pipe.fileHandleForReading.readabilityHandler = nil
            self.finish(id: id, code: proc.terminationStatus)
        }

        do {
            try p.run()
        } catch {
            mutate { $0[id]?.status = .error; $0[id]?.message = "yt-dlp 启动失败：\(error.localizedDescription)" }
            return nil
        }
        processes[id] = p
        return id
    }

    func cancel(_ id: String) {
        processes[id]?.terminate()
    }

    func isRunning(_ id: String) -> Bool { processes[id]?.isRunning ?? false }

    // MARK: - 输出解析

    private static let percentRE = try! NSRegularExpression(
        pattern: #"^\[download\]\s+([0-9.]+)%\s+of\s+~?\s*([0-9.]+)([KMGT]?i?B)(?:\s+at\s+([0-9.]+|Unknown|N/A)\s*([KMGT]?i?B)?(/s)?)?(?:\s+ETA\s+([0-9:]+))?"#)
    private static let destRE = try! NSRegularExpression(pattern: #"^\[download\] Destination: (.+)$"#)
    private static let mergeRE = try! NSRegularExpression(pattern: #"^\[Merger\] Merging formats into "(.+)"$"#)
    private static let titleRE = try! NSRegularExpression(pattern: #"^\[info\] .*: Downloading (?:1 video|1 audio|\d+ format)"#)

    private func parse(_ raw: String, id: String) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        if line.hasPrefix("ERROR:") {
            let msg = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            mutate { jobs in
                jobs[id]?.status = .error
                jobs[id]?.message = msg
                jobs[id]?.speed = 0
                // 失败时还没解析出标题，就用链接标识这个任务，别显示成「解析中…」
                let placeholder = L("video.parsingTitle")
                let current = jobs[id]?.title ?? ""
                if current.isEmpty || current == placeholder {
                    let link = jobs[id]?.uri ?? ""
                    jobs[id]?.title = VideoEngine.shortURL(link)
                }
            }
            return
        }
        if line.hasPrefix("WARNING:") { return }

        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)

        if let m = VideoEngine.percentRE.firstMatch(in: line, range: range) {
            let pct = Double(ns.substring(with: m.range(at: 1))) ?? 0
            let sizeVal = Double(ns.substring(with: m.range(at: 2))) ?? 0
            let sizeUnit = ns.substring(with: m.range(at: 3))
            let total = Int64(sizeVal * unitFactor(sizeUnit))
            var speed: Int64 = 0
            if m.range(at: 4).location != NSNotFound {
                let sv = Double(ns.substring(with: m.range(at: 4))) ?? 0
                let su = m.range(at: 5).location != NSNotFound ? ns.substring(with: m.range(at: 5)) : "B"
                speed = Int64(sv * unitFactor(su))
            }
            var eta = "--:--"
            if m.range(at: 7).location != NSNotFound { eta = ns.substring(with: m.range(at: 7)) }
            mutate { jobs in
                jobs[id]?.progress = min(1, pct / 100)
                jobs[id]?.totalBytes = total
                jobs[id]?.doneBytes = Int64(Double(total) * pct / 100)
                jobs[id]?.speed = speed
                jobs[id]?.etaText = eta
                jobs[id]?.status = .active
                jobs[id]?.message = L("status.active")
            }
            return
        }

        if line.contains("has already been downloaded") {
            let path = line.replacingOccurrences(of: "[download] ", with: "")
                .components(separatedBy: " has already been downloaded").first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            mutate { jobs in
                jobs[id]?.status = .complete
                jobs[id]?.progress = 1
                jobs[id]?.message = L("row.existing")
                let placeholder = L("video.parsingTitle")
                let current = jobs[id]?.title ?? ""
                if !path.isEmpty, current.isEmpty || current == placeholder {
                    jobs[id]?.outputPath = path
                    jobs[id]?.title = (path as NSString).lastPathComponent
                }
            }
            return
        }

        if let m = VideoEngine.mergeRE.firstMatch(in: line, range: range) {
            let path = ns.substring(with: m.range(at: 1))
            mutate { $0[id]?.outputPath = path; $0[id]?.message = L("video.merging") }
            return
        }

        if let m = VideoEngine.destRE.firstMatch(in: line, range: range) {
            let path = ns.substring(with: m.range(at: 1))
            mutate { jobs in
                jobs[id]?.outputPath = path
                let placeholder = L("video.parsingTitle")
                if (jobs[id]?.title ?? "").isEmpty || (jobs[id]?.title ?? "") == placeholder {
                    jobs[id]?.title = (path as NSString).lastPathComponent
                }
            }
            return
        }

        if line.hasPrefix("[download]") && line.contains("100%") {
            mutate { $0[id]?.progress = 1; $0[id]?.message = L("video.finalizing") }
            return
        }

        // 尽量从其他行里猜标题
        if line.contains("[youtube]") || line.contains("[bilibili]") || line.contains("[BiliBili]") {
            if let r = line.range(of: ": Downloading") {
                let title = String(line[line.startIndex..<r.lowerBound])
                    .replacingOccurrences(of: "[youtube] ", with: "")
                    .replacingOccurrences(of: "[BiliBili] ", with: "")
                    .replacingOccurrences(of: "[bilibili] ", with: "")
                if !title.isEmpty, !title.hasPrefix("Extracting") {
                    mutate { $0[id]?.title = title }
                }
            }
        }

        if line.contains("[ExtractAudio]") || line.contains("[VideoConvertor]") || line.contains("[FixupM3u8]") {
            mutate { $0[id]?.message = L("video.converting"); $0[id]?.speed = 0 }
        }
    }

    private func finish(id: String, code: Int32) {
        if let cookiePath = cookieFiles.removeValue(forKey: id) {
            try? FileManager.default.removeItem(atPath: cookiePath)
        }
        mutate { jobs in
            guard var job = jobs[id] else { return }
            if job.status != .error {
                if code == 0 {
                    job.status = .complete
                    job.progress = 1
                    job.speed = 0
                    job.etaText = "--:--"
                    job.message = L("status.complete")
                    if let path = job.outputPath, FileManager.default.fileExists(atPath: path) {
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                           let size = attrs[.size] as? Int64 {
                            job.totalBytes = size
                            job.doneBytes = size
                        }
                    } else if let path = job.outputPath {
                        job.message = L("video.doneMissing")
                        _ = path
                    }
                } else {
                    job.status = .error
                    job.message = L("video.exitCode", Int(code))
                }
            }
            job.speed = 0
            jobs[id] = job
        }
    }

    private func unitFactor(_ unit: String) -> Double {
        switch unit {
        case "KiB", "KB", "K": return 1024
        case "MiB", "MB", "M": return 1024 * 1024
        case "GiB", "GB", "G": return 1024 * 1024 * 1024
        case "TiB", "TB", "T": return 1024 * 1024 * 1024 * 1024
        default: return 1
        }
    }
}
