import SwiftUI
import WidgetKit
import AppIntents

// الويدجت الجديدة المستوحاة من المراجع (اقتباسات، تسبيح بالإحصائيات، اليوم والساعة، ساعة النقش،
// الطقس الكبير، كبسولات الصلاة) — بنفس نظام التصميم R2

private let SMALL3 = CGSize(width: 170, height: 170)
private let MEDIUM3 = CGSize(width: 364, height: 170)
private let LARGE3 = CGSize(width: 364, height: 382)

/// اسم اليوم المختصر (للأعمدة الضيقة)
private func wdShort(_ i: Int) -> String {
    let ar = ["أحد", "اثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة", "سبت"]
    let en = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    return (Lang.isEN ? en : ar)[max(0, min(6, i))]
}

/// سطح زجاجي داخلي (بطاقة داخل الويدجت): تعبئة خفيفة وحافة أفتح من أعلى
private struct Glass3: ViewModifier {
    var corner: CGFloat = 14
    var on = true
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.white.opacity(on ? 0.2 : 0.075)))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(LinearGradient(colors: [Color.white.opacity(0.24), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8))
    }
}
private extension View {
    func glass3(_ corner: CGFloat = 14, on: Bool = false) -> some View { modifier(Glass3(corner: corner, on: on)) }
}

// ═══════════════════════════ الاقتباسات

enum Quotes {
    struct Q { let text: String; let source: String }
    static let cats = ["القرآن", "الحديث", "الأذكار", "الشعر"]
    static let icons = ["book.closed", "text.quote", "hands.sparkles", "pencil.and.scribble"]

    static let hadith: [Q] = [
        Q(text: "إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ، وَإِنَّمَا لِكُلِّ امْرِئٍ مَا نَوَى", source: "متفق عليه"),
        Q(text: "الْكَلِمَةُ الطَّيِّبَةُ صَدَقَةٌ", source: "متفق عليه"),
        Q(text: "مَنْ كَانَ يُؤْمِنُ بِاللَّهِ وَالْيَوْمِ الآخِرِ فَلْيَقُلْ خَيْرًا أَوْ لِيَصْمُتْ", source: "متفق عليه"),
        Q(text: "لَا يُؤْمِنُ أَحَدُكُمْ حَتَّى يُحِبَّ لِأَخِيهِ مَا يُحِبُّ لِنَفْسِهِ", source: "متفق عليه"),
        Q(text: "تَبَسُّمُكَ فِي وَجْهِ أَخِيكَ لَكَ صَدَقَةٌ", source: "رواه الترمذي"),
        Q(text: "أَحَبُّ الأَعْمَالِ إِلَى اللَّهِ أَدْوَمُهَا وَإِنْ قَلَّ", source: "متفق عليه"),
        Q(text: "خَيْرُكُمْ مَنْ تَعَلَّمَ الْقُرْآنَ وَعَلَّمَهُ", source: "رواه البخاري"),
        Q(text: "الْمُسْلِمُ مَنْ سَلِمَ الْمُسْلِمُونَ مِنْ لِسَانِهِ وَيَدِهِ", source: "متفق عليه"),
        Q(text: "لَيْسَ الشَّدِيدُ بِالصُّرَعَةِ، إِنَّمَا الشَّدِيدُ الَّذِي يَمْلِكُ نَفْسَهُ عِنْدَ الْغَضَبِ", source: "متفق عليه"),
        Q(text: "مَنْ سَلَكَ طَرِيقًا يَلْتَمِسُ فِيهِ عِلْمًا سَهَّلَ اللَّهُ لَهُ بِهِ طَرِيقًا إِلَى الْجَنَّةِ", source: "رواه مسلم"),
        Q(text: "اتَّقِ اللَّهَ حَيْثُمَا كُنْتَ، وَأَتْبِعِ السَّيِّئَةَ الْحَسَنَةَ تَمْحُهَا، وَخَالِقِ النَّاسَ بِخُلُقٍ حَسَنٍ", source: "رواه الترمذي"),
        Q(text: "الطُّهُورُ شَطْرُ الإِيمَانِ", source: "رواه مسلم"),
    ]

    static let poetry: [Q] = [
        Q(text: "عَلى قَدرِ أَهلِ العَزمِ تَأتي العَزائِمُ\nوَتَأتي عَلى قَدرِ الكِرامِ المَكارِمُ", source: "المتنبي"),
        Q(text: "إِذا غامَرتَ في شَرَفٍ مَرومِ\nفَلا تَقنَع بِما دونَ النُجومِ", source: "المتنبي"),
        Q(text: "ما كُلُّ ما يَتَمَنّى المَرءُ يُدرِكُهُ\nتَجري الرِياحُ بِما لا تَشتَهي السُفُنُ", source: "المتنبي"),
        Q(text: "دَعِ الأَيّامَ تَفعَلُ ما تَشاءُ\nوَطِب نَفساً إِذا حَكَمَ القَضاءُ", source: "الإمام الشافعي"),
        Q(text: "نَعيبُ زَمانَنا وَالعَيبُ فينا\nوَما لِزَمانِنا عَيبٌ سِوانا", source: "الإمام الشافعي"),
        Q(text: "وَلَرُبَّ نازِلَةٍ يَضيقُ لَها الفَتى\nذَرعاً وَعِندَ اللَهِ مِنها المَخرَجُ", source: "الإمام الشافعي"),
        Q(text: "السَيفُ أَصدَقُ إِنباءً مِنَ الكُتُبِ\nفي حَدِّهِ الحَدُّ بَينَ الجِدِّ وَاللَعِبِ", source: "أبو تمام"),
        Q(text: "وَمَهما تَكُن عِندَ امرِئٍ مِن خَليقَةٍ\nوَإِن خالَها تَخفى عَلى الناسِ تُعلَمِ", source: "زهير بن أبي سلمى"),
    ]

    static func list(_ cat: Int) -> [Q] {
        switch cat {
        case 0: return Verses.list.map { Q(text: $0.0, source: $0.1) }
        case 1: return hadith
        case 2: return (Adhkar.morning + Adhkar.general).map { Q(text: $0.text, source: $0.source) }
        default: return poetry
        }
    }

    private static var d: UserDefaults { AppGroup.defaults }
    static var cat: Int { max(0, min(3, d.integer(forKey: "quote_cat"))) }
    /// اقتباس اليوم (يتغيّر يوميًا، والضغط ينقل للتالي)
    static func current(_ now: Date) -> Q {
        let l = list(cat)
        // رقم اليوم بتقويم الجوال (لا بأيام UTC): يتغيّر الاقتباس عند منتصف الليل المحلي، ويطابق التطبيق
        let day = Cal.gregCal.ordinality(of: .day, in: .era, for: now) ?? Int(now.timeIntervalSince1970 / 86400)
        let i = day + d.integer(forKey: "quote_off")
        return l[((i % l.count) + l.count) % l.count]
    }
    static func setCat(_ c: Int) { d.set(c, forKey: "quote_cat"); d.set(0, forKey: "quote_off") }
    static func next() { d.set(d.integer(forKey: "quote_off") + 1, forKey: "quote_off") }
}

struct QuoteCatIntent: AppIntent {
    static let title: LocalizedStringResource = "تصنيف الاقتباس"
    static let isDiscoverable = false
    @Parameter(title: "التصنيف") var cat: Int
    init() {}
    init(cat: Int) { self.cat = cat }
    func perform() async throws -> some IntentResult { Quotes.setCat(cat); return .result() }
}

struct QuoteNextIntent: AppIntent {
    static let title: LocalizedStringResource = "الاقتباس التالي"
    static let isDiscoverable = false
    init() {}
    func perform() async throws -> some IntentResult { Quotes.next(); return .result() }
}

/// القرآن ٦ — اقتباسات (متوسط وكبير): النص بخط النسخ، وأزرار التصنيف أسفلها
struct R3QuoteView: View {
    let entry: HEntry
    var body: some View {
        let big = entry.family == .systemLarge || (entry.family == nil && entry.size.height > 300)
        let sz = dims(entry, big ? LARGE3 : MEDIUM3)
        let q = Quotes.current(entry.date)
        let cat = Quotes.cat
        Root(entry: entry) {
            VStack(spacing: big ? 12 : 8) {
                Button(intent: QuoteNextIntent()) {
                    VStack(spacing: 6) {
                        Text(verbatim: q.text)
                            .font(.custom("Amiri-Bold", size: big ? 24 : 17))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineSpacing(big ? 6 : 2)
                            .minimumScaleFactor(0.55)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        T2(text: "— " + q.source, size: big ? 12.5 : 10.5)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, big ? 8 : 4)
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        Button(intent: QuoteCatIntent(cat: i)) {
                            HStack(spacing: 4) {
                                if big { Image(systemName: Quotes.icons[i]).font(.system(size: 11, weight: .semibold)) }
                                Text(verbatim: L(Quotes.cats[i])).font(R2.font(big ? 13 : 12, i == cat ? .bold : .medium))
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(Color.white.opacity(i == cat ? 1 : 0.6))
                            .frame(maxWidth: .infinity).frame(height: big ? 38 : 30)
                            .glass3(big ? 12 : 10, on: i == cat)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, big ? 18 : 12).padding(.bottom, 12)
            .frame(width: sz.width, height: sz.height)
        }
    }
}

// ═══════════════════════════ المسبحة بالإحصائيات

enum Tasbih {
    private static var d: UserDefaults { AppGroup.defaults }
    static func dayKey(_ t: Date) -> String {
        let c = Cal.gregCal.dateComponents([.year, .month, .day], from: t)
        // بأصفار حتى يكون الترتيب النصي ترتيبًا زمنيًا (حذف الأيام الأقدم)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static var count: Int { d.integer(forKey: "tsb_now") }
    static var days: [String: Int] { (d.dictionary(forKey: "tsb_days") as? [String: Int]) ?? [:] }
    static func plus(_ now: Date = Date()) {
        d.set(count + 1, forKey: "tsb_now")
        var m = days
        m[dayKey(now), default: 0] += 1
        // نحتفظ بآخر ٦٠ يومًا فقط
        if m.count > 60 { for k in m.keys.sorted().prefix(m.count - 60) { m.removeValue(forKey: k) } }
        d.set(m, forKey: "tsb_days")
    }
    static func reset() { d.set(0, forKey: "tsb_now") }
    /// آخر سبعة أيام (الأقدم أولًا) مع مجموعها
    static func week(_ now: Date) -> [(day: Date, n: Int)] {
        let m = days
        return (0..<7).reversed().map { k in
            let t = Cal.gregCal.date(byAdding: .day, value: -k, to: now) ?? now
            return (t, m[dayKey(t)] ?? 0)
        }
    }
}

struct TasbihPlusIntent: AppIntent {
    static let title: LocalizedStringResource = "تسبيحة"
    static let isDiscoverable = false
    init() {}
    func perform() async throws -> some IntentResult { Tasbih.plus(); return .result() }
}

struct TasbihResetIntent: AppIntent {
    static let title: LocalizedStringResource = "تصفير العدّاد"
    static let isDiscoverable = false
    init() {}
    func perform() async throws -> some IntentResult { Tasbih.reset(); return .result() }
}

/// زر دائري صغير بأيقونة
private struct RoundIcon: View {
    let icon: String
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: icon).font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.75))
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(0.12)))
            .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.6))
    }
}

/// القرآن ٧ — المسبحة (صغير)، والقرآن ٨ — المسبحة وإحصائيات الأسبوع (كبير)
struct R3TasbihView: View {
    let entry: HEntry
    var body: some View {
        let big = entry.family == .systemLarge || (entry.family == nil && entry.size.height > 300)
        let sz = dims(entry, big ? LARGE3 : SMALL3)
        let n = Tasbih.count
        Root(entry: entry) {
            VStack(spacing: 0) {
                ZStack {
                    T2(text: L("المسبحة"), size: big ? 14 : 12)
                    HStack {
                        Button(intent: TasbihResetIntent()) { RoundIcon(icon: "arrow.counterclockwise", size: big ? 32 : 28) }
                            .buttonStyle(.plain)
                        Spacer()
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
                GradDigits(text: R2.num(n), size: big ? 70 : 50)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(height: big ? 78 : 56)
                    .padding(.top, big ? 4 : 2)
                Button(intent: TasbihPlusIntent()) {
                    Image(systemName: "plus").font(.system(size: big ? 24 : 20, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(maxWidth: .infinity).frame(height: big ? 46 : 38)
                        .glass3(big ? 23 : 14)
                }
                .buttonStyle(.plain)
                .padding(.top, big ? 8 : 6)
                if big {
                    WeekBars(date: entry.date).padding(.top, 14)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(big ? 16 : 12)
            .frame(width: sz.width, height: sz.height)
        }
    }
}

/// أعمدة الأسبوع: اليوم أفتح، والرقم فوق كل عمود
private struct WeekBars: View {
    let date: Date
    var body: some View {
        let w = Tasbih.week(date)
        let mx = max(1, w.map { $0.n }.max() ?? 1)
        VStack(spacing: 8) {
            HStack {
                Text(verbatim: L("إحصائيات الأسبوع")).font(R2.font(14, .bold)).foregroundStyle(.white)
                Spacer()
                T2(text: L("المجموع") + ": " + R2.num(w.reduce(0) { $0 + $1.n }), size: 12)
            }
            GeometryReader { g in
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(w.enumerated()), id: \.offset) { i, it in
                        let today = i == w.count - 1
                        VStack(spacing: 4) {
                            if it.n > 0 { T2(text: R2.num(it.n), size: 10.5, op: today ? 1 : R2.dim) }
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(today ? 0.85 : 0.32))
                                .frame(height: max(5, (g.size.height - 34) * CGFloat(it.n) / CGFloat(mx)))
                            Text(verbatim: wdShort(Cal.weekday(it.day))).font(R2.font(10.5, today ? .bold : .medium))
                                .foregroundStyle(Color.white.opacity(today ? 1 : R2.past))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(12)
        .glass3(14)
    }
}

// ═══════════════════════════ اليوم والساعة خلفه

/// التاريخ ٩ — اليوم والساعة (متوسط): اسم اليوم بالثلث فوق ساعة رقمية خافتة بتدرّج، ومواقيت اليوم
struct R3DayClockView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date, sz = dims(entry, MEDIUM3)
        let st = Prayer.state(at: d)
        Root(entry: entry) {
            VStack(spacing: 0) {
                T2(text: R2.gregLine(d) + "  |  " + R2.hijriLine(d), size: 12)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.top, 10)
                ZStack {
                    // الساعة خلف الخط: تتلاشى للأسفل حتى لا تنافس اسم اليوم
                    Text(verbatim: hm12(d))
                        .font(digitFont(58, bold: true))
                        .foregroundStyle(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.06)],
                                                        startPoint: .top, endPoint: .bottom))
                        .environment(\.layoutDirection, .leftToRight)
                    Fit("wd\(Cal.weekday(d))_t", sz.width * 0.5, 54)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                .frame(height: 56)
                PrayerRow2(date: d, nameH: 17, timeSize: 13.5, colW: (sz.width - 24) / 6)
                    .padding(.horizontal, 12)
                Hair2().padding(.horizontal, 18).padding(.top, 5)
                LeftLine2(next: st.next, at: d, size: 12.5)
                    .padding(.top, 4)
                Spacer(minLength: 0)
            }
        }
    }
}

// ═══════════════════════════ ساعة النقش

/// الساعة ٤ — ساعة النقش (صغير): حلقة مخطوطة بالثلث خلف العقارب، والعبارة تتغيّر كل يوم
struct R3NaqshView: View {
    let entry: HEntry
    var body: some View {
        let ring = "ring\(Cal.weekday(entry.date) % 3 + 1)"
        Root(entry: entry) {
            GeometryReader { g in
                let s = min(g.size.width, g.size.height) - 16
                let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
                ZStack {
                    if let img = Calli.png(ring) {
                        Image(uiImage: img).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
                            .foregroundStyle(Color.white.opacity(0.34))
                            .accessibilityHidden(true)
                            .frame(width: s * 0.98, height: s * 0.98)
                            .position(c)
                    }
                    // علامات الساعات: الأربع الكبرى أطول
                    ForEach(0..<12, id: \.self) { i in
                        let major = i % 3 == 0
                        Capsule().fill(Color.white.opacity(major ? 0.92 : 0.45))
                            .frame(width: major ? 2.4 : 1.4, height: major ? 11 : 6)
                            .offset(y: -(s / 2 - (major ? 5.5 : 3)))
                            .rotationEffect(.degrees(Double(i) * 30))
                            .position(c)
                    }
                    ClockHands(size: s * 0.86, inApp: entry.inApp, date: entry.date).position(c)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
        }
    }
}

// ═══════════════════════════ الطقس الكبير

private func tmp3(_ v: Double?) -> String {
    guard let v else { return "--" }
    return R2.num(Int((Settings.fahrenheit ? v * 9 / 5 + 32 : v).rounded()))
}

/// الطقس ٤ — الطقس الكامل (كبير): بطاقة زجاجية بالحرارة والشروق والغروب، ثم المطر والرطوبة والرياح، ثم سبعة أيام
struct R3WeatherBigView: View {
    let entry: HEntry
    var body: some View {
        let w = entry.weather, d = entry.date
        let days = Array((w?.days ?? []).prefix(7))
        Root(entry: entry) {
            VStack(spacing: 10) {
                // البطاقة العلوية
                VStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            T2(text: R2.weekday(Cal.weekday(d)) + "، " + R2.time(d), size: 11.5)
                            HStack(alignment: .top, spacing: 1) {
                                GradDigits(text: tmp3(w?.temp), size: 46)
                                Text(verbatim: "°").font(digitFont(22, bold: true)).foregroundStyle(.white)
                            }
                            .environment(\.layoutDirection, .leftToRight)
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill").font(.system(size: 9))
                                Text(verbatim: Settings.placeName).font(R2.font(11.5, .bold))
                            }
                            .foregroundStyle(Color.white.opacity(R2.dim))
                        }
                        Spacer(minLength: 4)
                        VStack(spacing: 2) {
                            CImg(name: Weather.icon(w), s: 0.34)
                            Fit(Weather.word(w), 120, 26).frame(height: 26)
                        }
                    }
                    SunBar(w: w, now: d)
                }
                .padding(12)
                .glass3(18)
                // المطر والرطوبة والرياح
                HStack(spacing: 6) {
                    chip("cloud.rain", (w?.rain ?? w?.days?.first?.rain).map { R2.num($0) + PCT } ?? "--")
                    chip("humidity", w?.humidity.map { R2.num($0) + PCT } ?? "--")
                    chip("wind", Weather.windText(w))
                }
                // الأيام
                HStack(spacing: 5) {
                    if days.isEmpty {
                        T2(text: L("غير متوفر"), size: 12).frame(maxWidth: .infinity)
                    }
                    ForEach(Array(days.enumerated()), id: \.offset) { i, dd in
                        let day = Date(timeIntervalSince1970: dd.t)
                        VStack(spacing: 5) {
                            Text(verbatim: i == 0 ? L("اليوم") : wdShort(Cal.weekday(day)))
                                .font(R2.font(10.5, i == 0 ? .bold : .medium)).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            CImg(name: Weather.iconFor(code: dd.code), s: 0.17)
                            Digits(text: tmp3(dd.hi) + "°", size: 13, color: .white, bold: true)
                            Digits(text: tmp3(dd.lo) + "°", size: 11.5, color: Color.white.opacity(R2.past))
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .glass3(14, on: i == 0)
                    }
                }
            }
            .padding(12)
        }
    }

    private func chip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(verbatim: text).font(R2.font(12, .bold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.white.opacity(0.85))
        .frame(maxWidth: .infinity).frame(height: 28)
        .glass3(14)
    }
}

/// شريط الشروق ← طول النهار ← الغروب، والشمس عند موضعها الآن
private struct SunBar: View {
    let w: WeatherData?
    let now: Date
    var body: some View {
        let rise = w?.sunrise.map { Date(timeIntervalSince1970: $0) } ?? Prayer.dayTimes(now)[1].time
        let set = w?.sunset.map { Date(timeIntervalSince1970: $0) } ?? Prayer.dayTimes(now)[4].time
        let len = max(0, set.timeIntervalSince(rise))
        let p = len > 0 ? min(1, max(0, now.timeIntervalSince(rise) / len)) : 0
        let hrs = Int(len / 3600), mins = Int(len.truncatingRemainder(dividingBy: 3600) / 60)
        HStack(spacing: 6) {
            Image(systemName: "sunrise.fill").font(.system(size: 11))
            Text(verbatim: R2.time(rise)).font(R2.font(11, .bold))
            GeometryReader { g in
                ZStack(alignment: Lang.isEN ? .leading : .trailing) {
                    Line3().stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(height: 1).frame(maxHeight: .infinity)
                    Capsule().fill(Color.white.opacity(0.75)).frame(width: max(0, g.size.width * p), height: 1.6)
                        .frame(maxHeight: .infinity)
                    if p > 0 && p < 1 {
                        Circle().fill(Color.white).frame(width: 7, height: 7)
                            .shadow(color: .white.opacity(0.6), radius: 3)
                            .offset(x: (Lang.isEN ? 1 : -1) * (g.size.width * p - 3.5))
                            .frame(maxHeight: .infinity)
                    }
                    Text(verbatim: R2.num(hrs) + " " + L("س") + " " + R2.num(mins) + " " + L("د"))
                        .font(R2.font(10, .bold)).foregroundStyle(Color.white.opacity(R2.dim))
                        .padding(.horizontal, 5)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 16)
            Text(verbatim: R2.time(set)).font(R2.font(11, .bold))
            Image(systemName: "sunset.fill").font(.system(size: 11))
        }
        .foregroundStyle(Color.white.opacity(0.85))
        .padding(.horizontal, 10).frame(height: 30)
        .glass3(15)
    }
}

private struct Line3: Shape {
    func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p }
}

// ═══════════════════════════ كبسولات الصلاة

private func prayerIcon(_ k: PKey) -> String {
    switch k {
    case .fajr: return "sun.haze.fill"
    case .sunrise: return "sunrise.fill"
    case .dhuhr, .jumuah: return "sun.max.fill"
    case .asr: return "cloud.sun.fill"
    case .maghrib: return "sunset.fill"
    default: return "moon.stars.fill"
    }
}

/// الصلاة ٨ — كبسولات الصلاة (متوسط): ست كبسولات بأيقونة، والقادمة دائرة بيضاء مضيئة
struct R3CapsulesView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date, sz = dims(entry, MEDIUM3)
        let times = Prayer.dayTimes(d)
        let st = Prayer.state(at: d)
        let colW = (sz.width - 24 - 5 * 6) / 6
        Root(entry: entry) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(Array(times.enumerated()), id: \.offset) { _, t in
                        let on = abs(t.time.timeIntervalSince(st.next.time)) < 60
                        VStack(spacing: 6) {
                            Image(systemName: prayerIcon(t.key))
                                .font(.system(size: 15, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.white.opacity(on ? 1 : 0.8))
                                .frame(height: 22).padding(.top, 10)
                            Spacer(minLength: 0)
                            VStack(spacing: 1) {
                                Text(verbatim: R2.prayer(t.key)).font(R2.font(10.5, .bold))
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                Text(verbatim: hm12(t.time)).font(digitFont(11.5, bold: true))
                                    .lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .foregroundStyle(on ? Color.black : Color.white)
                            .frame(width: colW - 6, height: colW - 6)
                            .background(Circle().fill(on ? Color.white : Color.white.opacity(0.1)))
                            .overlay(Circle().stroke(Color.white.opacity(on ? 0 : 0.16), lineWidth: 0.8))
                            .shadow(color: on ? Color.white.opacity(0.35) : .clear, radius: 6)
                            .padding(.bottom, 3)
                        }
                        .frame(width: colW)
                        .glass3(colW / 2)
                    }
                }
                .frame(maxHeight: .infinity)
                LeftLine2(next: st.next, at: d, size: 12)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 9)
        }
    }
}
