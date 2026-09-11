import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var allowTermination = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// 有任务在下载时，退出前确认一次，避免误关窗口中断下载
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppDelegate.allowTermination { return .terminateNow }
        guard let dm = EngineHub.shared.manager else { return .terminateNow }
        let running = dm.tasks.filter { $0.status == .active || $0.status == .waiting }
        guard !running.isEmpty else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "还有 \(running.count) 个任务在下载"
        alert.informativeText = "退出会中断下载，重新添加同一链接可断点续传。"
        alert.addButton(withTitle: "退出并中断")
        alert.addButton(withTitle: "继续下载")
        if alert.runModal() == .alertFirstButtonReturn {
            AppDelegate.allowTermination = true
            return .terminateNow
        }
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        EngineHub.shared.manager?.shutdown()
    }
}

/// 让 AppDelegate 能拿到唯一的 DownloadManager 实例
final class EngineHub {
    static let shared = EngineHub()
    weak var manager: DownloadManager?
}

enum AppInfo {
    static let name = "LDM Mac"
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

@main
struct LdmMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dm = DownloadManager()

    init() {
        // 无界面自检模式：LdmMac --selftest <url> [--dir 路径] [--conn 16] [--video]
        if let idx = CommandLine.arguments.firstIndex(of: "--selftest") {
            let args = Array(CommandLine.arguments[(idx + 1)...])
            SelfTest.run(args: args)
            exit(SelfTest.exitCode)
        }
    }

    var body: some Scene {
        WindowGroup(AppInfo.name) {
            ContentView()
                .environmentObject(dm)
                .onAppear { EngineHub.shared.manager = dm }
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("打开下载目录") { dm.openDownloadDir() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}
