import XCTest
@testable import Hilal

/// اختبارات مستقلة: القيم المرجعية مأخوذة من مصادر خارجية (لا من خوارزمية التطبيق)، والمصدر وتاريخ الاطلاع مذكوران عند كل قيمة.
/// المدينة المنورة: ٢٤٫٤٦٧٢ ش، ٣٩٫٦١١١ ق، توقيت Asia/Riyadh، طريقة أم القرى (الفجر ١٨٫٥°، العشاء بعد المغرب ٩٠ دقيقة و١٢٠ في رمضان).
final class ReferenceTests: XCTestCase {
    private let lat = 24.4672, lng = 39.6111
    private var saved: [String: Any?] = [:]
    private let keys = ["lat", "lng", "loc_mode", "place", "place_tz", "calc_method", "hijri_offset"]

    override func setUp() {
        super.setUp()
        for k in keys { saved[k] = AppGroup.defaults.object(forKey: k) }
        Settings.mode = "city"
        Settings.setCity(name: "المدينة المنورة", lat: lat, lng: lng, tz: "Asia/Riyadh")
        Settings.methodID = "uqu"
        Settings.hijriOffset = 0
    }

    override func tearDown() {
        // نعيد إعدادات الجهاز كما كانت (الاختبار لا يغيّر بيانات المستخدم)
        for k in keys {
            if let v = saved[k] ?? nil { AppGroup.defaults.set(v, forKey: k) } else { AppGroup.defaults.removeObject(forKey: k) }
        }
        super.tearDown()
    }

    private let riyadh = TimeZone(identifier: "Asia/Riyadh")!

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = riyadh
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// يقارن الأوقات الستة بمرجع (ساعة:دقيقة بتوقيت الرياض) بسماحية دقيقتين
    private func assertTimes(_ day: Date, _ ref: [(Int, Int)], file: StaticString = #filePath, line: UInt = #line) {
        let names = ["الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"]
        let got = Prayer.times(for: day, lat: lat, lng: lng, method: CalcMethods.get("uqu"))
        XCTAssertEqual(got.count, 6, file: file, line: line)
        var c = Calendar(identifier: .gregorian); c.timeZone = riyadh
        let base = c.startOfDay(for: day)
        for (i, r) in ref.enumerated() where i < got.count {
            let expected = base.addingTimeInterval(Double(r.0 * 3600 + r.1 * 60))
            let diff = abs(got[i].timeIntervalSince(expected)) / 60
            XCTAssertLessThanOrEqual(diff, 2, "\(names[i]): الفرق \(Int(diff.rounded())) دقيقة", file: file, line: line)
        }
    }

    // MARK: مواقيت الصلاة — المرجع: AlAdhan API، طريقة 4 (أم القرى)، اطّلع عليه ١٨ نوفمبر ٢٠٢٦
    // https://api.aladhan.com/v1/timings/15-07-2026?latitude=24.4672&longitude=39.6111&method=4&timezonestring=Asia/Riyadh

    func testPrayerTimesSummer() {
        assertTimes(date(2026, 7, 15), [(4, 13), (5, 42), (12, 28), (15, 50), (19, 13), (20, 43)])
    }

    // https://api.aladhan.com/v1/timings/21-12-2026?... (نفس المعاملات)
    func testPrayerTimesWinter() {
        assertTimes(date(2026, 12, 21), [(5, 37), (7, 1), (12, 20), (15, 18), (17, 38), (19, 8)])
    }

    // رمضان: العشاء بعد المغرب ١٢٠ دقيقة — https://api.aladhan.com/v1/timings/01-03-2026?... (١٢ رمضان ١٤٤٧)
    func testPrayerTimesRamadanIsha() {
        assertTimes(date(2026, 3, 1), [(5, 26), (6, 44), (12, 34), (15, 54), (18, 24), (20, 24)])
    }

    // MARK: التاريخ الهجري (أم القرى)

    /// المرجع الرسمي: صحيفة أم القرى — «1447-8-29 الموافق 17-02-2026» https://www.uqn.gov.sa/news/4000353 (اطّلع عليه ١٨ نوفمبر ٢٠٢٦)
    func testHijriOfficialUQN() {
        let h = Cal.dmy(date(2026, 2, 17), greg: false)
        XCTAssertEqual([h.d, h.m, h.y], [29, 8, 1447])
    }

    /// صحيفة أم القرى: «1 صفر 1448 | 15 يوليو 2026»، ويطابقها AlAdhan (01-02-1448)
    func testHijriFirstSafar1448() {
        let h = Cal.dmy(date(2026, 7, 15), greg: false)
        XCTAssertEqual([h.d, h.m, h.y], [1, 2, 1448])
    }

    /// AlAdhan: ١ مارس ٢٠٢٦ = ١٢ رمضان ١٤٤٧، و٢١ ديسمبر ٢٠٢٦ = ١٢ رجب ١٤٤٨
    func testHijriSecondarySource() {
        let a = Cal.dmy(date(2026, 3, 1), greg: false)
        XCTAssertEqual([a.d, a.m, a.y], [12, 9, 1447])
        let b = Cal.dmy(date(2026, 12, 21), greg: false)
        XCTAssertEqual([b.d, b.m, b.y], [12, 7, 1448])
    }

    /// تعديل المستخدم (+١ يوم) يُطبَّق على الهجري فقط، والميلادي لا يتغيّر
    func testHijriOffsetOnlyShiftsHijri() {
        Settings.hijriOffset = 1
        let h = Cal.dmy(date(2026, 2, 17), greg: false)
        // شعبان ١٤٤٧ تسعة وعشرون يومًا (المرجعان أعلاه: ٢٩ شعبان = ١٧ فبراير، و١٢ رمضان = ١ مارس) فاليوم التالي ١ رمضان
        XCTAssertEqual([h.d, h.m, h.y], [1, 9, 1447])
        let g = Cal.dmy(date(2026, 2, 17), greg: true)
        XCTAssertEqual([g.d, g.m, g.y], [17, 2, 2026])
    }

    // MARK: القبلة — المرجع: AlAdhan Qibla API ‏176.2359° https://api.aladhan.com/v1/qibla/24.4672/39.6111 (اطّلع عليه ١٨ نوفمبر ٢٠٢٦)

    func testQiblaMedina() {
        XCTAssertEqual(QiblaMath.bearing(lat: lat, lng: lng), 176.2359, accuracy: 0.3)
    }

    /// حالة حدّية: من مكة نفسها الاتجاه غير معرّف، ويجب ألا ينهار الحساب (لا NaN)
    func testQiblaAtKaabaIsFinite() {
        let b = QiblaMath.bearing(lat: 21.422487, lng: 39.826206)
        XCTAssertFalse(b.isNaN)
        XCTAssertLessThan(QiblaMath.distance(lat: 21.422487, lng: 39.826206), 0.01)
    }
}
