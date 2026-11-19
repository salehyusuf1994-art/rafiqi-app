import Foundation
import UIKit
import UserNotifications

// MARK: - صور الإشعارات: بطاقة صغيرة تظهر بجانب الإشعار (اسم الصلاة بخط الثلث)

enum NotifyArt {
    static let side: CGFloat = 300

    /// ألوان سماء كل وقت (مثل بطاقة الصلاة القادمة في التطبيق)
    private static func sky(_ key: String) -> [UIColor] {
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
        switch key {
        case "fajr", "midnight": return [c(0.05, 0.07, 0.20), c(0.15, 0.17, 0.42)]
        case "sunrise": return [c(0.13, 0.17, 0.40), c(0.72, 0.40, 0.46)]
        case "dhuhr", "jumuah": return [c(0.10, 0.40, 0.68), c(0.40, 0.72, 0.88)]
        case "asr": return [c(0.16, 0.46, 0.70), c(0.90, 0.68, 0.40)]
        case "maghrib": return [c(0.80, 0.42, 0.24), c(0.50, 0.22, 0.42)]
        default: return [c(0.24, 0.17, 0.44), c(0.07, 0.10, 0.24)]
        }
    }

    private static func card(_ colors: [UIColor], draw: (CGContext, CGRect) -> Void) -> Data? {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let r = CGRect(x: 0, y: 0, width: side, height: side)
        let img = UIGraphicsImageRenderer(size: r.size, format: fmt).image { ctx in
            let g = ctx.cgContext
            let cs = CGColorSpaceCreateDeviceRGB()
            if let grad = CGGradient(colorsSpace: cs, colors: colors.map { $0.cgColor } as CFArray, locations: [0, 1]) {
                g.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: side), options: [])
            }
            draw(g, r)
        }
        return img.pngData()
    }

    /// بطاقة الصلاة: اسمها بخط الثلث فوق سماء وقتها
    static func prayer(_ key: String) -> Data? {
        let name = Calli.png("pr_\(key)_t")
        return card(sky(key)) { _, r in
            guard let name else { return }
            let k = min(r.width * 0.8 / name.size.width, r.height * 0.5 / name.size.height)
            let w = name.size.width * k, h = name.size.height * k
            name.draw(in: CGRect(x: (r.width - w) / 2, y: (r.height - h) / 2, width: w, height: h))
        }
    }

    /// يحوّل الصورة لمرفق (كل إشعار يحتاج نسخة خاصة لأن النظام ينقل الملف)
    static func attachment(_ data: Data?, id: String) -> UNNotificationAttachment? {
        guard let data else { return nil }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("miqat_\(id)_\(UUID().uuidString).png")
        do {
            try data.write(to: u)
            return try UNNotificationAttachment(identifier: id, url: u, options: nil)
        } catch {
            return nil
        }
    }
}

// MARK: - أنواع الإشعارات وأزرارها

enum NotifyKinds {
    static let prayer = "MIQAT_PRAYER"
    static let pre = "MIQAT_PRE"
    static let snooze = "SNOOZE"

    static var categories: Set<UNNotificationCategory> {
        let snooze = UNNotificationAction(identifier: Self.snooze, title: LF("ذكّرني بعد %@ دقائق", ar(10)), options: [],
                                          icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath"))
        return [
            UNNotificationCategory(identifier: prayer, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: pre, actions: [snooze], intentIdentifiers: [], options: []),
        ]
    }
}
