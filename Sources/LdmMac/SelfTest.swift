import Foundation

/// 无界面自检：用真实下载验证内核（aria2 多线程 / yt-dlp 视频解析）是否可用
/// 用法：LdmMac --selftest <url> [--dir /tmp/xxx] [--conn 16] [--video] [--p1080|--audio] [--timeout 300]
enum SelfTest {
    static var exitCode: Int32 = 0

    static func run(args: [String]) {
        if args.contains("--i18n-check") {
            runI18nCheck()
            return
        }
        if let i = args.firstIndex(of: "--douyin-resolve"), i + 1 < args.count {
            runDouyinResolve(args[i + 1])
            return
        }

        var url = ""
        var dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("ldm-selftest")
        var conn = 16
        var video = false
        var quality: VideoQuality = .best
        var timeout: Double = 300

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--dir":     i += 1; if i < args.count { dir = args[i] }
            case "--conn":    i += 1; if i < args.count { conn = Int(args[i]) ?? 16 }
            case "--timeout": i += 1; if i < args.count { timeout = Double(args[i]) ?? 300 }
            case "--video":   video = true
            case "--p1080":   video = true; quality = .p1080
            case "--audio":   video = true; quality = .audioOnly
            default:          url = args[i]
            }
            i += 1
        }

        guard !url.isEmpty else {
            print("用法：LdmMac --selftest <url> [--dir 路径] [--conn 16] [--video|--p1080|--audio]")
            exitCode = 2
            return
        }

        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        print("== LDM Mac 自检 ==")
        print("目标: \(url)")
        print("目录: \(dir)")
        print("模式: \(video ? "视频(yt-dlp, \(quality.rawValue))" : "多线程(aria2, \(conn) 线程)")")

        if video {
            runVideo(url: url, dir: dir, timeout: timeout, quality: quality)
        } else {
            runFile(url: url, dir: dir, conn: conn, timeout: timeout)
        }
    }

    // MARK: - 多语言自检

    static func runI18nCheck() {
        let l10n = L10n.shared
        let keys = l10n.allKeys
        let langs = L10n.allLangs
        print("== LDM Mac 多语言检查 ==")
        print("语言数：\(langs.count)（\(langs.map { $0.rawValue }.joined(separator: " / "))）")
        print("文案 key 总数：\(keys.count)")

        let missing = l10n.missingTranslations()
        if missing.isEmpty {
            print("✅ 所有语言全部齐全，无缺失")
        } else {
            print("❌ 缺失 \(missing.count) 条：\(missing.prefix(20).joined(separator: " | "))")
            exitCode = 1
        }

        let samples = ["app.subtitle", "btn.download", "empty.title", "settings.extension", "status.active", "notify.title"]
        for lang in langs {
            print("--- \(lang.rawValue) ---")
            for k in samples {
                print("  \(k) = \(l10n.t(k, lang: lang))")
            }
        }
    }

    // MARK: - 抖音解析自检

    private static func runDouyinResolve(_ input: String) {
        setbuf(stdout, nil)      // 实时输出，卡住时能看到卡在哪一步
        print("== 抖音解析自检 ==")
        print("输入: \(input.prefix(80))\(input.count > 80 ? "…" : "")")

        guard let link = DouyinResolver.extractLink(from: input) else {
            print("❌ 没能从输入里认出抖音链接")
            exitCode = 1
            return
        }
        print("认出链接: \(link)")
        guard DouyinResolver.isDouyin(link) else {
            print("❌ 这不是抖音域名")
            exitCode = 1
            return
        }
        guard let item = DouyinResolver.resolve(link) else {
            print("❌ 解析失败（接口没返回 aweme_detail）")
            print("   接口返回开头: \(DouyinResolver.lastResponsePreview)")
            print("   cookie 头长度: \(DouyinResolver.lastCookieHeader.count)")
            exitCode = 1
            return
        }
        print("✅ 解析成功")
        print("   aweme_id : \(item.id)")
        print("   标题     : \(item.title)")
        print("   作者     : \(item.author)")
        print("   时长     : \(item.durationMs / 1000) 秒")
        print("   文件名   : \(DouyinResolver.fileName(item.title)).mp4")
        if item.images.isEmpty {
            print("   无水印地址: \(item.playURL.prefix(110))…")
            // 顺便验证这个地址真能下（只取前 256KB 探路）
            var req = URLRequest(url: URL(string: item.playURL)!)
            req.setValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")
            req.setValue(item.cookieHeader, forHTTPHeaderField: "Cookie")
            req.setValue("bytes=0-262143", forHTTPHeaderField: "Range")
            let sem = DispatchSemaphore(value: 0)
            var code = 0, size = 0, ctype = ""
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                size = data?.count ?? 0
                ctype = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
                sem.signal()
            }.resume()
            _ = sem.wait(timeout: .now() + 25)
            if (200...206).contains(code) && size > 0 {
                print("   ✅ 地址可用：HTTP \(code)，取到 \(size) 字节，类型 \(ctype)")
            } else {
                print("   ❌ 地址不可用：HTTP \(code)，\(size) 字节")
                exitCode = 1
            }
        } else {
            print("   图集共 \(item.images.count) 张，首张: \(item.images[0].prefix(90))…")
        }
    }

    // MARK: aria2 多线程

    private static func runFile(url: String, dir: String, conn: Int, timeout: Double) {
        let aria = AriaEngine()
        do {
            try aria.start(downloadDir: dir, proxy: nil, maxConnections: conn, maxConcurrent: 3)
            print("aria2 引擎已启动，RPC 端口 \(aria.port)")
        } catch {
            print("❌ 引擎启动失败：\(error.localizedDescription)")
            exitCode = 1
            return
        }

        guard let gid = aria.add(uri: url, dir: dir, connections: conn) else {
            print("❌ 添加任务失败（链接或网络问题）")
            aria.stop()
            exitCode = 1
            return
        }
        print("任务 GID: \(gid)")

        let start = Date()
        var lastPrint = Date.distantPast
        var finalTask: AriaTask?

        while Date().timeIntervalSince(start) < timeout {
            guard let t = aria.snapshot().tasks.first(where: { $0.gid == gid }) else {
                Thread.sleep(forTimeInterval: 0.5); continue
            }
            finalTask = t
            if Date().timeIntervalSince(lastPrint) > 1.0 {
                lastPrint = Date()
                let pct = t.totalBytes > 0 ? Double(t.doneBytes) / Double(t.totalBytes) * 100 : 0
                print(String(format: "[%@] %5.1f%%  %@ / %@  %@  %d 连接",
                             t.status, pct, Fmt.bytes(t.doneBytes), Fmt.bytes(t.totalBytes),
                             Fmt.speed(t.speed), t.connections))
            }
            if t.status == "complete" { break }
            if t.status == "error" || t.status == "removed" {
                print("❌ 下载出错：\(t.errorMessage)")
                aria.stop()
                exitCode = 1
                return
            }
            Thread.sleep(forTimeInterval: 0.4)
        }

        let elapsed = Date().timeIntervalSince(start)
        defer { aria.stop() }

        guard let t = finalTask, t.status == "complete" else {
            print("❌ 超时未完成（\(Int(elapsed))s），最后状态：\(finalTask?.status ?? "无")")
            exitCode = 1
            return
        }

        // 校验落盘文件
        let path = t.path
        var diskSize: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64 { diskSize = size }
        print("✅ 完成：\(path)")
        print("   声明大小 \(Fmt.bytes(t.totalBytes)) / 落盘 \(Fmt.bytes(diskSize)) / 用时 \(String(format: "%.1f", elapsed))s / 均速 \(Fmt.speed(Int64(Double(t.totalBytes) / max(elapsed, 0.001))))")
        if t.totalBytes > 0 && diskSize == t.totalBytes {
            print("   大小校验通过 ✔︎")
        } else {
            print("   ⚠️ 大小与声明不一致")
            exitCode = 1
        }
    }

    // MARK: yt-dlp 视频

    private static func runVideo(url: String, dir: String, timeout: Double, quality: VideoQuality) {
        guard VideoEngine.findYtDlp() != nil else {
            print("❌ 未找到 yt-dlp")
            exitCode = 1
            return
        }
        let engine = VideoEngine()
        let proxy = ProcessInfo.processInfo.environment["LDM_TEST_PROXY"]
        guard let id = engine.start(uri: url, downloadDir: dir, quality: quality, proxy: proxy) else {
            print("❌ 无法启动 yt-dlp")
            exitCode = 1
            return
        }
        print("视频任务已创建，代理：\(proxy ?? "无")")

        let start = Date()
        var lastPrint = Date.distantPast
        while Date().timeIntervalSince(start) < timeout {
            guard let job = engine.snapshot().first(where: { $0.id == id }) else { break }
            if Date().timeIntervalSince(lastPrint) > 1.5 {
                lastPrint = Date()
                print(String(format: "[%@] %5.1f%%  %@ / %@  %@  %@",
                             job.status.rawValue, job.progress * 100,
                             Fmt.bytes(job.doneBytes), Fmt.bytes(job.totalBytes),
                             Fmt.speed(job.speed), job.message))
            }
            if job.status == .complete || job.status == .error {
                print(job.status == .complete ? "✅ 视频完成" : "❌ 视频失败")
                if let p = job.outputPath {
                    let attrs = try? FileManager.default.attributesOfItem(atPath: p)
                    let size = (attrs?[.size] as? Int64) ?? 0
                    print("   输出：\(p)  大小：\(Fmt.bytes(size))")
                }
                print("   状态信息：\(job.message)")
                exitCode = job.status == .complete ? 0 : 1
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        print("❌ 超时（\(Int(timeout))s）")
        engine.cancel(id)
        exitCode = 1
    }
}
