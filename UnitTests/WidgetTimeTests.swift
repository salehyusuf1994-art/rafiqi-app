import XCTest
@testable import Hilal

/// تدقيق ٠٣: تبديل منتصف الليل ومواقيت الصلاة يوم تغيّر التوقيت الصيفي (لندن).
/// المرجع المستقل: قاعدة الاتحاد الأوروبي/بريطانيا — يبدأ الصيفي آخر أحد من مارس (٢٩ مارس ٢٠٢٦ الساعة ١:٠٠ UTC)
/// وينتهي آخر أحد من أكتوبر (٢٥ أكتوبر ٢٠٢٦ الساعة ١:٠٠ UTC)؛ ومواقيت AlAdhan (طريقة ٤) اطّلع عليها ١٨ نوفمبر ٢٠٢٦:
/// https://api.aladhan.com/v1/timings/28-03-2026?latitude=51.5074&longitude=-0.1278&method=4&timezonestring=Europe/London
/// https://api.aladhan.com/v1/timings/29-03-2026?latitude=51.5074&longitude=-0.1278&method=4&timezonestring=Europe/London
final class WidgetTimeTests: XCTestCase {
    private let london = TimeZone(identifier: "Europe/London")!
    private var oldTZ = NSTimeZone.default
    private var saved: [String: Any?] = [:]
    private let keys = ["lat", "lng", "loc_mode", "place", "place_tz", "calc_method", "wx"]

    override func setUp() {
        super.setUp()
        oldTZ = NSTimeZone.default
        for k in keys { saved[k] = AppGroup.defaults.object(forKey: k) }
        NSTimeZone.default = london
        Settings.mode = "city"
        Settings.setCity(name: "London", lat: 51.5074, lng: -0.1278, tz: "Europe/London")
        Settings.methodID = "uqu"
    }

    override func tearDown() {
        NSTimeZone.default = oldTZ
        for k in keys {
            if let v = saved[k] ?? nil { AppGroup.defaults.set(v, forKey: k) } else { AppGroup.defaults.removeObject(forKey: k) }
        }
        super.tearDown()
    }

    private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testMidnightBeforeSpringForward() {
        // ١٢ ظهرًا ٢٨ مارس (GMT) ← منتصف ليل ٢٩ مارس = 00:00Z
        XCTAssertEqual(Cal.nextMidnight(after: utc("2026-03-28T12:00:00Z")), utc("2026-03-29T00:00:00Z"))
    }

    func testMidnightOnShortDay() {
        // يوم ٢٩ مارس ٢٣ ساعة فقط: منتصف الليل التالي 00:00 BST = 23:00Z
        XCTAssertEqual(Cal.nextMidnight(after: utc("2026-03-29T11:00:00Z")), utc("2026-03-29T23:00:00Z"))
    }

    func testMidnightOnLongDay() {
        // يوم ٢٥ أكتوبر ٢٥ ساعة: منتصف الليل التالي 00:00 GMT = 00:00Z يوم ٢٦
        XCTAssertEqual(Cal.nextMidnight(after: utc("2026-10-25T12:00:00Z")), utc("2026-10-26T00:00:00Z"))
    }

    /// الأوقات بساعة الحائط في لندن (يوم/شهر/سنة + ساعة:دقيقة) — لا بإضافة ساعات إلى بداية اليوم،
    /// لأن يوم التغيير ٢٣ أو ٢٥ ساعة فالإضافة تكرر خطأ الخوارزمية بدل كشفه.
    /// المفاتيح: ١ الشروق، ٢ الظهر، ٣ العصر، ٤ المغرب، ٥ العشاء (الفجر مستثنى: قواعد العروض العالية تختلف بين الحاسبات)
    private func check(_ y: Int, _ m: Int, _ d: Int, _ ref: [Int: (Int, Int)], file: StaticString = #filePath, line: UInt = #line) {
        var c = Calendar(identifier: .gregorian); c.timeZone = london
        let day = c.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
        let t = Prayer.times(for: day, lat: 51.5074, lng: -0.1278, method: CalcMethods.get("uqu"))
        for (idx, r) in ref.sorted(by: { $0.key < $1.key }) {
            let exp = c.date(from: DateComponents(year: y, month: m, day: d, hour: r.0, minute: r.1))!
            let diff = abs(t[idx].timeIntervalSince(exp)) / 60
            XCTAssertLessThanOrEqual(diff, 2, "\(d)/\(m) الوقت \(idx): الفرق \(Int(diff.rounded())) دقيقة", file: file, line: line)
        }
    }

    func testPrayerTimesAcrossSpringForward() {
        check(2026, 3, 28, [1: (5, 45), 2: (12, 6), 3: (15, 33), 4: (18, 27), 5: (19, 57)])
        check(2026, 3, 29, [1: (6, 43), 2: (13, 5), 3: (16, 33), 4: (19, 29), 5: (20, 59)])
    }

    /// يوم الرجوع للتوقيت الشتوي (٢٥ ساعة) — AlAdhan طريقة ٤، اطّلع عليه ١٨ نوفمبر ٢٠٢٦:
    /// https://api.aladhan.com/v1/timings/25-10-2026?latitude=51.5074&longitude=-0.1278&method=4&timezonestring=Europe/London
    /// (العصر مستثنى: الفرق بين الحاسبات يقارب دقيقتين هنا)
    func testPrayerTimesOnFallBack() {
        check(2026, 10, 25, [1: (6, 42), 2: (11, 45), 4: (16, 47), 5: (18, 17)])
    }
}
