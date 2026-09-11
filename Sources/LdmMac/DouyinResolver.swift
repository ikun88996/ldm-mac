import Foundation

/// 抖音去水印解析
///
/// 为什么不走 yt-dlp：它的抖音解析器要调 `douyin.com/aweme/v1/web/aweme/detail/`，
/// 没有 cookie 时接口返回空，直接报 `Fresh cookies (not necessarily logged in) are needed`。
///
/// 这里的做法：自建一份**合法** cookie（ttwid 从官方注册端点取，其余是客户端生成的指纹字段），
/// 调同一个官方接口拿 `aweme_detail`，再用 `video.play_addr.uri` 拼出**无水印**播放地址
/// （`/aweme/v1/play/?video_id=<uri>&ratio=1080p`），最后交给 aria2 多线程下载 —— 不用登录、也不用浏览器 cookie。
enum DouyinResolver {

    struct Item {
        var id: String
        var title: String
        var author: String
        var playURL: String          // 无水印播放地址（图集时为空）
        var images: [String] = []    // 图集图片（视频时为空）
        var durationMs: Int = 0
        var cookieHeader: String = ""
        var referer: String = "https://www.douyin.com/"
    }

    // MARK: - 链接识别

    /// 从粘贴内容里抠出抖音链接。
    /// 支持抖音 App 的「分享文本」（一长串中文夹着 `v.douyin.com/xxx`，可能不带 http），
    /// 也支持直接粘完整链接。
    static func extractLink(from text: String) -> String? {
        let patterns = [
            #"https?://[A-Za-z0-9.\-]*douyin\.com/[^\s，。；、！？）)】」"'']*"#,
            #"(?:v|www|m|iesdouyin)\.(?:douyin|iesdouyin)\.com/[^\s，。；、！？）)】」"'']*"#,
            #"(?:v|www|m)\.douyin\.com/[A-Za-z0-9_\-]+"#
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r = Range(m.range, in: text) else { continue }
            var s = String(text[r])
            // 去掉尾部可能粘连的标点
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: "，。、；：！？）)】」】.!?,;:\"'"))
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { continue }
            if !s.lowercased().hasPrefix("http") { s = "https://" + s }
            return s
        }
        return nil
    }

    static func isDouyin(_ url: String) -> Bool {
        let candidate = url.lowercased().hasPrefix("http") ? url : "https://" + url
        guard let host = URL(string: candidate)?.host?.lowercased() else { return false }
        return host.hasSuffix("douyin.com") || host.hasSuffix("iesdouyin.com")
    }

    /// 抖音返回的标题常带话题/at/表情，做成安全文件名
    static func fileName(_ s: String) -> String {
        var out = s
        for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\n", "\r", "\t"] {
            out = out.replacingOccurrences(of: ch, with: " ")
        }
        out = out.replacingOccurrences(of: "#", with: " ")
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        if out.count > 80 { out = String(out.prefix(80)) }
        return out.isEmpty ? "douyin" : out
    }

    // MARK: - 解析

    static func resolve(_ link: String, proxy: String? = nil) -> Item? {
        let session = makeSession(proxy: proxy)

        // 1) 跟随短链跳转，拿到真实地址里的 aweme_id
        guard let (finalURL, _) = fetch(session, link), let id = awemeID(from: finalURL.absoluteString) else { return nil }

        // 2) 准备 cookie（ttwid 取不到就用空的，接口有时也放行）
        ensureCookies(session)
        let cookieHeader = lastCookieHeader

        // 3) 调官方详情接口
        guard let json = fetchDetail(session, id: id, cookieHeader: cookieHeader),
              let detail = json["aweme_detail"] as? [String: Any] else { return nil }
        if (detail["status_code"] as? Int).map({ $0 != 0 }) == true { return nil }

        // 4) 解析字段
        let title = (detail["desc"] as? String) ?? "douyin_\(id)"
        let author = ((detail["author"] as? [String: Any])?["nickname"] as? String) ?? ""
        let video = detail["video"] as? [String: Any] ?? [:]
        let duration = (video["duration"] as? Int) ?? 0

        // 图集（新版字段 image_post_info，老版 images）
        var images: [String] = []
        if let arr = detail["images"] as? [[String: Any]] {
            images = arr.compactMap { ($0["url_list"] as? [String])?.first }
        } else if let post = (detail["image_post_info"] as? [String: Any])?["images"] as? [[String: Any]] {
            images = post.compactMap { item in
                let display = item["display_image"] as? [String: Any]
                return (display?["url_list"] as? [String])?.first ?? (item["url_list"] as? [String])?.first
            }
        }

        // 无水印地址：用 video_id 走 play 接口（download_addr 才带水印）
        var playURL = ""
        if let uri = (video["play_addr"] as? [String: Any])?["uri"] as? String, !uri.isEmpty {
            playURL = "https://www.douyin.com/aweme/v1/play/?video_id=\(uri)&ratio=1080p&line=0&is_play_url=1&source=PackSourceEnum_AWEME_DETAIL"
        } else if let first = ((video["play_addr"] as? [String: Any])?["url_list"] as? [String])?.first {
            playURL = first
        }
        guard !playURL.isEmpty || !images.isEmpty else { return nil }

        return Item(id: id, title: title, author: author, playURL: playURL,
                    images: images, durationMs: duration, cookieHeader: cookieHeader)
    }

    private static func awemeID(from url: String) -> String? {
        let patterns = [#"/(?:video|note)/(\d+)"#, #"/share/(?:video|note)/(\d+)"#, #"modal_id=(\d+)"#, #"aweme_id=(\d+)"#]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p),
               let m = re.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
               let r = Range(m.range(at: 1), in: url) { return String(url[r]) }
        }
        return nil
    }

    // MARK: - 网络

    private static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private static func makeSession(proxy: String?) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        // cookie 一律由我们显式写进 Cookie 头：URLSession 自己管 cookie 时会覆盖手动头，
        // 结果把 ttwid 丢掉（bytedance 域的 cookie 不会带到 douyin.com 的请求上）
        cfg.httpShouldSetCookies = false
        cfg.httpCookieStorage = HTTPCookieStorage()   // 私有罐，不碰系统/浏览器 cookie
        if let proxy, !proxy.isEmpty { cfg.connectionProxyDictionary = [:] }
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        cfg.httpAdditionalHeaders = ["User-Agent": ua,
                                     "Accept-Language": "zh-CN,zh;q=0.9"]
        return URLSession(configuration: cfg)
    }

    private static func fetch(_ session: URLSession, _ urlString: String) -> (URL, Data)? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let sem = DispatchSemaphore(value: 0)
        var result: (URL, Data)?
        session.dataTask(with: req) { data, resp, _ in
            if let data, let final = resp?.url { result = (final, data) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 20)
        return result
    }

    /// 「新鲜 cookie」= ttwid（官方注册端点取的）+ 客户端指纹字段，全部塞进 Cookie 头
    private static func ensureCookies(_ session: URLSession) -> [HTTPCookie] {
        var pairs: [String] = []
        if let ttwid = fetchTTWID(session) { pairs.append("ttwid=\(ttwid)") }
        pairs.append("s_v_web_id=verify_l\(hex(3))_\(hex(4))_\(hex(2))_\(hex(2))")
        pairs.append("msToken=\(randomToken(107))")
        pairs.append("odin_tt=\(hex(80))")
        pairs.append("__ac_nonce=\(hex(11))")
        lastCookieHeader = pairs.joined(separator: "; ")
        return []
    }

    /// 注册端点拿 ttwid（Set-Cookie 里）
    private static func fetchTTWID(_ session: URLSession) -> String? {
        guard let url = URL(string: "https://ttwid.bytedance.com/ttwid/union/register/") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = ["region": "cn", "aid": 1768, "needFid": false,
                                   "service": "www.douyin.com",
                                   "migrate_info": ["ticket": "", "source": "node"],
                                   "cbUrlProtocol": "https", "union": true]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        var value: String?
        let sem = DispatchSemaphore(value: 0)
        session.dataTask(with: req) { _, resp, _ in
            if let http = resp as? HTTPURLResponse {
                let raw = (http.allHeaderFields["Set-Cookie"] as? String) ?? ""
                if let r = raw.range(of: "ttwid=") {
                    let tail = raw[r.upperBound...]
                    let end = tail.firstIndex(of: ";") ?? tail.endIndex
                    value = String(tail[..<end])
                }
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 15)
        return value
    }

    /// 最近一次用过的 Cookie 头（给 aria2 下载直链时复用）
    private(set) static var lastCookieHeader: String = ""

    private static func fetchDetail(_ session: URLSession, id: String, cookieHeader: String) -> [String: Any]? {
        var comps = URLComponents(string: "https://www.douyin.com/aweme/v1/web/aweme/detail/")!
        comps.queryItems = [
            URLQueryItem(name: "aweme_id", value: id),
            URLQueryItem(name: "device_platform", value: "webapp"),
            URLQueryItem(name: "aid", value: "6383"),
            URLQueryItem(name: "channel", value: "channel_pc_web"),
            URLQueryItem(name: "pc_client_type", value: "1"),
            URLQueryItem(name: "version_code", value: "170400"),
            URLQueryItem(name: "version_name", value: "17.4.0"),
            URLQueryItem(name: "cookie_enabled", value: "true"),
            URLQueryItem(name: "platform", value: "PC"),
            URLQueryItem(name: "browser_name", value: "Chrome"),
            URLQueryItem(name: "browser_version", value: "120.0.0.0"),
            URLQueryItem(name: "os_name", value: "Mac OS"),
            URLQueryItem(name: "os_version", value: "10.15.7"),
            URLQueryItem(name: "screen_width", value: "1920"),
            URLQueryItem(name: "screen_height", value: "1080"),
            URLQueryItem(name: "browser_language", value: "zh-CN"),
            URLQueryItem(name: "browser_platform", value: "MacIntel"),
            URLQueryItem(name: "engine_name", value: "Blink")
        ]
        guard let url = comps.url else { return nil }
        guard let (_, data) = fetchWithCookie(session, url, cookieHeader: cookieHeader) else { return nil }
        lastResponsePreview = String(data: data.prefix(200), encoding: .utf8) ?? ""
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// 最近一次详情接口返回的开头（解析失败时用来定位原因）
    private(set) static var lastResponsePreview: String = ""

    private static func fetchWithCookie(_ session: URLSession, _ url: URL, cookieHeader: String) -> (URL, Data)? {
        var req = URLRequest(url: url)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")
        req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        let sem = DispatchSemaphore(value: 0)
        var result: (URL, Data)?
        session.dataTask(with: req) { data, resp, _ in
            if let data, let final = resp?.url { result = (final, data) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 20)
        return result
    }

    private static func hex(_ bytes: Int) -> String {
        var s = ""
        for _ in 0..<bytes { s += String(format: "%02x", Int.random(in: 0...255)) }
        return s
    }

    private static func randomToken(_ length: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }
}
