import XCTest

/// فحص تشخيصي (لا يُشغَّل مع الاختبارات المعتادة): يفتح شاشات «إدارة الملفات» واحدة واحدة ويطبع وقت كل خطوة،
/// ليُطابَق مع سجل النظام ويُعرف أي شاشة تسبّب تحذير SwiftUI الداخلي (_UIReparentingView).
final class ProbeTests: XCTestCase {
    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func mark(_ s: String) { print("TVTEST probe \(fmt.string(from: Date())) \(s)") }

    /// يغلق ما فُتح: زر إغلاق/تم/إلغاء، أو الرجوع، أو السحب للأسفل
    private func close(_ app: XCUIApplication) {
        for t in ["تم", "إغلاق", "إلغاء", "Done", "Close", "Cancel"] {
            let b = app.buttons[t].firstMatch
            if b.exists && b.isHittable { b.tap(); return }
        }
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists && back.isHittable { back.tap(); return }
        app.swipeDown(velocity: .fast)
    }

    private func step(_ app: XCUIApplication, _ name: String, _ action: () -> Bool) {
        mark("begin \(name)")
        let ok = action()
        sleep(2)
        mark("opened \(name) ok=\(ok)")
        close(app)
        sleep(2)
        mark("closed \(name)")
    }

    private func tapButton(_ app: XCUIApplication, _ label: String) -> Bool {
        let b = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        guard b.waitForExistence(timeout: 4), b.isHittable else { return false }
        b.tap()
        return true
    }

    func testReparentProbe() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-shot", "files"]
        mark("launch")
        app.launch()
        sleep(4)
        mark("files tab ready")
        sleep(3)
        mark("idle 3s")

        step(app, "tools") { tapButton(app, "أدوات الملفات") }
        step(app, "browser") { tapButton(app, "المتصفح") }
        _ = tapButton(app, "ملفاتي"); sleep(1)
        step(app, "downloads") { tapButton(app, "التنزيلات") }
        _ = tapButton(app, "ملفاتي"); sleep(1)
        step(app, "filter-menu") { tapButton(app, "فلترة") }
        step(app, "sort-menu") { tapButton(app, "الترتيب") }
        step(app, "create-menu") { tapButton(app, "إنشاء") }
        step(app, "scanner") { tapButton(app, "الماسح") }
        step(app, "context-menu") {
            let f = app.buttons.containing(NSPredicate(format: "label CONTAINS 'نغمة'")).firstMatch
            guard f.waitForExistence(timeout: 4) else { return false }
            f.press(forDuration: 1.3)
            return true
        }
        step(app, "folder") { tapButton(app, "شعر") }
        step(app, "image-preview") { tapButton(app, "صورة") }
        step(app, "audio-file") { tapButton(app, "نغمة") }
        step(app, "playlists") { tapButton(app, "قوائم التشغيل") }
        step(app, "servers") { tapButton(app, "الخوادم") }
        step(app, "trash") { tapButton(app, "سلة المحذوفات") }
        step(app, "select") { tapButton(app, "تحديد") }
        mark("end")
    }
}
