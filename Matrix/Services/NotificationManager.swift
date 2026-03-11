import Foundation
import UserNotifications

enum NotificationManager {
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func notifyDownloadCompleted(task: DownloadTask) async {
        let content = UNMutableNotificationContent()
        content.title = L10n.text("download_completed", language: .system)
        content.body = task.filename
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: task.id.uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
