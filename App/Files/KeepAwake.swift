import UIKit

/// يُبقي الشاشة مضاءة أثناء المهام الطويلة (فصل الصوت، التحويل، النقل عبر الواي فاي)،
/// ويطلب من النظام مهلة إضافية لإكمال المهمة إن خرج المستخدم من التطبيق مؤقتًا
@MainActor
enum KeepAwake {
    private static var count = 0

    static func begin() {
        count += 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func end() {
        count = max(0, count - 1)
        if count == 0 { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// مهمة خلفية قصيرة يمنحها النظام عند الخروج من التطبيق
    final class Background {
        private var id: UIBackgroundTaskIdentifier = .invalid
        init(_ name: String) {
            id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in self?.finish() }
        }
        func finish() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }
}
