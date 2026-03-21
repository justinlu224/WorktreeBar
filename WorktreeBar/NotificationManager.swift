import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let categoryID = "CLAUDE_FINISHED"
    private let openTerminalActionID = "OPEN_TERMINAL"

    private override init() {
        super.init()
    }

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Request permission
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("[WorktreeBar] Notification auth error: \(error.localizedDescription)")
            } else {
                print("[WorktreeBar] Notification auth granted: \(granted)")
            }
        }

        // Register action category
        let openAction = UNNotificationAction(
            identifier: openTerminalActionID,
            title: "Open Terminal",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [openAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    func notify(branch: String, path: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = ["path": path]

        let request = UNNotificationRequest(
            identifier: "claude-\(path.hashValue)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[WorktreeBar] Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notification even when app is in foreground (menu bar app is always "foreground")
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// Handle action button tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == openTerminalActionID {
            if let path = response.notification.request.content.userInfo["path"] as? String {
                openTerminal(at: path)
            }
        }
        completionHandler()
    }

    private func openTerminal(at path: String) {
        AppState.openTerminalTab(at: path)
    }
}
