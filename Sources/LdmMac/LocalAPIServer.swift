import Foundation
import Darwin

/// 供 Chrome 扩展调用的本机 HTTP API，只监听 127.0.0.1。
/// 端口固定为首选值，被占用时顺延两个；扩展默认连 47823。
final class LocalAPIServer {

    typealias Handler = (_ method: String, _ path: String, _ query: [String: String], _ body: Data, _ origin: String) -> (Int, [String: Any])

    static let preferredPort = 47823
    private(set) var port: Int = 0
    var handler: Handler?

    private var listenFD: Int32 = -1
    private let queue = DispatchQueue(label: "ldm.api", attributes: .concurrent)
    private let maxBody = 512 * 1024

    @discardableResult
    func start() -> Bool {
        stop()
        for p in [LocalAPIServer.preferredPort, LocalAPIServer.preferredPort + 1, LocalAPIServer.preferredPort + 2] {
            if bindAndListen(port: p) {
                port = p
                acceptLoop()
                return true
            }
        }
        return false
    }

    func stop() {
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        port = 0
    }

    // MARK: - socket

    private func bindAndListen(port p: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(p).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(fd, 32) == 0 else {
            close(fd)
            return false
        }
        listenFD = fd
        return true
    }

    private func acceptLoop() {
        queue.async { [weak self] in
            guard let self else { return }
            while true {
                let fd = self.listenFD
                if fd < 0 { break }
                var clientAddr = sockaddr_in()
                var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                let client = withUnsafeMutablePointer(to: &clientAddr) { ptr -> Int32 in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        accept(fd, sa, &len)
                    }
                }
                if client < 0 { break }
                self.queue.async { self.serve(clientFD: client) }
            }
        }
    }

    private func serve(clientFD: Int32) {
        defer { close(clientFD) }

        // 读超时 5 秒，防止连接卡死
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        var headerEnd: Range<Data.Index>?
        var contentLength = 0

        while buffer.count < maxBody {
            let n = recv(clientFD, &chunk, chunk.count, 0)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])

            if headerEnd == nil, let r = buffer.range(of: Data("\r\n\r\n".utf8)) {
                headerEnd = r
                let headerText = String(decoding: buffer[..<r.lowerBound], as: UTF8.self)
                for line in headerText.split(separator: "\r\n").dropFirst() {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2, parts[0].lowercased() == "content-length" {
                        contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                }
                if contentLength > maxBody { break }
            }
            if let r = headerEnd, buffer.count >= r.upperBound + contentLength { break }
        }

        guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else { return }
        let headerText = String(decoding: buffer[..<headerRange.lowerBound], as: UTF8.self)
        var lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return }
        lines.removeFirst()

        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else { return }
        let method = String(requestParts[0]).uppercased()
        let fullPath = String(requestParts[1])

        var headers: [String: String] = [:]
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }

        var path = fullPath
        var query: [String: String] = [:]
        if let qIndex = fullPath.firstIndex(of: "?") {
            path = String(fullPath[..<qIndex])
            let queryString = String(fullPath[fullPath.index(after: qIndex)...])
            for pair in queryString.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    let k = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                    let v = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                    query[k] = v
                }
            }
        }

        let bodyStart = headerRange.upperBound
        let body = contentLength > 0 && buffer.count >= bodyStart + contentLength
            ? Data(buffer[bodyStart..<(bodyStart + contentLength)])
            : Data()

        let origin = headers["origin"] ?? ""
        let (status, payload) = handler?(method, path, query, body, origin) ?? (500, ["ok": false, "error": "no handler"])

        var json = Data()
        if status != 204 {
            json = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data("{}".utf8)
        }

        var response = "HTTP/1.1 \(status) \(status == 200 ? "OK" : (status == 204 ? "No Content" : "Error"))\r\n"
        response += "Content-Type: application/json; charset=utf-8\r\n"
        response += "Access-Control-Allow-Origin: *\r\n"
        response += "Access-Control-Allow-Headers: Content-Type\r\n"
        response += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        response += "Cache-Control: no-store\r\n"
        response += "Content-Length: \(json.count)\r\n"
        response += "Connection: close\r\n\r\n"

        var out = Data(response.utf8)
        out.append(json)
        _ = out.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return send(clientFD, base, out.count, 0)
        }
    }
}
