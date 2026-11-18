import XCTest
@testable import Hilal

/// اختبارات منع التراجع لتدقيق ٠٢ (التقويم المخزّن، الاسم غير المكرر، سلسلة المفاتيح المشتركة)
final class QualityTests: XCTestCase {

    /// التقويم المخزّن يتبع تغيّر المنطقة الزمنية للجوال ولا يبقى على القديمة
    func testCachedCalendarsFollowTimeZoneChange() {
        let old = NSTimeZone.default
        defer { NSTimeZone.default = old }
        NSTimeZone.default = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(Cal.gregCal.timeZone.identifier, "Asia/Tokyo")
        XCTAssertEqual(Cal.hijriCal.timeZone.identifier, "Asia/Tokyo")
        NSTimeZone.default = TimeZone(identifier: "Asia/Riyadh")!
        XCTAssertEqual(Cal.gregCal.timeZone.identifier, "Asia/Riyadh")
        XCTAssertEqual(Cal.hijriCal.identifier, .islamicUmmAlQura)
    }

    /// نفس سلوك الدالتين السابقتين: «ملف.pdf» ثم «ملف (٢).pdf» ثم «ملف (٣).pdf»، وبدون امتداد «مجلد (٢)»
    func testUniqueFileName() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Uniq-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(uniqueFileURL("ملف.pdf", in: dir).lastPathComponent, "ملف.pdf")
        try Data().write(to: dir.appendingPathComponent("ملف.pdf"))
        XCTAssertEqual(uniqueFileURL("ملف.pdf", in: dir).lastPathComponent, "ملف (2).pdf")
        try Data().write(to: dir.appendingPathComponent("ملف (2).pdf"))
        XCTAssertEqual(uniqueFileURL("ملف.pdf", in: dir).lastPathComponent, "ملف (3).pdf")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("مجلد"), withIntermediateDirectories: true)
        XCTAssertEqual(uniqueFileURL("مجلد", in: dir).lastPathComponent, "مجلد (2)")
    }

    /// كلمات سر الخوادم: حفظ وقراءة وحذف عبر المخزن المشترك (نفس الواجهة القديمة)
    func testServerPasswordRoundTrip() throws {
        let id = UUID()
        Keychain.set("p@ss-\(id.uuidString.prefix(4))", for: id)
        let got = Keychain.get(id)
        if got.isEmpty { throw XCTSkip("سلسلة المفاتيح غير متاحة في بيئة الاختبار هذه") }
        XCTAssertEqual(got, "p@ss-\(id.uuidString.prefix(4))")
        Keychain.delete(id)
        XCTAssertEqual(Keychain.get(id), "")
    }
}
