import Foundation

enum EngineError: Error, LocalizedError {
    case aria2Missing
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .aria2Missing:
            return "找不到 aria2c。请先安装：brew install aria2"
        case .startFailed(let m):
            return "aria2 引擎启动失败：\(m)"
        }
    }
}

struct AriaTask {
    var gid: String
    var status: String
    var totalBytes: Int64
    var doneBytes: Int64
    var speed: Int64
    var connections: Int
    var path: String
    var uri: String
    var errorMessage: String
}

/// aria2c JSON-RPC 引擎：多线程分段、断点续传、队列都由它负责。
final class AriaEngine {
    private var process: Process?
    private var stderrTail: [String] = []
    private let tailLock = NSLock()
    private let session: URLSession

    private(set) var port: Int = 0
    private(set) var secret: String = ""

    /// 常用安装位置 + PATH 查找（GUI 启动时 PATH 很短，必须硬编码兜底）
    static func findBinary(named name: String) -> String? {
        let home = NSHomeDirectory()
        var candidates = [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/opt/local/bin/\(name)"
        ]
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            candidates += pathEnv.split(separator: ":").map { "\($0)/\(name)" }
        }
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]   // 回环地址不走系统代理
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 20
        session = URLSession(configuration: cfg)
    }

    var isRunning: Bool { process?.isRunning ?? false }

    func start(downloadDir: String, proxy: String?, maxConnections: Int, maxConcurrent: Int) throws {
        stop()
        guard let bin = AriaEngine.findBinary(named: "aria2c") else { throw EngineError.aria2Missing }

        secret = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        port = Int.random(in: 6870...7870)

        var args = [
            "--enable-rpc",
            "--rpc-listen-all=false",
            "--rpc-listen-port=\(port)",
            "--rpc-secret=\(secret)",
            "--rpc-max-request-size=16M",
            "--continue=true",
            "--max-concurrent-downloads=\(maxConcurrent)",
            "--split=\(maxConnections)",
            "--max-connection-per-server=\(maxConnections)",
            "--min-split-size=1M",
            "--file-allocation=none",
            "--auto-file-renaming=false",
            "--allow-overwrite=false",
            "--content-disposition-default-utf8=true",
            "--summary-interval=0",
            "--console-log-level=warn",
            "--follow-metalink=true",
            "--check-integrity=false",
            // 父进程（App）退出时 aria2 自动结束，避免残留孤儿进程
            "--stop-with-process=\(ProcessInfo.processInfo.processIdentifier)",
            "--user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) LdmMac/1.0 Safari/605.1.15",
            "--dir=\(downloadDir)"
        ]
        if let proxy, !proxy.isEmpty {
            args.append("--all-proxy=\(proxy)")
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice

        let errPipe = Pipe()
        p.standardError = errPipe
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            guard let self else { return }
            let data = fh.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            self.tailLock.lock()
            self.stderrTail.append(s)
            if self.stderrTail.count > 60 { self.stderrTail.removeFirst(self.stderrTail.count - 60) }
            self.tailLock.unlock()
        }

        do {
            try p.run()
        } catch {
            throw EngineError.startFailed(error.localizedDescription)
        }
        process = p

        // 等 RPC 就绪（最多 ~6 秒）
        for _ in 0..<40 {
            if rpc("aria2.getVersion") != nil { return }
            Thread.sleep(forTimeInterval: 0.15)
        }
        let detail = stderrTailText()
        stop()
        throw EngineError.startFailed(detail.isEmpty ? "RPC 端口无响应" : detail)
    }

    func stop() {
        process?.terminate()
        process = nil
        port = 0
        tailLock.lock(); stderrTail.removeAll(); tailLock.unlock()
    }

    private func stderrTailText() -> String {
        tailLock.lock(); defer { tailLock.unlock() }
        return stderrTail.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - JSON-RPC

    @discardableResult
    func rpc(_ method: String, _ params: [Any] = []) -> Any? {
        guard port != 0, !secret.isEmpty else { return nil }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "ldm",
            "method": method,
            "params": ["token:\(secret)"] + params
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: "http://127.0.0.1:\(port)/jsonrpc") else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let sem = DispatchSemaphore(value: 0)
        var result: Any?
        session.dataTask(with: req) { data, _, _ in
            if let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result = obj["result"]
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return result
    }

    // MARK: - 任务操作

    private let keys = ["gid", "status", "totalLength", "completedLength", "downloadSpeed",
                        "connections", "files", "errorMessage", "dir", "uri", "belongsTo", "followedBy"]

    func snapshot() -> (tasks: [AriaTask], globalSpeed: Int64) {
        var out: [AriaTask] = []
        if let arr = rpc("aria2.tellActive", [keys]) as? [[String: Any]] {
            out += arr.compactMap(parse)
        }
        if let arr = rpc("aria2.tellWaiting", [0, 500, keys]) as? [[String: Any]] {
            out += arr.compactMap(parse)
        }
        if let arr = rpc("aria2.tellStopped", [0, 1000, keys]) as? [[String: Any]] {
            out += arr.compactMap(parse)
        }
        var speed: Int64 = 0
        if let gs = rpc("aria2.getGlobalStat") as? [String: Any] {
            speed = Int64(gs["downloadSpeed"] as? String ?? "0") ?? 0
        }
        return (out, speed)
    }

    private func parse(_ d: [String: Any]) -> AriaTask? {
        guard let gid = d["gid"] as? String else { return nil }
        let files = d["files"] as? [[String: Any]]
        let first = files?.first
        let path = (first?["path"] as? String) ?? ""
        let uri = ((first?["uris"] as? [[String: Any]])?.first?["uri"] as? String) ?? (d["uri"] as? String) ?? ""
        return AriaTask(
            gid: gid,
            status: d["status"] as? String ?? "waiting",
            totalBytes: Int64(d["totalLength"] as? String ?? "0") ?? 0,
            doneBytes: Int64(d["completedLength"] as? String ?? "0") ?? 0,
            speed: Int64(d["downloadSpeed"] as? String ?? "0") ?? 0,
            connections: Int(d["connections"] as? String ?? "0") ?? 0,
            path: path,
            uri: uri,
            errorMessage: d["errorMessage"] as? String ?? ""
        )
    }

    @discardableResult
    func add(uri: String, dir: String, connections: Int) -> String? {
        let opts: [String: Any] = [
            "dir": dir,
            "split": "\(connections)",
            "max-connection-per-server": "\(connections)",
            "min-split-size": "1M"
        ]
        return rpc("aria2.addUri", [[uri], opts]) as? String
    }

    func pause(_ gid: String)  { _ = rpc("aria2.forcePause", [gid]) }
    func resume(_ gid: String) { _ = rpc("aria2.unpause", [gid]) }
    func remove(_ gid: String) {
        _ = rpc("aria2.forceRemove", [gid])
        _ = rpc("aria2.removeDownloadResult", [gid])
    }
    func pauseAll()  { _ = rpc("aria2.pauseAll") }
    func resumeAll() { _ = rpc("aria2.unpauseAll") }
    func purgeFinished() { _ = rpc("aria2.purgeDownloadResult") }
}
