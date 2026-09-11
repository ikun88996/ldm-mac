import Foundation

// MARK: - 任务类型

enum TaskKind: String {
    case file    // aria2 多线程文件下载
    case video   // yt-dlp 视频解析
}

enum TaskStatus: String {
    case waiting, active, paused, complete, error

    var label: String {
        switch self {
        case .waiting:  return L("status.waiting")
        case .active:   return L("status.active")
        case .paused:   return L("status.paused")
        case .complete: return L("status.complete")
        case .error:    return L("status.error")
        }
    }
}

// MARK: - 界面用任务模型

struct DownloadTask: Identifiable, Equatable {
    var id: String
    var name: String
    var kind: TaskKind
    var status: TaskStatus
    var totalBytes: Int64
    var doneBytes: Int64
    var speed: Int64          // 字节/秒
    var connections: Int
    var etaText: String
    var path: String
    var uri: String
    var message: String

    var progress: Double {
        if status == .complete { return 1 }
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(doneBytes) / Double(totalBytes))
    }

    var isFinished: Bool { status == .complete || status == .error }
    var canPause: Bool { status == .active || status == .waiting }
    var canResume: Bool { status == .paused }

    /// 给浏览器扩展的 JSON 表示
    var json: [String: Any] {
        [
            "id": id,
            "name": name,
            "kind": kind.rawValue,
            "status": status.rawValue,
            "progress": progress,
            "done": doneBytes,
            "total": totalBytes,
            "speed": speed,
            "connections": connections,
            "path": path,
            "url": uri
        ]
    }
}

// MARK: - 下载模式 / 视频画质

enum DownloadMode: String, CaseIterable, Identifiable {
    case auto, file, video
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto:  return L("mode.auto")
        case .file:  return L("mode.file")
        case .video: return L("mode.video")
        }
    }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case best, p1080, audioOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .best:      return L("quality.best")
        case .p1080:     return L("quality.1080")
        case .audioOnly: return L("quality.audio")
        }
    }
}

// MARK: - 格式化工具

enum Fmt {
    static func bytes(_ n: Int64) -> String {
        if n <= 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(n)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return String(format: i == 0 ? "%.0f %@" : "%.2f %@", v, units[i])
    }

    static func speed(_ n: Int64) -> String {
        guard n > 0 else { return "0 B/s" }
        return bytes(n) + "/s"
    }

    static func eta(_ seconds: Int) -> String {
        guard seconds > 0, seconds < 60 * 60 * 48 else { return "--:--" }
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
