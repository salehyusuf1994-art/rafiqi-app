import SwiftUI
import WidgetKit
import AppIntents

// MARK: - ورد القرآن: الجزء الحالي وعدد الختمات

enum Wird {
    private static var d: UserDefaults { AppGroup.defaults }

    /// الجزء الذي تقرؤه الآن (١…٣٠)
    static var juz: Int {
        get { let v = d.integer(forKey: "wird_juz"); return v < 1 ? 1 : min(30, v) }
        set { d.set(max(1, min(30, newValue)), forKey: "wird_juz") }
    }
    /// الختمات المكتملة
    static var khatmas: Int {
        get { max(0, d.integer(forKey: "wird_khatma")) }
        set { d.set(max(0, newValue), forKey: "wird_khatma") }
    }
    static var lastChange: Date {
        get { Date(timeIntervalSince1970: d.double(forKey: "wird_at")) }
        set { d.set(newValue.timeIntervalSince1970, forKey: "wird_at") }
    }

    /// تقدّم الختمة ٠…١ (الأجزاء المكتملة)
    static var progress: Double { Double(juz - 1) / 30 }

    static func step(_ delta: Int) {
        var j = juz + delta, k = khatmas
        if j > 30 { j = 1; k += 1 }
        if j < 1 {
            if k > 0 { k -= 1; j = 30 } else { j = 1 }
        }
        juz = j; khatmas = k; lastChange = Date()
    }

    static func reset() { juz = 1; khatmas = 0; lastChange = Date() }
}

/// زر داخل الويدجت: التالي أو السابق
struct WirdStepIntent: AppIntent {
    static let title: LocalizedStringResource = "تقدّم الورد"
    static let isDiscoverable = false
    @Parameter(title: "الخطوة") var delta: Int
    init() {}
    init(delta: Int) { self.delta = delta }
    func perform() async throws -> some IntentResult {
        Wird.step(delta)
        return .result()
    }
}

// MARK: - آيات قصيرة (تتبدّل يوميًا)

enum Verses {
    static let list: [(String, String)] = [
        ("إن الصلاة كانت على المؤمنين كتابا موقوتا", "النساء ١٠٣"),
        ("حافظوا على الصلوات والصلاة الوسطى", "البقرة ٢٣٨"),
        ("وأقم الصلاة لذكري", "طه ١٤"),
        ("ألا بذكر الله تطمئن القلوب", "الرعد ٢٨"),
        ("فاذكروني أذكركم واشكروا لي ولا تكفرون", "البقرة ١٥٢"),
        ("فإن مع العسر يسرا", "الشرح ٥"),
        ("واستعينوا بالصبر والصلاة", "البقرة ٤٥"),
        ("وقل رب زدني علما", "طه ١١٤"),
        ("إن الله مع الصابرين", "البقرة ١٥٣"),
        ("ورحمتي وسعت كل شيء", "الأعراف ١٥٦"),
        ("إن الحسنات يذهبن السيئات", "هود ١١٤"),
        ("وما توفيقي إلا بالله", "هود ٨٨"),
        ("ومن يتوكل على الله فهو حسبه", "الطلاق ٣"),
        ("إن ربي قريب مجيب", "هود ٦١"),
    ]

    static func of(_ date: Date) -> (String, String) {
        let day = Cal.gregCal.ordinality(of: .day, in: .era, for: date) ?? 0
        return list[day % list.count]
    }
}
