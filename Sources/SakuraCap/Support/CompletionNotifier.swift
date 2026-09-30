import AppKit
import UserNotifications

/// 录制完成通知 + 「在 Finder 中显示」动作。
final class CompletionNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CompletionNotifier()

    private static let categoryID = "SAKURACAP_SAVED"
    private let center = UNUserNotificationCenter.current()

    func setup() {
        center.delegate = self
        let reveal = UNNotificationAction(identifier: "REVEAL", title: L("在 Finder 中显示"), options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [reveal], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Log.app.info("通知授权: \(granted), error: \(error?.localizedDescription ?? "-")")
        }
    }

    func postSaved(url: URL, duration: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = L("录制完成")
        content.body = duration > 0.5
            ? "\(url.lastPathComponent)（\(Self.format(duration))）"
            : url.lastPathComponent
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["path": url.path]
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    static func format(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let path = response.notification.request.content.userInfo["path"] as? String {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
