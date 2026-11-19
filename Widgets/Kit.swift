import SwiftUI
import WidgetKit
import AppIntents
import UIKit

// MARK: - الألوان والثوابت

/// لون الخط الأساسي: أبيض صافٍ، ثم يُضرب في لون الويدجت المختار فيظهر اللون نفسه تمامًا
/// (كان رماديًا فاتحًا #d6d5d1 فيختلف عن الأرقام البيضاء ويظهر بدرجتين)
let TXT = Color.white
/// الخط الثانوي: الأبيض نفسه بشفافية (لا لون مختلف)، فيبقى بنفس الدرجة في كل أوضاع الشاشة
let DIM = Color.white.opacity(0.68)
let PX: CGFloat = 3              // بكسل لكل نقطة في صور الخط
let LINE_UP: CGFloat = 213       // ارتفاع شريط السطر فوق خط الأساس (بكسل)
let LINE_DN: CGFloat = 110
let YEAR_UP: CGFloat = 117
let GAP_PX: CGFloat = 22
/// علامة النسبة المئوية حسب اللغة والأرقام
var PCT: String { Lang.isEN || Settings.westernDigits ? "%" : "٪" }

// MARK: - صور خط الثلث

/// يعمل داخل امتداد الويدجت (ذاكرته محدودة بنحو ٣٠ م.ب) لا داخل التطبيق
let isWidgetProcess = Bundle.main.bundlePath.hasSuffix(".appex")

enum Calli {
    static let dir: URL = Bundle.main.bundleURL.appendingPathComponent("Calli")
    private static var cache: [String: UIImage] = [:]
    /// حجم الصور المخزنة بالبايت (ذاكرة الويدجت نحو ٣٠ م.ب: نُبقي المخزن تحت ١٢ م.ب)
    private static var bytes = 0

    private static let lock = NSLock()

    /// اختيار الويدجت المعروضة الآن («ميلادي» أو «ميلادي شامي»)، يُقدَّم على إعداد التطبيق
    static var shamiOverride: Bool?
    /// الأشهر الميلادية بأسمائها الشامية؟
    static var shami: Bool { shamiOverride ?? Settings.shamiMonths }

    /// الأشهر الميلادية بأسمائها الشامية (كانون الثاني، شباط…) إن اختيرت
    static func resolve(_ n: String) -> String {
        guard shami, n.hasPrefix("gm"), n.dropFirst(2).first?.isNumber == true else { return n }
        return "gs" + n.dropFirst(2)
    }

    /// صورة الثلث الأصلية كما هي
    static func png(_ name: String) -> UIImage? {
        let n = resolve(name)
        lock.lock(); let c = cache[n]; lock.unlock()
        if let c { return c }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(n + ".png")),
              let img = UIImage(data: data, scale: 3) else { return nil }
        // حد أعلى للذاكرة (ذاكرة الويدجت محدودة): يُفرّغ المخزن إن كبر كثيرًا
        let cost = imageCost(img)
        lock.lock()
        if cache.count >= (isWidgetProcess ? 160 : 4000) || (isWidgetProcess && bytes + cost > 12 << 20) { cache.removeAll(); bytes = 0 }
        cache[n] = img; bytes += cost
        lock.unlock()
        return img
    }

    /// صورة الثلث (مع أسماء الأشهر الشامية إن اختيرت)
    static func ui(_ n: String) -> UIImage? {
        if Lang.isEN, let alt = AltWord.image(n, font: .readex) { return alt }
        if Settings.westernDigits, isNumeric(n), let alt = AltWord.image(n, font: .thuluth) { return alt }
        return png(n)
    }

    /// صور الأرقام (تُرسم بالأرقام الإنجليزية إن اختيرت)
    static func isNumeric(_ n: String) -> Bool {
        for p in ["pn", "dg", "bn", "wm", "hy", "gy"] where n.hasPrefix(p) {
            return n.dropFirst(2).first.map { $0.isNumber || $0 == "l" } ?? false
        }
        return false
    }

    /// الصورة بالخط المختار
    static func img(_ n: String, _ font: WFont) -> UIImage? {
        if font == .thuluth { return ui(n) }
        if Lang.isEN { return AltWord.image(n, font: font.latin ? font : .readex) ?? ui(n) }
        return AltWord.image(n, font: font) ?? ui(n)
    }

    /// هل للصورة نسخة بلا زخرفة (‎_n)؟
    private static var plainCache: [String: Bool] = [:]
    static func hasPlain(_ name: String) -> Bool {
        let n = resolve(name)
        lock.lock(); let c = plainCache[n]; lock.unlock()
        if let c { return c }
        let v = FileManager.default.fileExists(atPath: dir.appendingPathComponent(n + "_n.png").path)
        lock.lock(); plainCache[n] = v; lock.unlock()
        return v
    }

    /// المقاس بالنقاط عند المقياس 1 (= البكسل ÷ 3) — ثابت مهما كان الخط عشان التنسيق
    static func size(_ n: String) -> CGSize { png(n)?.size ?? CGSize(width: 1, height: 1) }
}

struct CImg: View {
    let name: String
    let s: CGFloat
    var opacity: Double = 1
    @Environment(\.wfont) private var wf
    var body: some View {
        // الزخرفة الرمادية للثلث الكبير فقط: تحت هذا المقياس تصير ضجيجًا حول الحروف، فتُستخدم النسخة بلا زخرفة
        // (أيقونات الطقس «ic_» ليست خطًا: نسختها بلا زخرفة تمسح جسم الغيمة الرمادي فتختفي الأيقونة)
        let plain = wf == .thuluth && !Lang.isEN && s < 0.42 && !Calli.isNumeric(name) && !name.hasPrefix("ic_") && Calli.hasPlain(name)
        if let u = Calli.img(plain ? name + "_n" : name, wf) {
            let b = Calli.size(name)
            // قالب (شكل الحرف فقط) بلون الخط نفسه: يطابق الأرقام والنصوص في كل الأوضاع،
            // وفي الشاشة الشفافة/الملوّنة يعامله النظام مثل النص لا مثل صورة باهتة
            Image(uiImage: u).renderingMode(.template).resizable().interpolation(.high)
                .foregroundStyle(TXT)
                .frame(width: b.width * s, height: b.height * s)
                .opacity(opacity)
                .calliLabel(name)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}

extension View {
    /// صورة الخط تُقرأ بنصها لقارئ الشاشة (VoiceOver)؛ والزخرفة بلا نص تُتجاهل
    @ViewBuilder func calliLabel(_ name: String) -> some View {
        if let t = Lang.isEN ? Words.en(name) : Words.text(name) {
            self.accessibilityLabel(Text(verbatim: t))
        } else {
            self.accessibilityHidden(true)
        }
    }
}

/// صورة خط تملأ المكان (اسم اليوم الكبير، اسم الصلاة داخل الحلقة)
struct CArt: View {
    let name: String
    @Environment(\.wfont) private var wf
    var body: some View {
        if let u = Calli.img(name, wf) {
            Image(uiImage: u).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
                .foregroundStyle(TXT)
                .calliLabel(name)
        }
    }
}

extension View {
    /// بداية الحلقة من الأعلى مع عقارب الساعة. الاتجاه العربي يعكس زاوية التدوير
    /// فتبدأ الحلقة من الأسفل، لذلك نثبّت الاتجاه هنا.
    func ringStart() -> some View {
        rotationEffect(.degrees(-90)).environment(\.layoutDirection, .leftToRight)
    }
}

func wOf(_ n: String, _ s: CGFloat) -> CGFloat { Calli.size(n).width * s }
func hOf(_ n: String, _ s: CGFloat) -> CGFloat { Calli.size(n).height * s }
func fitS(_ n: String, _ maxW: CGFloat, _ maxH: CGFloat) -> CGFloat {
    min(maxW / wOf(n, 1), maxH / hOf(n, 1))
}
func Fit(_ n: String, _ maxW: CGFloat, _ maxH: CGFloat, _ op: Double = 1) -> CImg {
    CImg(name: n, s: fitS(n, maxW, maxH), opacity: op)
}
/// اسم صلاة ضمن قائمة: مقياس واحد لكل الصلوات (أصغر مقياس يتسع له أطولها)،
/// فلا يكبر اسم ويصغر آخر في نفس الصف — ومنتصف الليل وحده لأنه أطول بكثير
func PrName(_ key: PKey, _ maxW: CGFloat, _ maxH: CGFloat, _ op: Double = 1) -> CImg {
    let n = "pr_\(key.rawValue)_t"
    if key == .midnight { return Fit(n, maxW * 1.3, maxH, op) }
    // سماحة ٢٥٪ في الارتفاع: «الظهر» أطول الأسماء بحركاته، فلا يصغّر الباقي كثيرًا بسببه
    let s = ["fajr", "sunrise", "dhuhr", "jumuah", "asr", "maghrib", "isha"].map { fitS("pr_\($0)_t", maxW, maxH * 1.25) }.min() ?? fitS(n, maxW, maxH)
    return CImg(name: n, s: s, opacity: op)
}

func lineWidth(_ names: [String], _ gapPx: CGFloat = GAP_PX, _ s: CGFloat) -> CGFloat {
    names.reduce(0) { $0 + wOf($1, s) } + gapPx * s / PX * CGFloat(max(0, names.count - 1))
}

/// سطر خط بترتيب القراءة العربية (أول عنصر يمين)
struct CLine: View {
    let names: [String]
    let s: CGFloat
    var gapPx: CGFloat = GAP_PX
    var body: some View {
        HStack(spacing: gapPx * s / PX) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, n in CImg(name: n, s: s) }
        }
    }
}

// MARK: - الأرقام والعدّادات (خط Hilal Digits)

func digitFont(_ size: CGFloat, bold: Bool, _ font: WFont = .thuluth) -> Font {
    // أرقام الرقعة وتجوّل أصغر من بقية الخطوط بنفس المقاس: نكبّرها لتتساوى بصريًا مع أرقام رفيقي
    if let ps = font.digitsPS {
        let k: CGFloat = font == .ruqaa ? 1.2 : font == .tajawal ? 1.1 : 0.96
        return .custom(ps, fixedSize: size * k)
    }
    return .custom(bold ? "HilalDigits-Bold" : "HilalDigits-Regular", fixedSize: size)
}

/// أرقام الرقعة ترسم أسفل منتصف سطرها بكثير (قياس الخط: مركز الحبر عند ٦٤٪ من السطر لا ٥٠٪)،
/// فتنزل على ما تحتها في الأرقام الكبيرة — نرفعها لتتوسّط مثل بقية الخطوط (رسم فقط، لا يغيّر التنسيق)
func digitLift(_ size: CGFloat, _ font: WFont) -> CGFloat { font == .ruqaa ? -size * 0.2 : 0 }

struct Digits: View {
    let text: String
    let size: CGFloat
    var color: Color = TXT
    var bold: Bool = false
    /// يشيل الفراغ الكبير فوق وتحت الأرقام (سطر الخط أطول بكثير من الأرقام نفسها)
    var tight: Bool = false
    @Environment(\.wfont) private var wf
    var body: some View {
        Text(text).font(digitFont(size, bold: bold, wf)).foregroundStyle(color).lineLimit(1)
            .offset(y: digitLift(size, wf))
            // في الويدجت: الأرقام تتدحرج بنعومة عند كل تحديث بدل أن تقفز
            .contentTransition(.numericText())
            .fixedSize()
            .frame(height: tight ? size * 0.8 : nil)
    }
}

/// حجم الصورة في الذاكرة بعد فكّها (عرض × ارتفاع × ٤ بايت)
func imageCost(_ img: UIImage) -> Int {
    Int(img.size.width * img.scale) * Int(img.size.height * img.scale) * 4
}

/// بادئة العدّاد التنازلي حتى يظهر دائمًا بالساعات: «٠:» تحت الساعة، و«٠:٠» تحت عشر دقائق
func timerPrefix(_ left: TimeInterval) -> String {
    guard left > 0 else { return "" }
    // «<=»: المدخلات على رأس الدقيقة تمامًا (قبل الصلاة بساعة أو عشر دقائق) تبدأ بالبادئة الصحيحة
    if left <= 600 { return ar("0") + ":" + ar("0") }
    if left <= 3600 { return ar("0") + ":" }
    return ""
}

/// عدّاد تنازلي يقف عند الصفر
/// ساعات:دقائق ثابتة — لوضع «الشاشة دائمًا» حيث يخفي النظام الثواني بشرطات
func hmText(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded(.down)))
    return "\(ar(s / 3600)):" + ar((s % 3600) / 60).leftPad2
}
extension String {
    /// يضيف صفرًا عربيًا إن كان رقمًا واحدًا
    var leftPad2: String { count < 2 ? ar("0") + self : self }
}

struct CountDown: View {
    let to: Date
    let size: CGFloat
    var color: Color = .white
    var width: CGFloat = 150
    /// تاريخ مدخل الويدجت — يُستخدم لعرض ثابت في وضع الشاشة الخافتة
    var at: Date? = nil
    @Environment(\.isLuminanceReduced) private var dim
    @Environment(\.wfont) private var wf
    var body: some View {
        let now = Date()
        Group {
            if dim, let at {
                Text(hmText(to.timeIntervalSince(at)))
            } else {
                // أقل من ساعة: النظام يعرض «١٥:٢٤» فتُقرأ كأنها ساعة؛ نضيف الساعات صفرًا «٠:١٥:٢٤»
                // (للويدجت مدخل عند بقاء ساعة و١٠ دقائق ليتبدّل الشكل في وقته)
                Text(verbatim: timerPrefix(to.timeIntervalSince(at ?? now))) + Text(timerInterval: now...max(now, to), countsDown: true)
            }
        }
        .font(digitFont(size, bold: true, wf)).foregroundStyle(color)
        .offset(y: digitLift(size, wf))
        .multilineTextAlignment(.center).frame(width: width)
        .environment(\.layoutDirection, .leftToRight)
        .digitsLocale()
    }
}

/// عدّاد تصاعدي (كم مضى)
struct CountUp: View {
    let from: Date
    let size: CGFloat
    var color: Color = TXT
    var width: CGFloat = 150
    var at: Date? = nil
    @Environment(\.isLuminanceReduced) private var dim
    @Environment(\.wfont) private var wf
    var body: some View {
        Group {
            if dim, let at {
                Text(hmText(at.timeIntervalSince(from)))
            } else {
                Text(timerInterval: from...from.addingTimeInterval(2 * 86400), countsDown: false)
            }
        }
            .font(digitFont(size, bold: true, wf)).foregroundStyle(color)
        .offset(y: digitLift(size, wf))
            .multilineTextAlignment(.center).frame(width: width)
            .environment(\.layoutDirection, .leftToRight)
            .digitsLocale()
    }
}

// MARK: - إعداد الويدجت (المكان + اللون + التقويم)

enum PlaceOpt: String, AppEnum {
    case tr, tl, mr, ml, br, bl
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "المكان"
    static let caseDisplayRepresentations: [PlaceOpt: DisplayRepresentation] = [
        .tr: "الأعلى — يمين", .tl: "الأعلى — يسار",
        .mr: "الوسط — يمين", .ml: "الوسط — يسار",
        .br: "الأسفل — يمين", .bl: "الأسفل — يسار",
    ]
}

enum TintOpt: String, AppEnum {
    case app, auto, white, glass, gold, silver, beige, sky, mint, rose, black
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "الخامة واللون"
    static let caseDisplayRepresentations: [TintOpt: DisplayRepresentation] = [
        .app: "حسب إعدادات التطبيق", .auto: "تلقائي (زجاجي أو أبيض حسب الخلفية)", .white: "أبيض", .glass: "زجاجي", .gold: "ذهبي", .silver: "فضي", .beige: "بيج",
        .sky: "سماوي", .mint: "أخضر", .rose: "وردي", .black: "أسود",
    ]
}

enum CalOpt: String, AppEnum {
    case hijri, gregorian, gregorianShami
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "التقويم"
    static let caseDisplayRepresentations: [CalOpt: DisplayRepresentation] = [.hijri: "هجري", .gregorian: "ميلادي", .gregorianShami: "ميلادي شامي"]
    var isGregorian: Bool { self != .hijri }
    /// أسماء الأشهر لهذه الويدجت: شامية، أو عادية، أو (للهجري) حسب إعداد التطبيق
    var shami: Bool? { self == .gregorianShami ? true : (self == .gregorian ? false : nil) }
}

/// يضبط أسماء الأشهر الميلادية للويدجت المعروضة (شامية أو عادية) قبل رسم محتواها.
/// في عملية الويدجت تُرسم كل ويدجت وحدها، فتضبط كلٌّ منها اختيارها؛ وفي التطبيق يبقى إعداد التطبيق العام
struct ShamiScope<C: View>: View {
    let shami: Bool?
    @ViewBuilder let content: () -> C
    var body: some View {
        if isWidgetProcess { Calli.shamiOverride = shami }
        return content()
    }
}

protocol Positioned {
    var place: PlaceOpt { get }
    var tint: TintOpt { get }
    var isGregorian: Bool { get }
    /// أسماء الأشهر الميلادية لهذه الويدجت (nil = إعداد التطبيق)
    var shamiChoice: Bool? { get }
    var bgOpt: BgOpt { get }
    var fontOpt: FontOpt { get }
    var mediaOpt: String { get }
    /// ويدجت رفيقي بالمقاس: الويدجت المختارة من «تعديل الأداة»
    var designID: String? { get }
}
extension Positioned {
    var mediaOpt: String { "" }
    var designID: String? { nil }
}



// MARK: - المدخلات والجدولة

struct HEntry: TimelineEntry {
    let date: Date
    let slot: Slot
    let size: CGSize
    var tint: Color
    let greg: Bool
    /// أسماء الأشهر الميلادية الشامية لهذه الويدجت (nil = إعداد التطبيق)
    var shami: Bool? = nil
    var weather: WeatherData? = nil
    var preview = false
    /// معروض داخل التطبيق (معرض الويدجتات)
    var inApp = false
    var family: WidgetFamily? = nil
    /// تصميم الويدجت: الخلفية والخط والزخرفة
    var style = WStyle()
    /// معرّف الويدجت (للتصاميم الخاصة بكل نوع)
    var kind = ""
    /// مصدر ويدجت الوسائط (فارغ = الشغّال حاليًا)
    var media = ""
    /// وضع المعايرة ما يطلع في معرض الويدجتات
    var calibrating: Bool { !preview && !inApp && Backdrop.calibrating(at: date) }
}

enum Sched { case day, prayer, minute, weather, media }

struct HProvider<I: WidgetConfigurationIntent & Positioned>: AppIntentTimelineProvider {
    let sched: Sched
    var kind = ""

    /// الويدجت المعروضة: المختارة في «تعديل الأداة»، وإلا الافتراضية
    private func design(_ c: I?) -> String { c?.designID ?? kind }
    private func schedule(_ c: I?) -> Sched { c?.designID.map { Catalog.info($0).sched } ?? sched }

    private func make(_ d: Date, _ c: I?, _ ctx: Context, _ w: WeatherData? = nil) -> HEntry {
        let kind = design(c)
        let slot = Slot.of(place: c?.place.rawValue ?? "mr", medium: ctx.family == .systemMedium,
                           large: ctx.family == .systemLarge)
        var st = Styles.get(kind)
        if let b = c?.bgOpt.kind { st.bg = b }
        if let f = c?.fontOpt.font { st.font = f }
        let tintKey = c?.tint.rawValue ?? "app"
        let tint = tintKey == "app" ? (st.tint.map { Palette.color($0) } ?? Tint.appColor) : Tint.color(tintKey)
        var e = HEntry(date: d, slot: slot, size: ctx.displaySize, tint: tint,
                       greg: c?.isGregorian ?? false, weather: w, preview: ctx.isPreview, family: ctx.family)
        e.style = st
        e.kind = kind
        e.shami = c?.shamiChoice
        e.media = c?.mediaOpt ?? ""
        return e
    }

    func placeholder(in context: Context) -> HEntry {
        make(Date(), nil, context, Weather.cached())
    }

    func snapshot(for configuration: I, in context: Context) async -> HEntry {
        let sched = schedule(configuration)
        let w = sched == .weather ? await Weather.load() : nil
        return make(Date(), configuration, context, w)
    }

    func timeline(for configuration: I, in context: Context) async -> Timeline<HEntry> {
        let sched = schedule(configuration), kind = design(configuration)
        await LocationSync.refreshIfNeeded(inWidget: true)
        await Notify.refreshIfStale()
        let now = Date()
        func e(_ d: Date, _ w: WeatherData? = nil) -> HEntry { make(d, configuration, context, w) }
        // في الوضع التلقائي نعيد الحساب كل ٤٥ دقيقة عشان لو تنقّلت
        let cap = now.addingTimeInterval(45 * 60)
        func pol(_ p: TimelineReloadPolicy, _ end: Date) -> TimelineReloadPolicy {
            Settings.isAuto && end > cap ? .after(cap) : p
        }
        let first = e(now)
        Backdrop.noteSeen(slot: first.slot, size: context.displaySize)

        // وضع المعايرة: لون ثابت لين ينتهي الوقت
        if Backdrop.calibrating(at: now) {
            return Timeline(entries: [first, e(Backdrop.calibUntil.addingTimeInterval(1))], policy: .atEnd)
        }

        let midnight = Cal.nextMidnight(after: now)
        switch sched {
        case .day:
            return Timeline(entries: [first, e(midnight.addingTimeInterval(5))], policy: pol(.atEnd, midnight))
        case .prayer:
            let bounds = Prayer.boundaries(from: now)
            var dates = [now] + bounds.map { $0.addingTimeInterval(1) }
            // تبديل شكل العدّاد عند بقاء ساعة وعشر دقائق («٠:٥٩:٥٩» و«٠:٠٩:٥٩»)
            dates += bounds.flatMap { [$0.addingTimeInterval(-3600 + 0.5), $0.addingTimeInterval(-600 + 0.5)] }.filter { $0 > now }
            if !dates.contains(where: { abs($0.timeIntervalSince(midnight)) < 60 }) { dates.append(midnight.addingTimeInterval(5)) }
            dates.sort()
            return Timeline(entries: dates.map { e($0) }, policy: pol(.after(dates.last ?? midnight), dates.last ?? midnight))
        case .minute:
            // ساعات الإطار تعرض الطقس أيضًا
            let w: WeatherData? = (kind == "hilal.tickbox" || kind == "hilal.tickm") ? await Weather.load() : nil
            let start = Cal.gregCal.dateInterval(of: .minute, for: now)?.start ?? now
            let entries = (0..<60).map { e(start.addingTimeInterval(Double($0) * 60), w) }
            return Timeline(entries: entries, policy: .atEnd)
        case .media:
            // يحدّثها التطبيق عند كل تغيير في التشغيل؛ وأثناء تشغيل مقطع له مدة: مدخل كل ٣٠ ثانية لتتقدّم الحلقات والموجة
            let np = NowPlaying.display(for: configuration.mediaOpt)
            if np.playing && np.duration > 0 {
                let left = max(0, np.duration - np.elapsed(at: now))
                let n = min(60, Int(left / 30))
                let entries = (0...n).map { e(now.addingTimeInterval(Double($0) * 30)) }
                // التحديث التالي بعد آخر مدخل مباشرة (لا يتجمّد التقدّم في المقاطع الأطول من ٣٠ دقيقة)
                return Timeline(entries: entries, policy: .after(now.addingTimeInterval(min(Double(n) * 30 + 30, left + 5))))
            }
            return Timeline(entries: [first], policy: .after(now.addingTimeInterval(3600)))
        case .weather:
            let w = await Weather.load()
            // كل ساعة (ضمن حصة التحديث اليومية)، ومدخلات عند تغيّر الصلاة خلالها (لويدجت الطقس التي تعرض الصلاة القادمة)
            var marks = Prayer.boundaries(from: now, hours: 1).map { $0.addingTimeInterval(1) }
            // وقبل الصلاة بساعة وبعشر دقائق: يتغيّر شكل العدّاد (بادئة «٠:» و«٠:٠»)
            let hourEnd = now.addingTimeInterval(3600)
            for b in Prayer.boundaries(from: now, hours: 2) {
                for m in [b.addingTimeInterval(-3600 + 0.5), b.addingTimeInterval(-600 + 0.5)] where m > now && m < hourEnd { marks.append(m) }
            }
            marks.sort()
            // منتصف الليل خلال الساعة: مدخل جديد يحدّث اسم اليوم والتاريخ في ويدجت الطقس
            let mid = Cal.nextMidnight(after: now).addingTimeInterval(5)
            if mid < now.addingTimeInterval(3600) { marks.append(mid); marks.sort() }
            return Timeline(entries: [e(now, w)] + marks.map { e($0, w) }, policy: .after(now.addingTimeInterval(60 * 60)))
        }
    }
}

// MARK: - الخلفية والإطار

struct WidgetBG: View {
    let entry: HEntry

    /// صورة الخلفية المقصوصة لمكان الويدجت — داخل التطبيق لا صورة: لوح زجاجي (مثل معاينات Glassify)
    private var wall: UIImage? {
        entry.inApp ? nil : Backdrop.image(slot: entry.slot, size: entry.size)
    }

    @ViewBuilder private func wallView(blur: CGFloat = 0) -> some View {
        if let img = wall {
            if #available(iOS 18.0, *) {
                Image(uiImage: img).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
                    .blur(radius: blur, opaque: true)
            } else {
                Image(uiImage: img).resizable().scaledToFill().blur(radius: blur, opaque: true)
            }
        } else {
            GlassPanel()
        }
    }

    var body: some View {
        let st = entry.style
        let k = st.strength
        if entry.calibrating {
            entry.slot.calibColor
        } else {
            switch st.bg {
            case .clear:
                wallView()
            case .glass:
                ZStack {
                    wallView(blur: 10 + 14 * k)
                    LinearGradient(colors: [Color.white.opacity(0.10 + 0.14 * k), Color.white.opacity(0.03 + 0.05 * k)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    ContainerRelativeShape().strokeBorder(Color.white.opacity(0.10 + 0.2 * k), lineWidth: 1)
                }
            case .dark:
                ZStack {
                    wallView(blur: 6 * k)
                    Color.black.opacity(0.25 + 0.55 * k)
                }
            case .color:
                ZStack {
                    wallView()
                    Palette.color(st.color).opacity(0.35 + 0.65 * k)
                }
            case .gradient:
                ZStack {
                    wallView()
                    LinearGradient(colors: Palette.gradient(st.grad), startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(0.35 + 0.65 * k)
                }
            }
        }
    }
}

/// لوح زجاجي مدخّن (رمادي فحمي، أفتح قليلًا من الأعلى، بحافة لامعة رفيعة) — معاينات التطبيق،
/// وخلفية الويدجت إن لم تُضبط مطابقة الخلفية بعد
struct GlassPanel: View {
    var corner: CGFloat? = nil
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.19, green: 0.19, blue: 0.21), Color(red: 0.10, green: 0.10, blue: 0.11)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0)],
                           center: UnitPoint(x: 0.25, y: 0), startRadius: 0, endRadius: 320)
            rim
        }
    }
    @ViewBuilder private var rim: some View {
        let g = LinearGradient(colors: [Color.white.opacity(0.30), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom)
        if let corner {
            RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(g, lineWidth: 1)
        } else {
            ContainerRelativeShape().strokeBorder(g, lineWidth: 1)
        }
    }
}

/// غلاف كل ويدجت: اتجاه عربي + لون الخط + الخلفية المقصوصة.
/// الخلفية مرسومة داخل المحتوى نفسه (مثل سكربت ويدجت) عشان iOS ما يستبدلها بالزجاج في الوضع الداكن.
/// للمراجعة الآلية فقط (CI): رسم المحتوى بلا خلفية لقياس الهوامش
enum RenderDebug { static var bare = false }

struct Root<Content: View>: View {
    let entry: HEntry
    /// ما يفتحه الضغط على الويدجت (الافتراضي: صفحة تصميمها في المعرض)
    var url: URL? = nil
    @ViewBuilder let content: () -> Content
    /// وضع الشاشة الرئيسية «ملوّن» أو «شفاف» (iOS 18 وما بعده): النظام يرسم الزجاج ويلوّن المحتوى بنفسه
    @Environment(\.widgetRenderingMode) private var renderingMode
    var body: some View {
        let ok = entry.size.width > 10 && entry.size.height > 10
        let W: CGFloat? = ok ? entry.size.width : nil, H: CGFloat? = ok ? entry.size.height : nil
        let accented = renderingMode == .accented && !entry.inApp
        ZStack {
            // في الوضع الملوّن/الشفاف لا نرسم صورة الخلفية: لا تطابق الشاشة هناك، والنظام يضع زجاجه
            if !accented && !RenderDebug.bare {
                WidgetBG(entry: entry)
                    .frame(width: W, height: H)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            if !entry.calibrating {
                ZStack {
                    DecoView(kind: entry.style.deco, opacity: entry.style.decoOpacity)
                    content()
                    // الطقس أقدم من ٣ ساعات (بلا إنترنت): نوضح وقت آخر تحديث بدل عرضه كأنه الآن
                    if let w = entry.weather, !entry.inApp, entry.date.timeIntervalSince1970 - w.t > 3 * 3600 {
                        StaleWeatherBadge(updated: Date(timeIntervalSince1970: w.t))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(7)
                    }
                }
                .environment(\.untintIcons, !accented)
                .modifier(TintInk(tint: entry.tint, accented: accented, bright: Tint.isAuto(entry.tint) && !accented && inkBright(entry)))
                .overlayPreferenceValue(UntintedIcons.self) { UntintedOverlay(items: $0) }
                .widgetAccentable(accented)
                .frame(width: W, height: H)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.layoutDirection, Lang.dir)
                .environment(\.wfont, entry.style.font)
                .digitsLocale()
            }
        }
        .frame(width: W, height: H)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .containerBackground(for: .widget) { if RenderDebug.bare { Color.clear } else { WidgetBG(entry: entry) } }
        .widgetURL(entry.inApp ? nil : (url ?? (entry.kind.isEmpty ? nil : URL(string: "miqat://edit/" + entry.kind))))
    }
}

/// لون خط الويدجت: لون عادي بالضرب، أو «زجاجي» محفور، أو «تلقائي» (زجاجي فوق الداكن وأبيض فوق الفاتح)
/// شارة صغيرة بوقت آخر تحديث للطقس (تظهر فقط إذا كانت البيانات قديمة)
struct StaleWeatherBadge: View {
    let updated: Date
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 8, weight: .semibold))
            Text(verbatim: hm12(updated)).font(digitFont(9, bold: true))
        }
        .foregroundStyle(Color.white.opacity(0.7))
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Capsule().fill(Color.black.opacity(0.25)))
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: L("آخر تحديث للطقس") + " " + hm12(updated)))
    }
}

struct TintInk: ViewModifier {
    let tint: Color
    var accented = false
    /// الخلفية تحت الويدجت فاتحة
    var bright = false
    @ViewBuilder func body(content: Content) -> some View {
        if accented {
            content.colorMultiply(tint)
        } else if Tint.isAuto(tint) {
            if bright { content.modifier(LightInk()) } else { content.modifier(GlassInk()) }
        } else if Tint.isGlass(tint) {
            content.modifier(GlassInk())
        } else {
            content.colorMultiply(tint)
        }
    }
}

/// خط زجاجي محفور: جسم شفاف قليلًا، وحافة ضوء رفيعة من الأعلى، وحافة ظل رفيعة من الأسفل —
/// نفس الخامة في الصور المعتمدة. يُطبَّق على المحتوى كله (الحروف والأرقام والعدّاد الحي)،
/// فلا يغيّر حجمًا ولا مكانًا.
struct GlassInk: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            // حافة الظل: الحرف مزاحًا للأسفل ناقص الحرف نفسه
            ZStack {
                content.offset(y: 0.9)
                content.blendMode(.destinationOut)
            }
            .compositingGroup()
            .colorMultiply(.black)
            .opacity(0.55)
            // الجسم: أبيض مائل للزرقة، شفاف قليلًا ليظهر الزجاج خلفه
            content
                .colorMultiply(Color(red: 0.90, green: 0.92, blue: 0.95))
                .opacity(0.8)
            // حافة الضوء من الأعلى
            ZStack {
                content.offset(y: -0.75)
                content.blendMode(.destinationOut)
            }
            .compositingGroup()
            .opacity(0.95)
        }
    }
}

/// أبيض فوق خلفية فاتحة: ظل ناعم يفصل الحرف عن الخلفية فيبقى مقروءًا
struct LightInk: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Color.black.opacity(0.32), radius: 1.6, y: 0.6)
            .shadow(color: Color.black.opacity(0.12), radius: 6)
    }
}

/// هل الخلفية تحت الويدجت فاتحة؟ (للخامة التلقائية) — من صورة الخلفية المقصوصة نفسها
func inkBright(_ e: HEntry) -> Bool {
    if e.inApp || e.calibrating { return false }
    let st = e.style, k = st.strength
    func lum(_ c: [Double]) -> Double { c.count >= 3 ? 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2] : 0 }
    let wall = Backdrop.luminance(slot: e.slot, size: e.size, compute: imageLuminance)
    var v: Double
    switch st.bg {
    case .dark: return false
    case .clear: v = wall ?? 0.15
    case .glass: v = (wall ?? 0.15) * 0.9 + 0.1 * k
    case .color:
        let a = 0.35 + 0.65 * k
        v = lum(st.color) * a + (wall ?? 0.15) * (1 - a)
    case .gradient:
        let g = Palette.gradients[max(0, min(Palette.gradients.count - 1, st.grad))].1
        let a = 0.35 + 0.65 * k
        v = (g.map(lum).reduce(0, +) / Double(max(1, g.count))) * a + (wall ?? 0.15) * (1 - a)
    }
    return v > 0.6
}

/// متوسط إضاءة الصورة ٠…١ (تُصغَّر إلى ٨×٨ أولًا)
func imageLuminance(_ img: UIImage) -> Double? {
    guard let cg = img.cgImage else { return nil }
    let n = 8
    var px = [UInt8](repeating: 0, count: n * n * 4)
    let ok: Bool = px.withUnsafeMutableBytes { raw in
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        return true
    }
    guard ok else { return nil }
    var sum = 0.0
    for i in stride(from: 0, to: px.count, by: 4) {
        sum += 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
    }
    return sum / Double(n * n) / 255
}

/// اسم المدينة: المدينة المنورة بصورة الثلث المزخرفة، وأي مدينة ثانية بخط الثلث نفسه
struct CityLabel: View {
    let maxW: CGFloat
    let maxH: CGFloat
    @Environment(\.wfont) private var wf
    var body: some View {
        if Settings.isMedina && wf == .thuluth {
            Fit("city_t", maxW, maxH)
        } else if !Settings.placeName.isEmpty {
            Text(Settings.placeName)
                .font(.custom(wf.ps, size: maxH * (wf == .thuluth ? 0.95 : 0.7)))
                .foregroundStyle(TXT)
                .lineLimit(1).minimumScaleFactor(0.4)
                .frame(maxWidth: maxW, maxHeight: maxH)
        }
    }
}

// MARK: - الطقس (Open-Meteo)

struct WDay: Codable {
    let t: Double        // بداية اليوم (يونكس)
    let code: Int
    let hi: Double
    let lo: Double
    var rain: Int? = nil // احتمال المطر ٪
}

struct WeatherData: Codable {
    let t: Double
    let temp: Double
    let code: Int
    let day: Int
    let hi: Double?
    let lo: Double?
    var la: Double? = nil
    var lo2: Double? = nil
    var humidity: Int? = nil
    var wind: Double? = nil      // كم/س
    var feels: Double? = nil
    var sunrise: Double? = nil
    var sunset: Double? = nil
    var rain: Int? = nil
    var days: [WDay]? = nil
}

enum Weather {
    static func cached() -> WeatherData? {
        guard let d = AppGroup.defaults.data(forKey: "wx") else { return nil }
        return try? JSONDecoder().decode(WeatherData.self, from: d)
    }

    private static func num(_ x: Any?) -> Double? { (x as? NSNumber)?.doubleValue }
    private static func nums(_ x: Any?) -> [Double] { ((x as? [Any]) ?? []).map { num($0) ?? 0 } }

    static func load() async -> WeatherData? {
        let c = cached()
        if let c, c.days != nil, Date().timeIntervalSince1970 - c.t < 20 * 60,
           abs((c.la ?? Settings.lat) - Settings.lat) < 0.05, abs((c.lo2 ?? Settings.lng) - Settings.lng) < 0.05 { return c }
        // الموقع الدقيق (اختيار صالح: بدون تقريب)
        let s = "https://api.open-meteo.com/v1/forecast?latitude=\(Settings.lat)&longitude=\(Settings.lng)"
            + "&current=temperature_2m,apparent_temperature,weather_code,is_day,relative_humidity_2m,wind_speed_10m"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max"
            + "&forecast_days=7&timezone=auto&timeformat=unixtime"
        guard let url = URL(string: s) else { return c }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cur = j["current"] as? [String: Any],
                  let temp = num(cur["temperature_2m"]) else { return c }
            let daily = j["daily"] as? [String: Any]
            let times = nums(daily?["time"]), codes = nums(daily?["weather_code"])
            let his = nums(daily?["temperature_2m_max"]), los = nums(daily?["temperature_2m_min"])
            let rains = nums(daily?["precipitation_probability_max"])
            var days: [WDay] = []
            for i in 0..<times.count where i < codes.count && i < his.count && i < los.count {
                days.append(WDay(t: times[i], code: Int(codes[i]), hi: his[i], lo: los[i], rain: i < rains.count ? Int(rains[i]) : nil))
            }
            var w = WeatherData(t: Date().timeIntervalSince1970, temp: temp,
                                code: Int(num(cur["weather_code"]) ?? 2), day: Int(num(cur["is_day"]) ?? 1),
                                hi: his.first, lo: los.first, la: Settings.lat, lo2: Settings.lng)
            w.humidity = num(cur["relative_humidity_2m"]).map { Int($0.rounded()) }
            w.wind = num(cur["wind_speed_10m"])
            w.feels = num(cur["apparent_temperature"])
            w.sunrise = nums(daily?["sunrise"]).first
            w.sunset = nums(daily?["sunset"]).first
            w.rain = rains.first.map { Int($0) }
            w.days = days
            if let d = try? JSONEncoder().encode(w) { AppGroup.defaults.set(d, forKey: "wx") }
            return w
        } catch {
            return c
        }
    }

    /// سرعة الرياح حسب الوحدة المختارة
    static func windText(_ w: WeatherData?) -> String {
        guard let v = w?.wind else { return "--" }
        return Settings.windMS ? ar(Int((v / 3.6).rounded())) + " " + L("م/ث") : ar(Int(v.rounded())) + " " + L("كم/س")
    }

    static func iconFor(code: Int, day: Bool = true) -> String {
        let k = key(code)
        if k == "clear" || k == "partly" { return "ic_\(k)_\(day ? "d" : "n")" }
        return "ic_\(k)"
    }

    static func key(_ code: Int) -> String {
        switch code {
        case 0, 1: return "clear"
        case 2: return "partly"
        case 3: return "cloudy"
        case 45, 48: return "fog"
        case 51...57: return "drizzle"
        case 61...67, 80...82: return "rain"
        case 71...77, 85, 86: return "snow"
        case 95...: return "thunder"
        default: return "partly"
        }
    }

    /// بلا بيانات طقس: لا أيقونة (بدل غيمة توحي بطقس غير حقيقي)
    static func icon(_ w: WeatherData?) -> String {
        guard let w else { return "ic_none" }
        let k = key(w.code)
        if k == "clear" || k == "partly" { return "ic_\(k)_\(w.day == 1 ? "d" : "n")" }
        return "ic_\(k)"
    }

    static func word(_ w: WeatherData?) -> String { "wx_\(w.map { key($0.code) } ?? "none")_t" }

    static func deg(_ v: Double?) -> String {
        v.map { ar(Int((Settings.fahrenheit ? $0 * 9 / 5 + 32 : $0).rounded())) + "°" } ?? "--"
    }
}


/// صورة بألوانها الأصلية حتى في وضع الويدجت الملوّن
struct SImage: View {
    let img: UIImage
    var body: some View {
        if #available(iOS 18.0, *) {
            Image(uiImage: img).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFit()
        } else {
            Image(uiImage: img).resizable().scaledToFit()
        }
    }
}

/// «ص» أو «م» (فارغ في نظام ٢٤ ساعة)
func ampmText(_ d: Date) -> String {
    if Settings.use24h { return "" }
    let am = Cal.gregCal.component(.hour, from: d) < 12
    return Lang.isEN ? (am ? "AM" : "PM") : (am ? "ص" : "م")
}
