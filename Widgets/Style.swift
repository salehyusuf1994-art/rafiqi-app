import SwiftUI
import WidgetKit
import AppIntents
import UIKit
import CoreText

// MARK: - الخطوط

/// خطوط الويدجت: الثلث (صور مرسومة مسبقًا) وخطوط أخرى تُرسم وقت العرض
enum WFont: String, CaseIterable, Codable, Identifiable {
    case thuluth, naskh, ruqaa, ruwudu, kufi, nastaliq, katibeh, blaka, tajawal, readex
    var id: String { rawValue }

    var title: String {
        switch self {
        case .thuluth: return L("الثلث")
        case .naskh: return L("النسخ")
        case .ruqaa: return L("الرقعة")
        case .ruwudu: return L("رُوُدو")
        case .kufi: return L("الكوفي")
        case .nastaliq: return L("النستعليق")
        case .katibeh: return L("كاتبة")
        case .blaka: return L("بلاكا")
        case .tajawal: return L("تجوّل")
        case .readex: return L("ريدكس")
        }
    }

    /// اسم الخط في النظام (PostScript)
    var ps: String {
        switch self {
        case .thuluth: return "DecoTypeThuluthII"
        case .naskh: return "Amiri-Bold"
        case .ruqaa: return "ArefRuqaa-Bold"
        case .ruwudu: return "Ruwudu-Bold"
        case .kufi: return "ReemKufiMono-Regular"
        case .nastaliq: return "Gulzar-Regular"
        case .katibeh: return "Katibeh-Regular"
        case .blaka: return "Blaka-Regular"
        case .tajawal: return "Tajawal-Bold"
        case .readex: return "ReadexPro-SemiBold"
        }
    }

    /// خط الأرقام والعدّادات: الخطوط الحديثة أرقامها واضحة، والباقي يبقى على أرقام رفيقي
    var digitsPS: String? {
        switch self {
        case .naskh, .ruqaa, .tajawal, .readex: return ps
        default: return nil
        }
    }

    /// يناسب النص الإنجليزي
    var latin: Bool { self == .tajawal || self == .readex || self == .naskh }
}

private struct WFontKey: EnvironmentKey { static let defaultValue: WFont = .thuluth }
extension EnvironmentValues {
    var wfont: WFont {
        get { self[WFontKey.self] }
        set { self[WFontKey.self] = newValue }
    }
}

// MARK: - الخلفية والزخرفة

enum BgKind: String, CaseIterable, Codable, Identifiable {
    case clear, glass, dark, color, gradient
    var id: String { rawValue }
    var title: String {
        switch self {
        case .clear: return L("شفافة")
        case .glass: return L("زجاجية")
        case .dark: return L("داكنة")
        case .color: return L("لون")
        case .gradient: return L("متدرّجة")
        }
    }
    var icon: String {
        switch self {
        case .clear: return "square.dashed"
        case .glass: return "drop.halffull"
        case .dark: return "moon.fill"
        case .color: return "paintbrush.fill"
        case .gradient: return "circle.lefthalf.filled"
        }
    }
}

enum DecoKind: String, CaseIterable, Codable, Identifiable {
    case off, line, double, dots, corners, stars
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return L("بدون")
        case .line: return L("إطار")
        case .double: return L("مزدوج")
        case .dots: return L("نقاط")
        case .corners: return L("أركان")
        case .stars: return L("نجوم")
        }
    }
}

enum Palette {
    static let solids: [(String, [Double])] = [
        ("كحلي", [0.09, 0.12, 0.22]), ("أسود", [0.05, 0.05, 0.06]), ("رمادي", [0.22, 0.23, 0.25]),
        ("بنّي", [0.29, 0.20, 0.13]), ("زيتي", [0.17, 0.24, 0.17]), ("عنابي", [0.33, 0.10, 0.14]),
        ("بنفسجي", [0.24, 0.15, 0.35]), ("أزرق", [0.10, 0.27, 0.48]), ("فيروزي", [0.05, 0.36, 0.38]),
        ("رملي", [0.72, 0.60, 0.42]), ("بيج", [0.88, 0.82, 0.72]), ("أبيض", [0.96, 0.96, 0.95]),
    ]
    static let gradients: [(String, [[Double]])] = [
        ("ليل", [[0.07, 0.09, 0.20], [0.25, 0.13, 0.36]]),
        ("غروب", [[0.93, 0.45, 0.28], [0.55, 0.16, 0.38]]),
        ("صحراء", [[0.86, 0.68, 0.43], [0.45, 0.28, 0.16]]),
        ("زمرّد", [[0.05, 0.42, 0.40], [0.03, 0.17, 0.22]]),
        ("ذهبي", [[0.80, 0.64, 0.35], [0.30, 0.22, 0.12]]),
        ("بحر", [[0.15, 0.55, 0.85], [0.06, 0.15, 0.40]]),
        ("وردي", [[0.95, 0.55, 0.65], [0.45, 0.25, 0.55]]),
        ("فحمي", [[0.30, 0.31, 0.34], [0.06, 0.06, 0.08]]),
    ]
    static func rgb(_ c: Color) -> [Double] {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [Double(r), Double(g), Double(b)].map { min(1, max(0, $0)) }
    }
    static func same(_ a: [Double], _ b: [Double]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 0.01 }
    }
    static func color(_ a: [Double]) -> Color {
        a.count >= 3 ? Color(red: a[0], green: a[1], blue: a[2]) : .black
    }
    static func gradient(_ i: Int) -> [Color] {
        gradients[max(0, min(gradients.count - 1, i))].1.map { color($0) }
    }
}

// MARK: - نمط الويدجت

struct WStyle: Codable, Equatable {
    var bg: BgKind = .clear
    var color: [Double] = Palette.solids[0].1
    var grad: Int = 0
    /// قوة الخلفية ٠…١ (للزجاجية والداكنة واللون والتدرّج)
    var strength: Double = 0.75
    var font: WFont = .thuluth
    var deco: DecoKind = .off
    var decoOpacity: Double = 0.55
    /// لون الخط الخاص بهذا التصميم (nil = اللون العام)
    var tint: [Double]? = nil

    init() {}

    // فكّ مرن: أي حقل ناقص يأخذ القيمة الافتراضية (عشان الإضافات المستقبلية)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bg = (try? c.decode(BgKind.self, forKey: .bg)) ?? .clear
        color = (try? c.decode([Double].self, forKey: .color)) ?? Palette.solids[0].1
        grad = (try? c.decode(Int.self, forKey: .grad)) ?? 0
        strength = (try? c.decode(Double.self, forKey: .strength)) ?? 0.75
        font = (try? c.decode(WFont.self, forKey: .font)) ?? .thuluth
        deco = (try? c.decode(DecoKind.self, forKey: .deco)) ?? .off
        decoOpacity = (try? c.decode(Double.self, forKey: .decoOpacity)) ?? 0.55
        tint = try? c.decode([Double].self, forKey: .tint)
    }
}

/// أنماط الويدجت المحفوظة: نمط عام، ونمط خاص لكل تصميم (إن عُدّل)
enum Styles {
    private static var d: UserDefaults { AppGroup.defaults }

    /// بصمة كل إعدادات التصميم: تتغيّر فقط إذا تغيّر تصميم أو لون أو خط (لإعادة رسم المعرض عند الحاجة فقط)
    static var stamp: Int {
        var h = Hasher()
        for (k, v) in d.dictionaryRepresentation().sorted(by: { $0.key < $1.key })
        where k.hasPrefix("style.") || k.hasPrefix("tint") || k == "lock_font" || k == "hijri_offset" || k == "favorites" {
            h.combine(k); h.combine(String(describing: v))
        }
        return h.finalize()
    }

    static var global: WStyle {
        get { d.data(forKey: "style.global").flatMap { try? JSONDecoder().decode(WStyle.self, from: $0) } ?? WStyle() }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "style.global") }
    }

    static func custom(_ kind: String) -> WStyle? {
        d.data(forKey: "style." + kind).flatMap { try? JSONDecoder().decode(WStyle.self, from: $0) }
    }

    static func get(_ kind: String) -> WStyle {
        if let c = custom(kind) { return c }
        var g = global
        // ويدجت الوسائط والمباريات بخلفية زجاجية افتراضيًا (مثل المراجع)
        if (kind.hasPrefix("hilal.m.") || kind.hasPrefix("hilal.s.")), g.bg == .clear { g.bg = .glass }
        return g
    }

    static func set(_ kind: String, _ s: WStyle?) {
        if let s { d.set(try? JSONEncoder().encode(s), forKey: "style." + kind) } else { d.removeObject(forKey: "style." + kind) }
    }

    static func hasCustom(_ kind: String) -> Bool { custom(kind) != nil }

    /// خط ويدجت شاشة القفل
    static var lockFont: WFont {
        get { d.string(forKey: "lock_font").flatMap { WFont(rawValue: $0) } ?? .thuluth }
        set { d.set(newValue.rawValue, forKey: "lock_font") }
    }

    // ── المفضّلة ──
    static var favorites: [String] {
        get { d.stringArray(forKey: "favorites") ?? [] }
        set { d.set(newValue, forKey: "favorites") }
    }
    static func isFavorite(_ id: String) -> Bool { favorites.contains(id) }
    static func toggleFavorite(_ id: String) {
        var f = favorites
        if let i = f.firstIndex(of: id) { f.remove(at: i) } else { f.append(id) }
        favorites = f
    }
}

// MARK: - خيارات «تعديل الأداة»

enum BgOpt: String, AppEnum {
    case app, clear, glass, dark, color, gradient
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "الخلفية"
    static let caseDisplayRepresentations: [BgOpt: DisplayRepresentation] = [
        .app: "حسب تصميمك في التطبيق", .clear: "شفافة", .glass: "زجاجية", .dark: "داكنة",
        .color: "لون (من التطبيق)", .gradient: "متدرّجة (من التطبيق)",
    ]
    var kind: BgKind? { BgKind(rawValue: rawValue) }
}

enum FontOpt: String, AppEnum {
    case app, thuluth, naskh, ruqaa, ruwudu, kufi, nastaliq, katibeh, blaka, tajawal, readex
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "الخط"
    static let caseDisplayRepresentations: [FontOpt: DisplayRepresentation] = [
        .app: "حسب تصميمك في التطبيق", .thuluth: "الثلث", .naskh: "النسخ", .ruqaa: "الرقعة", .ruwudu: "رُوُدو",
        .kufi: "الكوفي", .nastaliq: "النستعليق", .katibeh: "كاتبة", .blaka: "بلاكا", .tajawal: "تجوّل", .readex: "ريدكس",
    ]
    var font: WFont? { WFont(rawValue: rawValue) }
}

// MARK: - نصوص صور الخط (لرسمها بالخطوط الأخرى)

enum Words {
    static let hm = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة",
                     "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
    static let gm = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]
    static let gs = ["كانون الثاني", "شباط", "آذار", "نيسان", "أيار", "حزيران", "تموز", "آب", "أيلول",
                     "تشرين الأول", "تشرين الثاني", "كانون الأول"]
    static let wd = ["الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]
    static let wl = ["ح", "ن", "ث", "ر", "خ", "ج", "س"]
    static let pr: [String: String] = ["fajr": "الفجر", "sunrise": "الشروق", "dhuhr": "الظهر", "asr": "العصر",
                                       "maghrib": "المغرب", "isha": "العشاء", "jumuah": "الجمعة", "midnight": "منتصف الليل"]
    static let wx: [String: String] = ["clear": "صحو", "partly": "غائم جزئيًا", "cloudy": "غائم", "fog": "ضباب",
                                       "drizzle": "رذاذ", "rain": "مطر", "snow": "ثلوج", "thunder": "عاصفة رعدية"]
    static let labels: [String: String] = ["lbl_next": "الصلاة القادمة", "lbl_prev": "الصلاة السابقة",
                                           "lbl_next_m": "القادم", "lbl_prev_m": "السابق", "lbl_left": "باقي",
                                           "lbl_ago": "مضى", "hi": "ع", "lo": "ص", "city": "المدينة المنورة",
                                           "app_title": "رفيقي", "lbl_third": "الثلث الأخير", "lbl_iftar": "الإفطار",
                                           "lbl_imsak": "الإمساك", "lbl_wird": "ورد اليوم", "lbl_juz": "الجزء",
                                           "lbl_khatma": "الختمة", "lbl_ramadan_left": "على رمضان", "lbl_day": "يوم",
                                           "lbl_days": "أيام", "lbl_today": "اليوم", "lbl_now": "الآن",
                                           "lbl_humidity": "الرطوبة", "lbl_wind": "الرياح", "lbl_sunrise": "الشروق",
                                           "lbl_sunset": "الغروب", "lbl_rain": "المطر", "lbl_fasting": "صائم",
                                           "lbl_leftto": "باقي على", "lbl_next2": "الصلاة القادمة",
                                           "lbl_dayn": "يومًا", "lbl_days2": "يومان"]

    private static func num(_ s: Substring) -> Int? { Int(s) }

    /// النص المقابل لاسم الصورة (بدون لاحقة ‎_t)
    static func text(_ name: String, shami: Bool = Settings.shamiMonths) -> String? {
        let n = name.hasSuffix("_t") ? String(name.dropLast(2)) : name
        if let s = labels[n] { return s }
        if n.hasPrefix("pr_") { return pr[String(n.dropFirst(3))] }
        if n.hasPrefix("p_") { return pr[String(n.dropFirst(2))] }
        if n.hasPrefix("wx_") { return wx[String(n.dropFirst(3))] }
        if n.hasPrefix("hyl"), let y = num(n.dropFirst(3)) { return ar(y) + " هـ" }
        if n.hasPrefix("gyl"), let y = num(n.dropFirst(3)) { return ar(y) + " م" }
        if n.hasPrefix("hy"), let y = num(n.dropFirst(2)) { return ar(y) + " هـ" }
        if n.hasPrefix("gy"), let y = num(n.dropFirst(2)) { return ar(y) + " م" }
        if n.hasPrefix("hm"), let m = num(n.dropFirst(2)), (1...12).contains(m) { return hm[m - 1] }
        if n.hasPrefix("gm"), let m = num(n.dropFirst(2)), (1...12).contains(m) { return shami ? gs[m - 1] : gm[m - 1] }
        if n.hasPrefix("wd"), let i = num(n.dropFirst(2)), (0...6).contains(i) { return wd[i] }
        if n.hasPrefix("wl"), let i = num(n.dropFirst(2)), (0...6).contains(i) { return wl[i] }
        if n.hasPrefix("pn"), let i = num(n.dropFirst(2)) { return "(" + ar(i) + ")" }
        for p in ["dg", "bn", "wm"] where n.hasPrefix(p) {
            if let i = num(n.dropFirst(2)) { return ar(i) }
        }
        if n.hasPrefix("d"), n.count == 2, let i = num(n.dropFirst(1)), (0...6).contains(i) { return wd[i] }
        return nil
    }
}

// MARK: - رسم الكلمة بخط آخر بنفس مقاس صورة الثلث (عشان التنسيق يبقى كما هو)

enum AltWord {
    private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()

    /// يزيل التشكيل (يناسب الخطوط الحديثة أكثر)
    static func plain(_ s: String) -> String {
        var v = String.UnicodeScalarView()
        for u in s.unicodeScalars where !(0x064B...0x0652).contains(u.value) && u.value != 0x0670 { v.append(u) }
        return String(v)
    }

    static func image(_ name: String, font: WFont) -> UIImage? {
        guard let base = Calli.png(name), let text = Lang.isEN ? Words.en(name) : Words.text(name) else { return nil }
        var key = font.rawValue + "|" + name
        if Settings.shamiMonths { key += "|s" }
        if Settings.westernDigits { key += "|w" }
        if Lang.isEN { key += "|en" }
        lock.lock(); let hit = cache[key]; lock.unlock()
        if let hit { return hit }
        guard UIFont(name: font.ps, size: 20) != nil else { return nil }
        var t = font == .thuluth || Lang.isEN ? text : plain(text)
        // بلاكا ما فيه حرف المدّ «ـ»
        if font == .blaka { t = t.replacingOccurrences(of: "\u{0640}", with: "") }
        let img = render(text: t, font: font, name: name, box: base.size)
        if let img { lock.lock(); cache[key] = img; lock.unlock() }
        return img
    }

    private static func render(text: String, font: WFont, name: String, box: CGSize) -> UIImage? {
        let ct = CTFontCreateWithName(font.ps as CFString, 100, nil)
        var alpha: CGFloat = 1
        if name.hasPrefix("wm") { alpha = 0.18 } else if name.hasPrefix("bn") { alpha = 0.9 }
        let col = UIColor(red: 0xd6 / 255, green: 0xd5 / 255, blue: 0xd1 / 255, alpha: alpha).cgColor
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ct,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): col,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        guard ink.width > 1, ink.height > 1 else { return nil }

        let W = box.width, H = box.height
        let isLine = !name.hasSuffix("_t") && abs(H * PX - 323) < 3
        let isSquare = name.hasPrefix("p_") || (name.hasPrefix("d") && name.count == 2)
        var k: CGFloat
        var ox: CGFloat, baseY: CGFloat
        if isLine {
            // خط الأساس نفسه، والكلمة تتّسع لأقصى ما يسمح به المربع
            let up = LINE_UP / PX * 0.80, dn = LINE_DN / PX * 0.80
            k = min(W * 0.98 / ink.width, up / max(1, ink.maxY), ink.minY < 0 ? dn / -ink.minY : .greatestFiniteMagnitude)
            baseY = LINE_UP / PX
        } else {
            let bw = isSquare ? W * (name.hasPrefix("p_") ? 0.5 : 0.84) : W * 0.97
            let bh = isSquare ? H * (name.hasPrefix("p_") ? 0.2 : 0.42) : H * 0.94
            k = min(bw / ink.width, bh / ink.height)
            // يتوسّط عموديًا
            baseY = H / 2 + (ink.maxY + ink.minY) / 2 * k
        }
        ox = (W - ink.width * k) / 2 - ink.minX * k

        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = PX
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: box, format: fmt).image { c in
            let g = c.cgContext
            g.textMatrix = .identity
            g.translateBy(x: ox, y: baseY)
            g.scaleBy(x: k, y: -k)
            CTLineDraw(line, g)
        }
    }
}

// MARK: - الزخرفة حول الويدجت

struct Star8: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), R = min(r.width, r.height) / 2, ri = R * 0.55
        for i in 0..<16 {
            let a = Double(i) * .pi / 8 - .pi / 2
            let rr = i % 2 == 0 ? R : ri
            let pt = CGPoint(x: c.x + rr * CGFloat(cos(a)), y: c.y + rr * CGFloat(sin(a)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

struct CornerMarks: Shape {
    var inset: CGFloat = 9
    var len: CGFloat = 16
    func path(in r: CGRect) -> Path {
        var p = Path()
        let a = r.insetBy(dx: inset, dy: inset)
        let pts: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: a.minX, y: a.minY), 1, 1), (CGPoint(x: a.maxX, y: a.minY), -1, 1),
            (CGPoint(x: a.minX, y: a.maxY), 1, -1), (CGPoint(x: a.maxX, y: a.maxY), -1, -1),
        ]
        for (o, sx, sy) in pts {
            p.move(to: CGPoint(x: o.x, y: o.y + sy * len))
            p.addLine(to: o)
            p.addLine(to: CGPoint(x: o.x + sx * len, y: o.y))
            // معيّن صغير قرب الزاوية
            let m = CGPoint(x: o.x + sx * 6, y: o.y + sy * 6), d: CGFloat = 2.6
            p.move(to: CGPoint(x: m.x, y: m.y - d)); p.addLine(to: CGPoint(x: m.x + d, y: m.y))
            p.addLine(to: CGPoint(x: m.x, y: m.y + d)); p.addLine(to: CGPoint(x: m.x - d, y: m.y)); p.closeSubpath()
        }
        return p
    }
}

struct DecoView: View {
    let kind: DecoKind
    let opacity: Double
    var body: some View {
        let c = TXT.opacity(opacity)
        switch kind {
        case .off:
            EmptyView()
        case .line:
            ContainerRelativeShape().inset(by: 7).stroke(c, lineWidth: 1.2)
        case .double:
            ZStack {
                ContainerRelativeShape().inset(by: 6).stroke(c, lineWidth: 1.4)
                ContainerRelativeShape().inset(by: 10).stroke(c.opacity(0.7), lineWidth: 0.6)
            }
        case .dots:
            ContainerRelativeShape().inset(by: 8)
                .stroke(c, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [0.1, 6]))
        case .corners:
            CornerMarks().stroke(c, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        case .stars:
            GeometryReader { g in
                let s: CGFloat = 11, m: CGFloat = 12
                ZStack {
                    ContainerRelativeShape().inset(by: 8).stroke(c.opacity(0.6), lineWidth: 0.7)
                    ForEach(0..<4, id: \.self) { i in
                        Star8().fill(c)
                            .frame(width: s, height: s)
                            .position(x: i % 2 == 0 ? m : g.size.width - m, y: i < 2 ? m : g.size.height - m)
                    }
                }
            }
        }
    }
}

// MARK: - إعدادات التاريخ والوقت

extension Settings {
    /// تعديل التاريخ الهجري بالأيام (−٢…+٢)
    static var hijriOffset: Int {
        get { max(-2, min(2, AppGroup.defaults.integer(forKey: "hijri_offset"))) }
        set { AppGroup.defaults.set(max(-2, min(2, newValue)), forKey: "hijri_offset") }
    }
    /// نظام ٢٤ ساعة
    static var use24h: Bool {
        get { AppGroup.defaults.bool(forKey: "use24h") }
        set { AppGroup.defaults.set(newValue, forKey: "use24h") }
    }
    /// أسماء الأشهر الميلادية الشامية (كانون الثاني، شباط…)
    static var shamiMonths: Bool {
        get { AppGroup.defaults.bool(forKey: "shami_months") }
        set { AppGroup.defaults.set(newValue, forKey: "shami_months") }
    }
    /// الأرقام الإنجليزية 123 بدل العربية ١٢٣
    static var westernDigits: Bool {
        get { AppGroup.defaults.bool(forKey: "western_digits") }
        set { AppGroup.defaults.set(newValue, forKey: "western_digits") }
    }
    /// وحدة الحرارة: مئوية أو فهرنهايت
    static var fahrenheit: Bool {
        get { AppGroup.defaults.bool(forKey: "wx_f") }
        set { AppGroup.defaults.set(newValue, forKey: "wx_f") }
    }
    /// وحدة الرياح: كم/س أو م/ث
    static var windMS: Bool {
        get { AppGroup.defaults.bool(forKey: "wx_ms") }
        set { AppGroup.defaults.set(newValue, forKey: "wx_ms") }
    }
}

// MARK: - اللغة (العربية افتراضيًا، والإنجليزية من إعدادات النظام ← رفيقي ← اللغة)

enum Lang {
    static let isEN: Bool = (Bundle.main.preferredLocalizations.first ?? "ar").hasPrefix("en")
    static var dir: LayoutDirection { isEN ? .leftToRight : .rightToLeft }
}

/// نص مترجم (المفتاح هو النص العربي نفسه)
func L(_ s: String) -> String { NSLocalizedString(s, comment: "") }

/// نص مترجم بقالب (%@)
func LF(_ s: String, _ args: CVarArg...) -> String { String(format: L(s), arguments: args) }

extension Words {
    static let hmEN = ["Muharram", "Safar", "Rabi I", "Rabi II", "Jumada I", "Jumada II",
                       "Rajab", "Sha'ban", "Ramadan", "Shawwal", "Dhu al-Qa'dah", "Dhu al-Hijjah"]
    static let gmEN = ["January", "February", "March", "April", "May", "June", "July", "August",
                       "September", "October", "November", "December"]
    static let wdEN = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let wlEN = ["S", "M", "T", "W", "T", "F", "S"]
    static let prEN: [String: String] = ["fajr": "Fajr", "sunrise": "Sunrise", "dhuhr": "Dhuhr", "asr": "Asr",
                                         "maghrib": "Maghrib", "isha": "Isha", "jumuah": "Jumuah", "midnight": "Midnight"]
    static let wxEN: [String: String] = ["clear": "Clear", "partly": "Partly cloudy", "cloudy": "Cloudy", "fog": "Fog",
                                         "drizzle": "Drizzle", "rain": "Rain", "snow": "Snow", "thunder": "Thunderstorm"]
    static let labelsEN: [String: String] = ["lbl_next": "Next prayer", "lbl_prev": "Previous prayer", "lbl_next_m": "Next",
                                             "lbl_prev_m": "Previous", "lbl_left": "Left", "lbl_ago": "Ago", "hi": "H", "lo": "L",
                                             "city": "Madinah", "app_title": "Rafiqi", "lbl_third": "Last third",
                                             "lbl_iftar": "Iftar", "lbl_imsak": "Imsak", "lbl_wird": "Daily wird",
                                             "lbl_juz": "Juz", "lbl_khatma": "Khatma", "lbl_ramadan_left": "to Ramadan",
                                             "lbl_day": "day", "lbl_days": "days", "lbl_today": "Today", "lbl_now": "Now",
                                             "lbl_humidity": "Humidity", "lbl_wind": "Wind", "lbl_sunrise": "Sunrise",
                                             "lbl_sunset": "Sunset", "lbl_rain": "Rain", "lbl_fasting": "Fasting",
                                             "lbl_leftto": "Until", "lbl_next2": "Next prayer",
                                             "lbl_dayn": "days", "lbl_days2": "days"]

    /// النص الإنجليزي المقابل لاسم الصورة
    static func en(_ name: String) -> String? {
        let n = name.hasSuffix("_t") ? String(name.dropLast(2)) : name
        func num(_ s: Substring) -> Int? { Int(s) }
        if let s = labelsEN[n] { return s }
        if n.hasPrefix("pr_") { return prEN[String(n.dropFirst(3))] }
        if n.hasPrefix("p_") { return prEN[String(n.dropFirst(2))] }
        if n.hasPrefix("wx_") { return wxEN[String(n.dropFirst(3))] }
        if n.hasPrefix("hyl"), let y = num(n.dropFirst(3)) { return "\(y) AH" }
        if n.hasPrefix("gyl"), let y = num(n.dropFirst(3)) { return "\(y)" }
        if n.hasPrefix("hy"), let y = num(n.dropFirst(2)) { return "\(y) AH" }
        if n.hasPrefix("gy"), let y = num(n.dropFirst(2)) { return "\(y)" }
        if n.hasPrefix("hm"), let m = num(n.dropFirst(2)), (1...12).contains(m) { return hmEN[m - 1] }
        if n.hasPrefix("gm"), let m = num(n.dropFirst(2)), (1...12).contains(m) { return gmEN[m - 1] }
        if n.hasPrefix("wd"), let i = num(n.dropFirst(2)), (0...6).contains(i) { return wdEN[i] }
        if n.hasPrefix("wl"), let i = num(n.dropFirst(2)), (0...6).contains(i) { return wlEN[i] }
        if n.hasPrefix("pn"), let i = num(n.dropFirst(2)) { return "\(i)" }
        for p in ["dg", "bn", "wm"] where n.hasPrefix(p) {
            if let i = num(n.dropFirst(2)) { return "\(i)" }
        }
        if n.hasPrefix("d"), n.count == 2, let i = num(n.dropFirst(1)), (0...6).contains(i) { return wdEN[i] }
        return nil
    }
}
