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
    private var pipes: [String: Pipe] = [:]
    private var cookieFiles: [String: String] = [:]
    /// 每个任务最近一次的启动参数，供「就地重试」复用
    private var jobParams: [String: (dir: String, quality: VideoQuality, proxy: String?, referer: String?, cookies: String?)] = [:]
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

    /// 外部改写某个任务的状态说明（例如自动重试后把 yt-dlp 原文换成更好懂的提示）
    func setMessage(id: String, _ message: String) {
        mutate { $0[id]?.message = message }
    }

    /// 把长链接缩成「域名/末段」，用于失败任务的可读标题
    static func shortURL(_ url: String) -> String {
        guard let u = URL(string: url), let host = u.host else { return url }
        let tail = (u.path as NSString).lastPathComponent
        return tail.isEmpty ? host : "\(host)/\(tail)"
    }

    /// 在文件所在目录里找「同名前缀、不同扩展名」的最终产物（.mp3/.mp4/.mkv/...）
    static func siblingOutput(for path: String) -> String? {
        let dir = (path as NSString).deletingLastPathComponent
        let base = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        guard !dir.isEmpty, !base.isEmpty else { return nil }
        let exts = ["mp3", "m4a", "mp4", "mkv", "webm", "opus", "aac", "flac", "wav"]
        for e in exts {
            let cand = (dir as NSString).appendingPathComponent("\(base).\(e)")
            if FileManager.default.fileExists(atPath: cand) { return cand }
        }
        // 再宽松一点：目录里以该 base 开头的文件
        if let items = try? FileManager.default.contentsOfDirectory(atPath: dir) {
            if let hit = items.first(where: { $0.hasPrefix(base + ".") }) {
                return (dir as NSString).appendingPathComponent(hit)
            }
        }
        return nil
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
        let id = UUID().uuidString
        return launch(id: id, uri: uri, downloadDir: downloadDir, quality: quality,
                      proxy: proxy, referer: referer, cookies: cookies, fresh: true)
    }

    /// 就地重试：用**同一条任务行**重新开始（例如微博短链失败后拿到真实视频地址）
    /// 这样用户看到的是一条任务从「解析中…」到「已完成」，不会先冒出一条红色失败行
    @discardableResult
    func restart(id: String, uri: String) -> Bool {
        guard let p = jobParams[id] else { return false }
        return launch(id: id, uri: uri, downloadDir: p.dir, quality: p.quality,
                      proxy: p.proxy, referer: p.referer, cookies: p.cookies, fresh: false) != nil
    }

    @discardableResult
    private func launch(id: String, uri: String, downloadDir: String, quality: VideoQuality,
                        proxy: String?, referer: String?, cookies: String?, fresh: Bool) -> String? {
        guard let ytdlp = VideoEngine.findYtDlp() else { return nil }

        // 记住参数，供 restart 复用
        jobParams[id] = (dir: downloadDir, quality: quality, proxy: proxy, referer: referer, cookies: cookies)
        if fresh {
            jobs[id] = Job(id: id, title: L("video.parsingTitle"), uri: uri, message: L("video.resolving"))
            order.append(id)
        } else {
            mutate { jobs in
                guard var job = jobs[id] else { return }
                job.uri = uri
                job.title = L("video.parsingTitle")
                job.status = .waiting
                job.message = L("video.resolving")
                job.progress = 0
                job.doneBytes = 0
                job.totalBytes = 0
                job.speed = 0
                job.etaText = "--:--"
                job.outputPath = nil
                jobs[id] = job
            }
        }

        // 「就地重试」前先把老进程的收尾切断：否则老 yt-dlp 退出时会回调 finish()，
        // 把刚重启的任务状态又覆盖回「出错」（用户就会看到一闪而过的红色失败）
        if let old = processes[id] {
            pipes[id]?.fileHandleForReading.readabilityHandler = nil
            old.terminationHandler = nil
        }

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
            if let old = cookieFiles[id], old != cookiePath { try? FileManager.default.removeItem(atPath: old) }
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
            // 只认当前这条任务正在跑的那个进程，被换掉的老进程退出不再改状态
            guard self.processes[id] === proc else { return }
            self.finish(id: id, code: proc.terminationStatus)
        }

        do {
            try p.run()
        } catch {
            mutate { $0[id]?.status = .error; $0[id]?.message = "yt-dlp 启动失败：\(error.localizedDescription)" }
            return nil
        }
        processes[id] = p
        pipes[id] = pipe
        return id
    }

    func cancel(_ id: String) {
        processes[id]?.terminate()
    }

    /// 彻底删掉一条视频任务（**不只是终止进程**）：
    /// 以前只调 cancel()，任务数据还留在引擎里，下一轮轮询又把它读回列表 ——
    /// 用户看到的「清除已完成没用、列表里还在、通知再响一遍」就是这个原因。
    func remove(_ id: String) {
        processes[id]?.terminationHandler = nil
        pipes[id]?.fileHandleForReading.readabilityHandler = nil
        processes[id]?.terminate()
        if let cookiePath = cookieFiles.removeValue(forKey: id) {
            try? FileManager.default.removeItem(atPath: cookiePath)
        }
        processes.removeValue(forKey: id)
        pipes.removeValue(forKey: id)
        jobParams.removeValue(forKey: id)
        lock.lock()
        jobs.removeValue(forKey: id)
        order.removeAll { $0 == id }
        lock.unlock()
        onUpdate?()
    }

    func isRunning(_ id: String) -> Bool { processes[id]?.isRunning ?? false }

    // MARK: - 输出解析

    private static let percentRE = try! NSRegularExpression(
        pattern: #"^\[download\]\s+([0-9.]+)%\s+of\s+~?\s*([0-9.]+)([KMGT]?i?B)(?:\s+at\s+([0-9.]+|Unknown|N/A)\s*([KMGT]?i?B)?(/s)?)?(?:\s+ETA\s+([0-9:]+))?"#)
    private static let destRE = try! NSRegularExpression(pattern: #"^\[download\] Destination: (.+)$"#)
    private static let mergeRE = try! NSRegularExpression(pattern: #"^\[Merger\] Merging formats into "(.*)"$"#)
    /// 转码/修正容器后的最终文件（仅音频模式的 mp3、VideoConvertor 的 mp4 等）：
    /// 不认这行的话，输出路径会指向中间产物（如 .m4a），界面上就会说「文件未找到」
    private static let convertRE = try! NSRegularExpression(pattern: #"^\[(?:ExtractAudio|VideoConvertor|FixupM3u8|FixupM4a|VideoRemuxer|Metadata)[^\]]*\] Destination: (.+)$"#)
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
            // 只有「那个文件真的已经在磁盘上」才算完成；
            // 仅音频模式下 yt-dlp 会跳过下载的中间文件继续转码，此时提前标完成会让界面骗人
            let alreadyOnDisk = !path.isEmpty && FileManager.default.fileExists(atPath: path)
            mutate { jobs in
                jobs[id]?.message = L("row.existing")
                if alreadyOnDisk {
                    jobs[id]?.status = .complete
                    jobs[id]?.progress = 1
                }
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

        // 转码后的最终文件（仅音频模式 mp3 等），以这行为准覆盖掉中间产物的路径
        if let m = VideoEngine.convertRE.firstMatch(in: line, range: range) {
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
                        // 兜底：有的模式下最终文件名和中间产物不同名（如 .m4a → .mp3），
                        // 在同一个目录里按同名前缀找一下，别让界面显示「文件未找到」
                        if let fixed = Self.siblingOutput(for: path) {
                            job.outputPath = fixed
                            if let attrs = try? FileManager.default.attributesOfItem(atPath: fixed),
                               let size = attrs[.size] as? Int64 {
                                job.totalBytes = size
                                job.doneBytes = size
                            }
                            job.title = (fixed as NSString).lastPathComponent
                        } else {
                            job.message = L("video.doneMissing")
                        }
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
