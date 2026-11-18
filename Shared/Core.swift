import Foundation
import UIKit
import SwiftUI

// MARK: - App Group (يدعم إعادة التسمية اللي يسويها AltStore/AltServer)

enum AppGroup {
    static let configured = "group.app.hilal.widgets"

    static let identifier: String = {
        let fm = FileManager.default
        if fm.containerURL(forSecurityApplicationGroupIdentifier: configured) != nil { return configured }
        let groups = (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]) ?? []
        for g in groups where g == configured || (g.hasPrefix(configured + ".") && g.count > configured.count + 1) {
            if fm.containerURL(forSecurityApplicationGroupIdentifier: g) != nil { return g }
        }
        // أي مجموعة أعطاها AltStore (احتياط)
        for g in groups where fm.containerURL(forSecurityApplicationGroupIdentifier: g) != nil { return g }
        return configured
    }()

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

// MARK: - الإعدادات المشتركة

enum Settings {
    static let medinaLat = 24.4672
    static let medinaLng = 39.6111

    static var lat: Double {
        get { AppGroup.defaults.object(forKey: "lat") as? Double ?? medinaLat }
        set { AppGroup.defaults.set(newValue, forKey: "lat") }
    }
    static var lng: Double {
        get { AppGroup.defaults.object(forKey: "lng") as? Double ?? medinaLng }
        set { AppGroup.defaults.set(newValue, forKey: "lng") }
    }
    static var isMedina: Bool {
        abs(lat - medinaLat) < 0.15 && abs(lng - medinaLng) < 0.15
    }
    /// auto = حسب موقعي — city = مدينة أختارها
    static var mode: String {
        get { AppGroup.defaults.string(forKey: "loc_mode") ?? "city" }
        set { AppGroup.defaults.set(newValue, forKey: "loc_mode") }
    }
    static var isAuto: Bool { mode == "auto" }
    static var placeName: String {
        get { AppGroup.defaults.string(forKey: "place") ?? (isMedina ? "المدينة المنورة" : "") }
        set { AppGroup.defaults.set(newValue, forKey: "place") }
    }
    static var lastFix: Date {
        get { Date(timeIntervalSince1970: AppGroup.defaults.double(forKey: "last_fix")) }
        set { AppGroup.defaults.set(newValue.timeIntervalSince1970, forKey: "last_fix") }
    }
    /// المنطقة الزمنية للمدينة المختارة يدويًا (مدن المملكة: الرياض)
    static var placeTZ: String {
        get { AppGroup.defaults.string(forKey: "place_tz") ?? "Asia/Riyadh" }
        set { AppGroup.defaults.set(newValue, forKey: "place_tz") }
    }
    /// منطقة حساب أوقات الصلاة: التلقائي يتبع الجوال، واليدوي يتبع المدينة المختارة
    static var timeZone: TimeZone { isAuto ? .current : (TimeZone(identifier: placeTZ) ?? .current) }

    static func setCity(name: String, lat: Double, lng: Double, tz: String = "Asia/Riyadh") {
        self.lat = lat; self.lng = lng; placeName = name; placeTZ = tz
        AppGroup.defaults.removeObject(forKey: "wx")
    }

    /// طريقة حساب أوقات الصلاة (الافتراضي أم القرى)
    static var methodID: String {
        get { AppGroup.defaults.string(forKey: "calc_method") ?? "uqu" }
        set { AppGroup.defaults.set(newValue, forKey: "calc_method") }
    }
    static var method: CalcMethod { CalcMethods.get(methodID) }
}

// MARK: - طرق حساب أوقات الصلاة
// زاوية الفجر، والعشاء بزاوية أو بدقائق بعد المغرب. العصر على المذهب الجمهوري (ظل الشيء مثله).

struct CalcMethod: Identifiable, Hashable {
    let id: String
    let arName: String
    let enName: String
    let fajr: Double
    /// زاوية العشاء
    var isha: Double? = nil
    /// أو: دقائق بعد المغرب
    var ishaMinutes: Double? = nil
    /// دقائق العشاء بعد المغرب في رمضان (أم القرى)
    var ramadanMinutes: Double? = nil

    var name: String { Lang.isEN ? enName : arName }
    /// اسم مختصر (لعناوين البطاقات)
    var short: String {
        switch id {
        case "uqu": return L("أم القرى")
        case "mwl": return Lang.isEN ? "MWL" : "رابطة العالم الإسلامي"
        case "egypt": return Lang.isEN ? "Egypt" : "الهيئة المصرية"
        case "karachi": return Lang.isEN ? "Karachi" : "كراتشي"
        case "isna": return "ISNA"
        default: return name
        }
    }

    private func deg(_ v: Double) -> String {
        let s = v == v.rounded() ? String(Int(v)) : String(v)
        return ar(s.replacingOccurrences(of: ".", with: Lang.isEN || Settings.westernDigits ? "." : "٫")) + "°"
    }
    /// «الفجر ١٨٫٥° · العشاء ٩٠ دقيقة بعد المغرب»
    var detail: String {
        let f = LF("الفجر %@", deg(fajr))
        if let a = isha { return f + " · " + LF("العشاء %@", deg(a)) }
        var t = f + " · " + LF("العشاء %@ دقيقة بعد المغرب", ar(Int(ishaMinutes ?? 90)))
        if let r = ramadanMinutes { t += " " + LF("(%@ في رمضان)", ar(Int(r))) }
        return t
    }
}

enum CalcMethods {
    static let all: [CalcMethod] = [
        CalcMethod(id: "uqu", arName: "أم القرى — مكة المكرمة", enName: "Umm al-Qura, Makkah", fajr: 18.5, ishaMinutes: 90, ramadanMinutes: 120),
        CalcMethod(id: "mwl", arName: "رابطة العالم الإسلامي", enName: "Muslim World League", fajr: 18, isha: 17),
        CalcMethod(id: "egypt", arName: "الهيئة المصرية العامة للمساحة", enName: "Egyptian General Authority of Survey", fajr: 19.5, isha: 17.5),
        CalcMethod(id: "karachi", arName: "جامعة العلوم الإسلامية — كراتشي", enName: "University of Islamic Sciences, Karachi", fajr: 18, isha: 18),
        CalcMethod(id: "kuwait", arName: "الكويت", enName: "Kuwait", fajr: 18, isha: 17.5),
        CalcMethod(id: "qatar", arName: "قطر", enName: "Qatar", fajr: 18, ishaMinutes: 90),
        CalcMethod(id: "isna", arName: "الجمعية الإسلامية لأمريكا الشمالية (ISNA)", enName: "Islamic Society of North America (ISNA)", fajr: 15, isha: 15),
    ]
    static func get(_ id: String) -> CalcMethod { all.first { $0.id == id } ?? all[0] }
}

// MARK: - الأرقام والتواريخ

let arDigits: [Character] = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
func ar(_ s: String) -> String {
    if Settings.westernDigits || Lang.isEN { return s }
    return String(s.map { c -> Character in
        if let v = c.wholeNumberValue, c.isASCII { return arDigits[v] }
        return c
    })
}
func ar(_ n: Int) -> String { ar(String(n)) }

/// العدد مع المعدود بقواعد العربية: «دقيقة واحدة، دقيقتان، ٥ دقائق، ١٥ دقيقة»
func countText(_ n: Int, one: String, two: String, few: String, many: String, en: String) -> String {
    if Lang.isEN { return "\(n) \(en)" }
    switch n {
    case 1: return one
    case 2: return two
    case 3...10: return ar(n) + " " + few
    default: return ar(n) + " " + many
    }
}
func minutesText(_ n: Int) -> String {
    countText(n, one: "دقيقة واحدة", two: "دقيقتان", few: "دقائق", many: "دقيقة", en: n == 1 ? "minute" : "minutes")
}
func channelsText(_ n: Int) -> String {
    countText(n, one: "قناة واحدة", two: "قناتان", few: "قنوات", many: "قناة", en: n == 1 ? "channel" : "channels")
}
func stationsText(_ n: Int) -> String {
    countText(n, one: "إذاعة واحدة", two: "إذاعتان", few: "إذاعات", many: "إذاعة", en: n == 1 ? "station" : "stations")
}
/// «١:٠٥:٠٩» — العدّاد بالساعات دائمًا (حتى «٠:١٤:١٠» تحت الساعة)
func hmsText(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded(.up)))
    func two(_ n: Int) -> String { (n < 10 ? ar("0") : "") + ar(n) }
    return ar(s / 3600) + ":" + two((s % 3600) / 60) + ":" + two(s % 60)
}

func pagesText(_ n: Int) -> String {
    countText(n, one: "صفحة واحدة", two: "صفحتان", few: "صفحات", many: "صفحة", en: n == 1 ? "page" : "pages")
}

struct DMY { let d: Int; let m: Int; let y: Int }

enum Cal {
    /// التقويمان مخزّنان ويُعادان بنسخة (قيمة)؛ يُبنيان من جديد فقط إذا تغيّرت المنطقة الزمنية للجوال
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: (tz: TimeZone, hijri: Calendar, greg: Calendar)?
    private static func cals() -> (hijri: Calendar, greg: Calendar) {
        let tz = TimeZone.current
        lock.lock(); defer { lock.unlock() }
        if let c = cached, c.tz == tz { return (c.hijri, c.greg) }
        var h = Calendar(identifier: .islamicUmmAlQura); h.timeZone = tz
        var g = Calendar(identifier: .gregorian); g.timeZone = tz
        cached = (tz, h, g)
        return (h, g)
    }
    static var hijriCal: Calendar { cals().hijri }
    static var gregCal: Calendar { cals().greg }
    static func cal(_ greg: Bool) -> Calendar { greg ? gregCal : hijriCal }

    /// الهجري مع تعديل المستخدم (±يومين)
    static func shifted(_ date: Date, greg: Bool) -> Date {
        greg ? date : date.addingTimeInterval(Double(Settings.hijriOffset) * 86400)
    }

    static func dmy(_ date: Date, greg: Bool) -> DMY {
        let c = cal(greg).dateComponents([.day, .month, .year], from: shifted(date, greg: greg))
        return DMY(d: c.day ?? 1, m: c.month ?? 1, y: c.year ?? 1448)
    }
    static func hijri(_ date: Date) -> DMY { dmy(date, greg: false) }

    /// أول يوم في الشهر، طوله، طول الشهر السابق، ورقم اليوم
    static func monthInfo(_ date: Date, greg: Bool) -> (first: Date, len: Int, prevLen: Int, day: Int) {
        let c = cal(greg)
        let sd = shifted(date, greg: greg)
        let first = c.dateInterval(of: .month, for: sd)?.start ?? sd
        let len = c.range(of: .day, in: .month, for: sd)?.count ?? 30
        let prev = c.date(byAdding: .day, value: -1, to: first) ?? first
        let prevLen = c.range(of: .day, in: .month, for: prev)?.count ?? 30
        // أول الشهر بالتاريخ الفعلي (عشان يوم الأسبوع يطلع صح مع التعديل)
        let realFirst = greg ? first : first.addingTimeInterval(-Double(Settings.hijriOffset) * 86400)
        return (realFirst, len, prevLen, dmy(date, greg: greg).d)
    }

    static func yearInfo(_ date: Date, greg: Bool) -> (len: Int, day: Int) {
        let c = cal(greg)
        let sd = shifted(date, greg: greg)
        let len = c.range(of: .day, in: .year, for: sd)?.count ?? (greg ? 365 : 354)
        let day = c.ordinality(of: .day, in: .year, for: sd) ?? 1
        return (len, day)
    }

    /// الأيام الباقية على رمضان، أو رقم اليوم في رمضان
    static func ramadan(_ date: Date) -> (inRamadan: Bool, day: Int, len: Int, daysLeft: Int) {
        let h = dmy(date, greg: false)
        if h.m == 9 {
            return (true, h.d, monthInfo(date, greg: false).len, 0)
        }
        let c = hijriCal
        let y = h.m < 9 ? h.y : h.y + 1
        guard let start = c.date(from: DateComponents(year: y, month: 9, day: 1)) else { return (false, 0, 30, 0) }
        let real = start.addingTimeInterval(-Double(Settings.hijriOffset) * 86400)
        let g = gregCal
        let days = g.dateComponents([.day], from: g.startOfDay(for: date), to: g.startOfDay(for: real)).day ?? 0
        return (false, 0, 30, max(0, days))
    }

    static func weekday(_ date: Date) -> Int { gregCal.component(.weekday, from: date) - 1 } // الأحد = 0

    static func nextMidnight(after date: Date) -> Date {
        let c = gregCal
        return c.date(byAdding: .day, value: 1, to: c.startOfDay(for: date)) ?? date.addingTimeInterval(86400)
    }
}

/// الوقت ساعة:دقيقة — ١٢ ساعة افتراضيًا، أو ٢٤ ساعة حسب الإعدادات
func hm12(_ d: Date) -> String {
    let c = Cal.gregCal.dateComponents([.hour, .minute], from: d)
    let h24 = c.hour ?? 0
    if Settings.use24h { return ar(String(format: "%02d:%02d", h24, c.minute ?? 0)) }
    let h = h24 % 12 == 0 ? 12 : h24 % 12
    return ar(String(format: "%d:%02d", h, c.minute ?? 0))
}

// MARK: - أوقات الصلاة (أم القرى: فجر 18.5°، عشاء +90 د و120 د في رمضان، عصر شافعي)

enum PKey: String, CaseIterable {
    case fajr, sunrise, dhuhr, asr, maghrib, isha, jumuah, midnight
    /// الشروق ومنتصف الليل أوقات وليست صلوات
    var isPrayer: Bool { self != .sunrise && self != .midnight }
}

struct PTime { let key: PKey; let time: Date }

enum Prayer {
    private static func fx(_ a: Double, _ b: Double) -> Double { a - b * floor(a / b) }
    private static let R = Double.pi / 180
    private static func sn(_ x: Double) -> Double { sin(x * R) }
    private static func cs(_ x: Double) -> Double { cos(x * R) }

    /// الفجر، الشروق، الظهر، العصر، المغرب، العشاء
    static func times(for day: Date, lat: Double = Settings.lat, lng: Double = Settings.lng,
                      method: CalcMethod = Settings.method) -> [Date] {
        let c = Cal.gregCal.dateComponents([.year, .month, .day], from: day)
        var y = c.year ?? 2026, m = c.month ?? 1
        let d = c.day ?? 1
        // اليوم نفسه بتوقيت المكان (للمدن خارج منطقة الجوال الزمنية)، والعرض بتوقيت الجوال
        var g = Calendar(identifier: .gregorian)
        g.timeZone = Settings.timeZone
        let noon = g.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) ?? day
        let tz = Double(g.timeZone.secondsFromGMT(for: noon)) / 3600
        if m <= 2 { y -= 1; m += 12 }
        let a = floor(Double(y) / 100)
        let jd = floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + Double(d) + 2 - a + floor(a / 4) - 1524.5 - lng / 360

        func sun(_ t: Double) -> (dec: Double, eq: Double) {
            let n = jd + t - 2451545
            let gg = fx(357.529 + 0.98560028 * n, 360), q = fx(280.459 + 0.98564736 * n, 360)
            let L = fx(q + 1.915 * sn(gg) + 0.02 * sn(2 * gg), 360), e = 23.439 - 0.00000036 * n
            let dec = asin(sn(e) * sn(L)) / R
            let ra = fx(atan2(cs(e) * sn(L), cs(L)) / R / 15, 24)
            return (dec, q / 15 - ra)
        }
        func mid(_ t: Double) -> Double { fx(12 - sun(t).eq, 24) }
        func at(_ ang: Double, _ t: Double, _ ccw: Bool) -> Double {
            let dc = sun(t).dec
            let v = (-sn(ang) - sn(dc) * sn(lat)) / (cs(dc) * cs(lat))
            let T = acos(max(-1, min(1, v))) / R / 15
            return mid(t) + (ccw ? -T : T)
        }
        /// هل تصل الشمس لهذه الزاوية تحت الأفق؟ (في العروض العالية صيفًا قد لا تصل)
        func reaches(_ ang: Double, _ t: Double) -> Bool {
            let dc = sun(t).dec
            let v = (-sn(ang) - sn(dc) * sn(lat)) / (cs(dc) * cs(lat))
            return v >= -1 && v <= 1
        }
        func asr(_ t: Double) -> Double {
            let dc = sun(t).dec
            return at(-atan(1 / (1 + tan(abs(lat - dc) * R))) / R, t, false)
        }
        var t = [5.0, 6, 12, 13, 18, 19].map { $0 / 24 }
        var h: [Double] = []
        for _ in 0..<2 {
            h = [at(method.fajr, t[0], true), at(0.833, t[1], true), mid(t[2]), asr(t[3]), at(0.833, t[4], false),
                 at(method.isha ?? 18, t[5], false)]
            t = h.map { $0 / 24 }
        }
        // العروض العالية: إن لم تبلغ الشمس زاوية الفجر أو العشاء، أو طال الوقت عن الحد،
        // يُؤخذ جزء من الليل (النصف، وفوق ٤٨° السُّبع) — لا يؤثر في المملكة ولا ما يشابهها
        let night = 24 - (h[4] - h[1])
        let portion = night * (abs(lat) > 48 ? 1.0 / 7.0 : 0.5)
        if !reaches(method.fajr, t[0]) || h[1] - h[0] > portion { h[0] = h[1] - portion }
        if let mins = method.ishaMinutes {
            let ramadan = method.ramadanMinutes != nil && Cal.hijri(noon).m == 9
            h[5] = h[4] + (ramadan ? method.ramadanMinutes! : mins) / 60
        } else if !reaches(method.isha ?? 18, t[5]) || h[5] - h[4] > portion {
            h[5] = h[4] + portion
        }
        // منتصف الليل بفارق الظهر نفسه (tz): يوم تغيّر التوقيت الصيفي يكون اليوم ٢٣ أو ٢٥ ساعة،
        // فبداية اليوم الفعلية + ساعات بفارق آخر تزيح الأوقات ساعة — نطرح ١٢ ساعة من الظهر بدلها
        let base = noon.addingTimeInterval(-12 * 3600)
        return h.map { base.addingTimeInterval((($0 + tz - lng / 15) * 60).rounded() * 60) }
    }

    static func dayTimes(_ day: Date) -> [PTime] {
        let t = times(for: day)
        let friday = Cal.weekday(day) == 5
        let keys: [PKey] = [.fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha]
        return keys.enumerated().map { i, k in PTime(key: (k == .dhuhr && friday) ? .jumuah : k, time: t[i]) }
    }

    static func events(around now: Date, sunrise: Bool) -> [PTime] {
        var ev: [PTime] = []
        for off in -1...1 {
            if let day = Cal.gregCal.date(byAdding: .day, value: off, to: now) {
                ev += dayTimes(day).filter { sunrise || $0.key != .sunrise }
            }
        }
        return ev.sorted { $0.time < $1.time }
    }

    /// الوقت القادم (يشمل الشروق كما في الرئيسية، حتى لا تختلف الويدجت عن بعضها)
    static func state(at now: Date, sunrise: Bool = true) -> (prev: PTime, next: PTime, progress: Double) {
        let ev = events(around: now, sunrise: sunrise)
        let k = ev.firstIndex { $0.time > now } ?? (ev.count - 1)
        let next = ev[k], prev = ev[max(0, k - 1)]
        let span = next.time.timeIntervalSince(prev.time)
        let p = span > 0 ? now.timeIntervalSince(prev.time) / span : 0
        return (prev, next, min(1, max(0, p)))
    }

    /// منتصف الليل: بين مغرب هذا اليوم وفجر اليوم اللي بعده
    static func midnight(after day: Date) -> PTime? {
        guard let next = Cal.gregCal.date(byAdding: .day, value: 1, to: day) else { return nil }
        let mg = times(for: day)[4], fj = times(for: next)[0]
        return PTime(key: .midnight, time: mg.addingTimeInterval(fj.timeIntervalSince(mg) / 2))
    }

    /// للسابقة والقادمة: القادمة تشمل الشروق ومنتصف الليل،
    /// والسابقة دائماً صلاة (بعد الشروق يحسب من الفجر، وبعد منتصف الليل يحسب من العشاء)
    static func prevNext(at now: Date) -> (prev: PTime, next: PTime, progress: Double) {
        var ev: [PTime] = []
        for off in -2...1 {
            if let day = Cal.gregCal.date(byAdding: .day, value: off, to: now) {
                ev += dayTimes(day)
                if let m = midnight(after: day) { ev.append(m) }
            }
        }
        ev.sort { $0.time < $1.time }
        let k = ev.firstIndex { $0.time > now } ?? (ev.count - 1)
        let next = ev[k]
        let prev = ev[..<k].last { $0.key.isPrayer } ?? ev[max(0, k - 1)]
        let span = next.time.timeIntervalSince(prev.time)
        let p = span > 0 ? now.timeIntervalSince(prev.time) / span : 0
        return (prev, next, min(1, max(0, p)))
    }

    /// الليل الحالي أو القادم: من المغرب إلى الفجر
    static func night(around now: Date) -> (maghrib: Date, fajr: Date) {
        let g = Cal.gregCal
        let today = times(for: now)
        if now < today[0] {
            let y = g.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86400)
            return (times(for: y)[4], today[0])
        }
        let tm = g.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
        return (today[4], times(for: tm)[0])
    }

    /// بداية الثلث الأخير من الليل
    static func lastThird(around now: Date) -> (start: Date, fajr: Date, maghrib: Date) {
        let n = night(around: now)
        let len = n.fajr.timeIntervalSince(n.maghrib)
        return (n.fajr.addingTimeInterval(-len / 3), n.fajr, n.maghrib)
    }

    /// كل لحظات تغيّر الصلاة خلال المدة القادمة (لجدولة الويدجت)
    static func boundaries(from now: Date, hours: Double = 26) -> [Date] {
        let end = now.addingTimeInterval(hours * 3600)
        var all: [Date] = []
        for off in 0...2 {
            if let day = Cal.gregCal.date(byAdding: .day, value: off, to: now) {
                all += dayTimes(day).map { $0.time }
                if let m = midnight(after: day) { all.append(m.time) }
                // بداية الثلث الأخير (لويدجت الثلث الأخير)
                if let next = Cal.gregCal.date(byAdding: .day, value: 1, to: day) {
                    let mg = times(for: day)[4], fj = times(for: next)[0]
                    all.append(fj.addingTimeInterval(-fj.timeIntervalSince(mg) / 3))
                }
            }
        }
        return all.filter { $0 > now && $0 < end }.sorted()
    }
}
