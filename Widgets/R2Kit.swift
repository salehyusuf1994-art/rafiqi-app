import SwiftUI
import WidgetKit
import AppIntents

// MARK: - النظام الجديد للويدجت (معتمد ١٨ نوفمبر ٢٠٢٦)
// بطل واحد كبير (كلمة بالثلث أو رقم)، ثم سطر معلومة، ثم تفاصيل صغيرة باهتة.
// أبيض فقط بثلاث شفافيات: ١٠٠٪ للمهم، ٦٢٪ للثانوي، ٤٢٪ للماضي.
// الماضي باهت، والقادم داخل كبسولة زجاج، والحالي يمتلئ (حلقة أو شرطات أو شريط).

enum R2 {
    static let dim: Double = 0.62
    static let past: Double = 0.42

    /// خط النصوص الصغيرة (تجوّل) — واضح بكل الأحجام
    static func font(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black, .semibold: name = "Tajawal-Bold"
        case .regular, .light, .thin, .ultraLight: name = "Tajawal-Regular"
        default: name = "Tajawal-Medium"
        }
        return .custom(name, fixedSize: size)
    }

    // ── الأسماء ──
    static func weekday(_ i: Int) -> String {
        let a = Lang.isEN ? Words.wdEN : Words.wd
        return a[max(0, min(6, i))]
    }
    static func month(_ m: Int, greg: Bool) -> String {
        let i = max(0, min(11, m - 1))
        if Lang.isEN { return greg ? Words.gmEN[i] : Words.hmEN[i] }
        return greg ? (Calli.shami ? Words.gs[i] : Words.gm[i]) : Words.hm[i]
    }
    static func prayer(_ k: PKey) -> String {
        Lang.isEN ? (Words.prEN[k.rawValue] ?? "") : (PR_NAMES[k] ?? "")
    }
    static func num(_ n: Int) -> String { Lang.isEN ? "\(n)" : ar(n) }

    /// «(٨) جمادى الآخرة ١٤٤٨ هـ»
    static func hijriLine(_ d: Date, year: Bool = true) -> String {
        let h = Cal.dmy(d, greg: false)
        if Lang.isEN { return "\(h.d) \(month(h.m, greg: false))" + (year ? " \(h.y) AH" : "") }
        return "(" + ar(h.d) + ") " + month(h.m, greg: false) + (year ? " " + ar(h.y) + " هـ" : "")
    }
    /// «١٨ نوفمبر ٢٠٢٦»
    static func gregLine(_ d: Date, year: Bool = true) -> String {
        let g = Cal.dmy(d, greg: true)
        return num(g.d) + " " + month(g.m, greg: true) + (year ? " " + num(g.y) : "")
    }

    /// وقت الصلاة مع ص/م
    static func time(_ d: Date) -> String {
        let a = ampmText(d)
        return hm12(d) + (a.isEmpty ? "" : " " + a)
    }
}

/// نص ثانوي صغير
struct T2: View {
    let text: String
    var size: CGFloat = 12
    var weight: Font.Weight = .medium
    var op: Double = R2.dim
    var body: some View {
        Text(verbatim: text).font(R2.font(size, weight)).foregroundStyle(Color.white.opacity(op))
            .lineLimit(1).minimumScaleFactor(0.7)
    }
}

/// رقم كبير بتدرّج: أبيض من الأعلى ويخفت للأسفل (الأرقام البطلة)
struct GradDigits: View {
    let text: String
    let size: CGFloat
    @Environment(\.wfont) private var wf
    var body: some View {
        Text(verbatim: text)
            .font(digitFont(size, bold: true, wf))
            .foregroundStyle(LinearGradient(colors: [Color.white, Color.white.opacity(0.58)], startPoint: .top, endPoint: .bottom))
            .lineLimit(1)
            .fixedSize()
            .offset(y: digitLift(size, wf))
            .frame(height: size * 0.8)
    }
}

/// خط فاصل رفيع
struct Hair2: View {
    var vertical = false
    var body: some View {
        if vertical {
            Rectangle().fill(Color.white.opacity(0.18)).frame(width: 0.6)
        } else {
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 0.6)
        }
    }
}

/// كبسولة زجاج للعنصر القادم
struct Pill2: ViewModifier {
    var on = true
    var corner: CGFloat = 7
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, on ? 6 : 0)
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.white.opacity(on ? 0.17 : 0)))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Color.white.opacity(on ? 0.35 : 0), lineWidth: 0.6))
    }
}
extension View {
    func pill2(_ on: Bool = true, corner: CGFloat = 7) -> some View { modifier(Pill2(on: on, corner: corner)) }
}

/// شريط تقدّم رفيع (يمتلئ من اليمين في العربية)
struct Bar2: View {
    let p: Double
    var height: CGFloat = 3
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: Lang.isEN ? .leading : .trailing) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Color.white).frame(width: max(height, g.size.width * min(1, max(0, p))))
            }
        }
        .frame(height: height)
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// حلقة تقدّم دائرية تبدأ من الأعلى
struct Ring2: View {
    let p: Double
    var line: CGFloat = 3
    var on = true
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: line)
            if p > 0 {
                Circle().trim(from: 0, to: min(1, max(0.004, p)))
                    .stroke(Color.white.opacity(on ? 1 : 0.7), style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - إطار الشرطات (حول حافة الويدجت)

/// نقطة على محيط مستطيل مستدير الزوايا، تبدأ من منتصف الأعلى مع عقارب الساعة، مع اتجاه الداخل
private func rrPoint(_ t: CGFloat, _ r: CGRect, _ rad: CGFloat) -> (CGPoint, CGVector) {
    let w = r.width - 2 * rad, h = r.height - 2 * rad, arc = CGFloat.pi * rad / 2
    var s = t * (2 * w + 2 * h + 4 * arc)
    func arcPt(_ c: CGPoint, _ a0: CGFloat) -> (CGPoint, CGVector) {
        let a = a0 + s / rad
        return (CGPoint(x: c.x + rad * cos(a), y: c.y + rad * sin(a)), CGVector(dx: -cos(a), dy: -sin(a)))
    }
    if s <= w / 2 { return (CGPoint(x: r.midX + s, y: r.minY), CGVector(dx: 0, dy: 1)) }
    s -= w / 2
    if s <= arc { return arcPt(CGPoint(x: r.maxX - rad, y: r.minY + rad), -.pi / 2) }
    s -= arc
    if s <= h { return (CGPoint(x: r.maxX, y: r.minY + rad + s), CGVector(dx: -1, dy: 0)) }
    s -= h
    if s <= arc { return arcPt(CGPoint(x: r.maxX - rad, y: r.maxY - rad), 0) }
    s -= arc
    if s <= w { return (CGPoint(x: r.maxX - rad - s, y: r.maxY), CGVector(dx: 0, dy: -1)) }
    s -= w
    if s <= arc { return arcPt(CGPoint(x: r.minX + rad, y: r.maxY - rad), .pi / 2) }
    s -= arc
    if s <= h { return (CGPoint(x: r.minX, y: r.maxY - rad - s), CGVector(dx: 1, dy: 0)) }
    s -= h
    if s <= arc { return arcPt(CGPoint(x: r.minX + rad, y: r.minY + rad), .pi) }
    s -= arc
    return (CGPoint(x: r.minX + rad + s, y: r.minY), CGVector(dx: 0, dy: 1))
}

private struct TickPath: Shape {
    let count: Int
    let lit: Int
    let major: Int
    let inset: CGFloat
    let radius: CGFloat
    /// true: الشرطات المضيئة فقط، false: الباهتة فقط
    let on: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: inset, dy: inset)
        guard count > 0, r.width > 2 * radius, r.height > 2 * radius else { return p }
        for i in 0..<count {
            let isMajor = i % max(1, major) == 0
            let isOn = lit > 0 ? i < lit : isMajor
            if isOn != on { continue }
            let (pt, n) = rrPoint(CGFloat(i) / CGFloat(count), r, radius)
            let len: CGFloat = isMajor ? 7.5 : 4.5
            p.move(to: pt)
            p.addLine(to: CGPoint(x: pt.x + n.dx * len, y: pt.y + n.dy * len))
        }
        return p
    }
}

/// شرطات حول حافة الويدجت: «lit» عدد المضيء منها (صفر = إطار ساعة: الرئيسية فقط مضيئة)
struct TickRim: View {
    let count: Int
    var lit: Int = 0
    var major: Int = 5
    var inset: CGFloat = 8
    var radius: CGFloat = 17
    var body: some View {
        ZStack {
            TickPath(count: count, lit: lit, major: major, inset: inset, radius: radius, on: false)
                .stroke(Color.white.opacity(lit > 0 ? 0.2 : 0.28), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            TickPath(count: count, lit: lit, major: major, inset: inset, radius: radius, on: true)
                .stroke(Color.white.opacity(lit > 0 ? 0.95 : 0.75), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - مكوّنات الصلاة

/// «باقي على العصر ٠:٤٥:١٢»
struct LeftLine2: View {
    let next: PTime
    let at: Date
    var size: CGFloat = 13.5
    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: L("باقي على") + " " + R2.prayer(next.key))
                .font(R2.font(size, .medium)).foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(1).fixedSize()
            CountDown(to: next.time, size: size + 2, color: .white, width: (size + 2) * 4.6, at: at)
                .fixedSize()
        }
    }
}

/// صف الصلوات الست: الاسم بالثلث فوق الوقت؛ الماضي باهت والقادم في كبسولة
struct PrayerRow2: View {
    let date: Date
    var nameH: CGFloat = 19
    var timeSize: CGFloat = 14.5
    var colW: CGFloat = 52
    var body: some View {
        let times = Prayer.dayTimes(date)
        let nextIdx = times.firstIndex { $0.time > date }
        HStack(spacing: 0) {
            ForEach(Array(times.enumerated()), id: \.offset) { i, p in
                let past = nextIdx.map { i < $0 } ?? true
                let on = i == nextIdx
                VStack(spacing: 1) {
                    PrName(p.key, colW - 4, nameH)
                    Digits(text: hm12(p.time), size: timeSize, color: .white, bold: on)
                        .frame(height: timeSize + 5)
                        .pill2(on)
                }
                .opacity(past ? R2.past : 1)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - المناسبات (نفس قائمة تقويم التطبيق)

enum Occasions {
    static func of(_ d: Date) -> String? {
        let h = Cal.dmy(d, greg: false)
        let g = Cal.gregCal.dateComponents([.month, .day], from: d)
        switch (h.m, h.d) {
        case (1, 1): return "رأس السنة الهجرية"
        case (1, 10): return "يوم عاشوراء"
        case (9, 1): return "بداية شهر رمضان"
        case (10, 1): return "عيد الفطر"
        case (12, 8): return "يوم التروية"
        case (12, 9): return "يوم عرفة"
        case (12, 10): return "عيد الأضحى"
        case (12, 11), (12, 12), (12, 13): return "أيام التشريق"
        default: break
        }
        switch (g.month ?? 0, g.day ?? 0) {
        case (2, 22): return "يوم التأسيس"
        case (3, 11): return "يوم العلم"
        case (9, 23): return "اليوم الوطني السعودي"
        default: return nil
        }
    }

    /// أقرب مناسبة (اليوم يُحسب)
    static func next(from now: Date) -> (date: Date, name: String, days: Int)? {
        let g = Cal.gregCal
        let today = g.startOfDay(for: now)
        for k in 0..<400 {
            guard let d = g.date(byAdding: .day, value: k, to: today) else { break }
            if let n = of(d) { return (d, n, k) }
        }
        return nil
    }

    /// اسم قصير للعرض الكبير
    static func short(_ name: String) -> String {
        switch name {
        case "بداية شهر رمضان": return "رمضان"
        case "اليوم الوطني السعودي": return "اليوم الوطني"
        case "رأس السنة الهجرية": return "السنة الهجرية"
        default: return name
        }
    }

    static func daysWord(_ n: Int) -> String {
        if Lang.isEN { return n == 1 ? "day" : "days" }
        // ٣–١٠ «أيام»، ١١–٩٩ «يومًا»، والمئات وما بعدها مثل «١٠٠ يوم»
        let r = n % 100
        if (3...10).contains(r) { return "أيام" }
        if (11...99).contains(r) { return "يومًا" }
        return "يوم"
    }
}

// MARK: - الأذكار (تعدّ من الويدجت نفسها)

enum Adhkar {
    struct Item { let text: String; let times: Int; let source: String }

    static let morning: [Item] = [
        Item(text: "أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللهُ وَحْدَهُ لَا شَرِيكَ لَهُ", times: 1, source: "رواه مسلم"),
        Item(text: "بِسْمِ اللهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ وَهُوَ السَّمِيعُ الْعَلِيمُ", times: 3, source: "رواه أبو داود والترمذي"),
        Item(text: "سُبْحَانَ اللهِ وَبِحَمْدِهِ", times: 100, source: "رواه مسلم"),
    ]
    static let evening: [Item] = [
        Item(text: "أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللهُ وَحْدَهُ لَا شَرِيكَ لَهُ", times: 1, source: "رواه مسلم"),
        Item(text: "بِسْمِ اللهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ وَهُوَ السَّمِيعُ الْعَلِيمُ", times: 3, source: "رواه أبو داود والترمذي"),
        Item(text: "سُبْحَانَ اللهِ وَبِحَمْدِهِ", times: 100, source: "رواه مسلم"),
    ]
    static let general: [Item] = [
        Item(text: "سُبْحَانَ اللهِ وَبِحَمْدِهِ", times: 100, source: "رواه مسلم"),
        Item(text: "لَا إِلَهَ إِلَّا اللهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ، وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ", times: 10, source: "متفق عليه"),
        Item(text: "أَسْتَغْفِرُ اللهَ وَأَتُوبُ إِلَيْهِ", times: 100, source: "رواه البخاري ومسلم"),
        Item(text: "سُبْحَانَ اللهِ، وَالْحَمْدُ لِلَّهِ، وَلَا إِلَهَ إِلَّا اللهُ، وَاللهُ أَكْبَرُ", times: 33, source: "رواه مسلم"),
    ]

    /// ٠ صباح، ١ مساء، ٢ عام
    static func period(_ d: Date) -> Int {
        let t = Prayer.times(for: d)
        if d >= t[0] && d < t[2] { return 0 }
        if d >= t[3] && d < t[5] { return 1 }
        return 2
    }
    static func list(_ p: Int) -> [Item] { [morning, evening, general][max(0, min(2, p))] }
    static func title(_ p: Int) -> String { L(["أذكار الصباح", "أذكار المساء", "ذكر"][max(0, min(2, p))]) }

    private static var d: UserDefaults { AppGroup.defaults }
    /// مفتاح الفترة الحالية (يتصفّر العدّ والاختيار عند تغيّرها)
    private static func key(_ now: Date) -> String {
        let c = Cal.gregCal.dateComponents([.year, .month, .day], from: now)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(period(now))"
    }
    private static func sync(_ now: Date) {
        let k = key(now)
        if d.string(forKey: "dhikr_key") != k {
            d.set(k, forKey: "dhikr_key"); d.set(0, forKey: "dhikr_idx"); d.set(0, forKey: "dhikr_count")
        }
    }
    static func current(_ now: Date) -> (item: Item, count: Int, period: Int) {
        let p = period(now)
        let l = list(p)
        let k = key(now)
        let same = d.string(forKey: "dhikr_key") == k
        let idx = same ? d.integer(forKey: "dhikr_idx") : 0
        let count = same ? d.integer(forKey: "dhikr_count") : 0
        return (l[((idx % l.count) + l.count) % l.count], count, p)
    }
    static func tap(_ now: Date = Date()) {
        sync(now)
        let c = current(now)
        d.set(min(c.item.times, c.count + 1), forKey: "dhikr_count")
    }
    static func next(_ now: Date = Date()) {
        sync(now)
        d.set(d.integer(forKey: "dhikr_idx") + 1, forKey: "dhikr_idx")
        d.set(0, forKey: "dhikr_count")
    }
}

/// ضغطة على حلقة الذكر: عدّة واحدة (بدون فتح التطبيق)
struct DhikrTapIntent: AppIntent {
    static let title: LocalizedStringResource = "عدّ الذكر"
    static let isDiscoverable = false
    init() {}
    func perform() async throws -> some IntentResult {
        Adhkar.tap()
        return .result()
    }
}

/// الذكر التالي
struct DhikrNextIntent: AppIntent {
    static let title: LocalizedStringResource = "الذكر التالي"
    static let isDiscoverable = false
    init() {}
    func perform() async throws -> some IntentResult {
        Adhkar.next()
        return .result()
    }
}

// MARK: - القبلة (من موقعك إلى الكعبة)

enum QiblaMath {
    static let kaaba = (lat: 21.422487, lng: 39.826206)
    /// الاتجاه بالدرجات من الشمال الحقيقي
    static func bearing(lat: Double = Settings.lat, lng: Double = Settings.lng) -> Double {
        let r = Double.pi / 180
        let p1 = lat * r, p2 = kaaba.lat * r, dl = (kaaba.lng - lng) * r
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let b = atan2(y, x) / r
        return (b + 360).truncatingRemainder(dividingBy: 360)
    }
    /// المسافة بالكيلومترات
    static func distance(lat: Double = Settings.lat, lng: Double = Settings.lng) -> Double {
        let r = Double.pi / 180
        let dp = (kaaba.lat - lat) * r, dl = (kaaba.lng - lng) * r
        let a = sin(dp / 2) * sin(dp / 2) + cos(lat * r) * cos(kaaba.lat * r) * sin(dl / 2) * sin(dl / 2)
        return 6371 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

// MARK: - لقطة الملفات والمساحة (يكتبها التطبيق، وتقرؤها الويدجت)

struct WFile: Codable, Identifiable {
    var id: String { rel }
    let name: String
    let kind: String       // image, video, audio, document, archive, other
    let rel: String        // المسار داخل «ملفاتي»
    let date: Double
    var thumb: String?     // اسم صورة مصغّرة في المجلد المشترك
}

struct WFilesSnap: Codable {
    var files: [WFile] = []
    var locked = false
    var rafiqiBytes: Int64 = 0
    var t: Double = 0
}

enum WFilesStore {
    static var dir: URL? { AppGroup.container?.appendingPathComponent("wfiles", isDirectory: true) }
    static func load() -> WFilesSnap {
        guard let d = AppGroup.defaults.data(forKey: "w_files"), let s = try? JSONDecoder().decode(WFilesSnap.self, from: d) else { return WFilesSnap() }
        return s
    }
    static func save(_ s: WFilesSnap) {
        if let d = try? JSONEncoder().encode(s) { AppGroup.defaults.set(d, forKey: "w_files") }
    }
    static func thumb(_ name: String?) -> UIImage? {
        guard let name, let u = dir?.appendingPathComponent(name), let data = try? Data(contentsOf: u) else { return nil }
        return UIImage(data: data)
    }
    /// مساحة الجوال (المستخدمة، الكلية)
    static func volume() -> (used: Int64, total: Int64)? {
        let u = URL(fileURLWithPath: NSHomeDirectory())
        guard let v = try? u.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage, total > 0 else { return nil }
        return (Int64(total) - free, Int64(total))
    }
    static func gb(_ bytes: Int64) -> String {
        let g = Double(bytes) / 1_000_000_000
        let s = g >= 10 ? String(format: "%.0f", g) : String(format: "%.1f", g)
        return (Lang.isEN ? s : ar(s).replacingOccurrences(of: ".", with: "٫")) + " " + L("غ.ب")
    }
}
