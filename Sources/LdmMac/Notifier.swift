import Foundation
import UserNotifications

/// 下载完成后的系统通知（通知中心）。
///
/// 注意：`UNUserNotificationCenter` 在「不是 .app 包」的进程里调用会直接抛异常，
/// 所以这里做了 bundle 判断——命令行自检（直接跑可执行文件）永远不会触发通知。
final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    static let shared = Notifier()

    private var usable = false
    private var denied = false

    /// 首次使用时申请权限（在 App 里启动时调用一次）
    func setupIfNeeded() {
        guard !usable else { return }
        guard Bundle.main.bundlePath.hasSuffix(".app"), Bundle.main.bundleIdentifier != nil else { return }

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        usable = true
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.denied = !granted
        }
    }

    /// 发一条完成通知（未授权时系统会自动丢弃，不会报错）
    func notify(title: String, body: String) {
        setupIfNeeded()
        guard usable, !denied else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // App 在前台时也把横幅弹出来
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
