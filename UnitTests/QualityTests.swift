import XCTest
@testable import Hilal

/// اختبارات منع التراجع لتدقيق ٠٢ (التقويم المخزّن، الاسم غير المكرر، سلسلة المفاتيح المشتركة)
final class QualityTests: XCTestCase {

    /// التقويم المخزّن يتبع تغيّر المنطقة الزمنية للجوال ولا يبقى على القديمة
    func testCachedCalendarsFollowTimeZoneChange() {
        defer { Cal.testTimeZone = nil }
        // المنطقة تُحقن (TimeZone.current في الاختبار ثابت على منطقة جهاز البناء)
        Cal.testTimeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(Cal.gregCal.timeZone.identifier, "Asia/Tokyo")
        XCTAssertEqual(Cal.hijriCal.timeZone.identifier, "Asia/Tokyo")
        Cal.testTimeZone = TimeZone(identifier: "Asia/Riyadh")!
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
        // على المحاكي يجب أن تعمل سلسلة المفاتيح: الفشل خطأ حقيقي لا يُتجاوز
        #if targetEnvironment(simulator)
        XCTAssertFalse(got.isEmpty, "حفظ كلمة سر الخادم في سلسلة المفاتيح فشل")
        #else
        if got.isEmpty { throw XCTSkip("سلسلة المفاتيح غير متاحة في بيئة الاختبار هذه") }
        #endif
        XCTAssertEqual(got, "p@ss-\(id.uuidString.prefix(4))")
        Keychain.delete(id)
        XCTAssertEqual(Keychain.get(id), "")
    }

    /// خيار «ميلادي شامي» في الويدجت: يفرض الأسماء الشامية، و«ميلادي» يفرض العادية، و«هجري» يتبع إعداد التطبيق
    func testShamiCalendarOption() {
        XCTAssertEqual(CalOpt.gregorianShami.shami, true)
        XCTAssertEqual(CalOpt.gregorian.shami, false)
        XCTAssertNil(CalOpt.hijri.shami)
        XCTAssertTrue(CalOpt.gregorianShami.isGregorian && CalOpt.gregorian.isGregorian && !CalOpt.hijri.isGregorian)
        defer { Calli.shamiOverride = nil }
        Calli.shamiOverride = true
        XCTAssertEqual(Calli.resolve("gm3"), "gs3")
        XCTAssertEqual(Calli.resolve("hm3"), "hm3")
        XCTAssertNotNil(Calli.png("gm3"), "صورة آذار بالثلث موجودة")
        XCTAssertEqual(Words.text("gm1"), Words.gs[0])
        Calli.shamiOverride = false
        XCTAssertEqual(Calli.resolve("gm3"), "gm3")
        XCTAssertEqual(Words.text("gm1"), Words.gm[0])
    }

    /// ويدجت التاريخين (بلا تحويل للتقويم): «ميلادي شامي» يغيّر أسماء الأشهر الميلادية فيها، والتاريخ الأساسي يبقى كما هو
    func testShamiOnBothDatesWidget() {
        XCTAssertFalse(Catalog.info("hilal.daytwoy").hasCalendar)
        var i = RafiqiSmallIntent()
        i.design = DesignSmall(rawValue: "hilal.daytwoy") ?? i.design
        XCTAssertEqual(i.designID, "hilal.daytwoy")
        i.calendar = .gregorianShami
        XCTAssertEqual(i.shamiChoice, true)
        XCTAssertFalse(i.isGregorian)
        i.calendar = .gregorian
        XCTAssertEqual(i.shamiChoice, false)
        i.calendar = .hijri
        XCTAssertNil(i.shamiChoice)
    }
}
