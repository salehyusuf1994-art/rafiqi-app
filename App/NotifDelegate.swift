import UserNotifications
import Foundation

// MARK: - الإشعارات داخل التطبيق والضغط عليها

final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    static func registerCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(NotifyKinds.categories)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // «ذكّرني بعد ١٠ دقائق»: نفس الإشعار بعد عشر دقائق
        if response.actionIdentifier == NotifyKinds.snooze,
           let c = response.notification.request.content.mutableCopy() as? UNMutableNotificationContent {
            c.categoryIdentifier = NotifyKinds.prayer
            c.attachments = []
            // تأجيل التنبيه المسبق: بعد ١٠ دقائق يكون الوقت قد دخل، فلا يصح نص «اقترب…» ولا صوته
            // (المعرّف: miqat.pre.<الوقت>.<يونكس>)
            let parts = response.notification.request.identifier.split(separator: ".")
            if parts.count == 4, parts[1] == "pre", let t = Double(parts[3]) {
                c.title = Notify.title(String(parts[2]), pre: false)
                c.body = LF("الساعة %@", hm12(Date(timeIntervalSince1970: t))) + "."
                c.sound = .default
            }
            let req = UNNotificationRequest(identifier: "snooze." + UUID().uuidString, content: c,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false))
            center.add(req)
            completionHandler()
            return
        }
        // تذكير بملف: نفتحه في «إدارة الملفات»
        if let rel = response.notification.request.content.userInfo["file"] as? String {
            Task { @MainActor in
                let u = FileStore.shared.root.appendingPathComponent(rel)
                FilesRouter.shared.page = .files
                FilesRouter.shared.path = []
                FilesRouter.shared.openTab = true
                if FileManager.default.fileExists(atPath: u.path) {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    FileOpener.open(u)
                }
            }
        }
        completionHandler()
    }
}
