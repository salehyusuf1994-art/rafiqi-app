import SwiftUI
import WidgetKit

// MARK: - ويدجتات شاشة القفل (لون واحد شفاف — يتبع لون ساعة القفل)

let HM_NAMES = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة",
                "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
let PR_NAMES: [PKey: String] = [.fajr: "الفجر", .sunrise: "الشروق", .dhuhr: "الظهر", .jumuah: "الجمعة",
                                .asr: "العصر", .maghrib: "المغرب", .isha: "العشاء", .midnight: "منتصف الليل"]

/// غلاف ويدجت شاشة القفل: اتجاه عربي + بدون خلفية
struct LockRoot<Content: View>: View {
    var circle = false
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.layoutDirection, Lang.dir)
            .environment(\.wfont, Styles.lockFont)
            .digitsLocale()
            .containerBackground(for: .widget) {
                if circle { AccessoryWidgetBackground() } else { Color.clear }
            }
    }
}

// ── مستطيل: الصلاة القادمة + العدّاد ──
struct LockNextView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.prevNext(at: entry.date)
        LockRoot {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    PrIcon(key: st.next.key, size: 15, color: .white)
                    Fit("pr_\(st.next.key.rawValue)_t", st.next.key == .midnight ? 96 : 76, 30)
                    Digits(text: hm12(st.next.time), size: 15, color: .white)
                }
                HStack(spacing: 6) {
                    Fit("lbl_left_t", 40, 24)
                    CountDown(to: st.next.time, size: 25, color: .white, width: 112, at: entry.date)
                        .widgetAccentable()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// ── مستطيل: السابقة والقادمة ──
struct LockPrevNextView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.prevNext(at: entry.date)
        LockRoot {
            VStack(alignment: .leading, spacing: 3) {
                row(st.prev, "lbl_ago_t", up: true)
                row(st.next, "lbl_left_t", up: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    func row(_ p: PTime, _ lbl: String, up: Bool) -> some View {
        // «مضى» و«باقي» أكبر قليلًا وأوضح (كانت تضيع بين اسم الصلاة والعدّاد)؛ والعرض الكلي كما هو
        HStack(spacing: 3) {
            Fit("pr_\(p.key.rawValue)_t", p.key == .midnight ? 62 : 52, 26)
                .frame(width: 54, alignment: .leading)
            Fit(lbl, 36, 22)
            Group {
                if up { CountUp(from: p.time, size: 19, color: .white, width: 76, at: entry.date) }
                else { CountDown(to: p.time, size: 19, color: .white, width: 76, at: entry.date) }
            }
            .widgetAccentable()
        }
    }
}

// ── مستطيل: التاريخ الهجري (اليوم) الشهر وتحته السنة ──
struct LockHijriView: View {
    let entry: HEntry
    var greg = false
    var body: some View {
        let h = Cal.dmy(entry.date, greg: greg)
        let names = ["pn\(h.d)", (greg ? "gm" : "hm") + "\(h.m)"]
        let s = min(0.5, 168 / lineWidth(names, GAP_PX, 1))
        let year = greg ? "gy\(clampY(h.y, 2020, 2050))" : "hy\(clampY(h.y, 1440, 1470))"
        LockRoot {
            VStack(spacing: -(LINE_DN + LINE_UP) * s / PX * 0.12) {
                CLine(names: names, s: s)
                CImg(name: year, s: s * 0.62)
            }
        }
    }
}

// ── مستطيل: اسم اليوم + التاريخ ──
struct LockDayDateView: View {
    let entry: HEntry
    var greg = false
    var body: some View {
        let h = Cal.dmy(entry.date, greg: greg)
        let names = greg ? ["pn\(h.d)", "gm\(h.m)", "gyl\(clampY(h.y, 2020, 2050))"]
                         : ["pn\(h.d)", "hm\(h.m)", "hyl\(clampY(h.y, 1440, 1470))"]
        LockRoot {
            VStack(spacing: -4) {
                Fit("wd\(Cal.weekday(entry.date))_t", 130, 40)
                CLine(names: names, s: min(0.4, 168 / lineWidth(names, GAP_PX, 1)))
            }
        }
    }
}

// ── مستطيل: مواقيت اليوم — القادمة مع العدّاد، وتحتها الصلوات الخمس ──
struct LockDayPrayersView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.prevNext(at: entry.date)
        let today = Prayer.dayTimes(entry.date)
        let tomorrow = Cal.gregCal.date(byAdding: .day, value: 1, to: entry.date) ?? entry.date
        let list = ((today.last?.time ?? entry.date) < entry.date ? Prayer.dayTimes(tomorrow) : today)
            .filter { $0.key != .sunrise }
        let hd = Cal.dmy(entry.date, greg: false).d
        LockRoot {
            VStack(spacing: 1) {
                HStack(spacing: 5) {
                    Fit("pr_\(st.next.key.rawValue)_t", st.next.key == .midnight ? 62 : 50, 22)
                    CountDown(to: st.next.time, size: 17, color: .white, width: 70, at: entry.date)
                        .widgetAccentable()
                    Spacer(minLength: 0)
                    Digits(text: ar(hd), size: 12, color: .white, bold: true, tight: true)
                        .frame(width: 21, height: 21)
                        .background(Circle().fill(Color.white.opacity(0.22)))
                }
                HStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { _, p in
                        let on = p.key == st.next.key
                        VStack(spacing: 0) {
                            PrIcon(key: p.key, size: 10, color: .white)
                            PrName(p.key, 31, 16)
                            Digits(text: hm12(p.time), size: 11, color: .white, bold: on)
                        }
                        .opacity(on ? 1 : 0.72)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// ── دائرة: رقم اليوم الهجري والشهر ──
struct LockDayCircle: View {
    let entry: HEntry
    var greg = false
    var body: some View {
        let h = Cal.dmy(entry.date, greg: greg)
        LockRoot(circle: true) {
            VStack(spacing: -2) {
                Digits(text: ar(h.d), size: 30, color: .white, bold: true, tight: true)
                    .widgetAccentable()
                Fit((greg ? "gm" : "hm") + "\(h.m)_t", 60, 24)
            }
        }
    }
}

// ── دائرة: الصلاة القادمة مع حلقة التقدّم ──
struct LockPrayerCircle: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.prevNext(at: entry.date)
        LockRoot(circle: true) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 4).padding(3)
                Circle().trim(from: 0, to: max(0.01, st.progress))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .ringStart().padding(3)
                    .widgetAccentable()
                VStack(spacing: -1) {
                    Fit("pr_\(st.next.key.rawValue)_t", st.next.key == .midnight ? 52 : 46, 25)
                    Digits(text: hm12(st.next.time), size: 13, color: .white, bold: true)
                }
            }
        }
    }
}

// ── دائرة: اسم اليوم ──
struct LockWeekdayCircle: View {
    let entry: HEntry
    var body: some View {
        LockRoot(circle: true) {
            Fit("wd\(Cal.weekday(entry.date))_t", 60, 44)
        }
    }
}

/// يركّب كلمات خط الثلث في صورة واحدة مقصوصة على حدود الحبر — للسطر أعلى الساعة
enum InlineArt {
    /// items: (اسم الصورة، مقياس) — المقياس يكبّر الكلمة حول خط الأساس
    static func image(_ items: [(String, CGFloat)], height: CGFloat = 23) -> UIImage? {
        let imgs = items.compactMap { it in Calli.img(it.0, Styles.lockFont)?.cgImage.map { ($0, it.1) } }
        guard imgs.count == items.count, !imgs.isEmpty else { return nil }
        let gap = Int(GAP_PX)
        let base = LINE_UP
        // مواضع من الأعلى لكل صورة بعد التكبير (محاذاة خط الأساس)
        let sizes = imgs.map { (w: Int(CGFloat($0.0.width) * $0.1), h: Int(CGFloat($0.0.height) * $0.1), top: base - base * $0.1) }
        let minTop = sizes.map(\.top).min() ?? 0
        let H = Int(ceil((sizes.map { $0.top + CGFloat($0.h) }.max() ?? 1) - minTop)) + 2
        let W = sizes.reduce(0) { $0 + $1.w } + gap * (imgs.count - 1)
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        // الترتيب العربي: أول كلمة يمين — وفي الإنجليزي أول كلمة يسار
        var x = Lang.isEN ? 0 : W
        for (i, im) in imgs.enumerated() {
            let sz = sizes[i]
            if !Lang.isEN { x -= sz.w }
            let yTop = sz.top - minTop
            ctx.draw(im.0, in: CGRect(x: CGFloat(x), y: CGFloat(H) - yTop - CGFloat(sz.h), width: CGFloat(sz.w), height: CGFloat(sz.h)))
            x += Lang.isEN ? sz.w + gap : -gap
        }
        guard let full = ctx.makeImage(), let data = ctx.data else { return nil }
        let p = data.bindMemory(to: UInt8.self, capacity: W * H * 4)
        var top = H, bottom = -1
        for y in 0..<H {
            var hit = false
            var xx = 0
            while xx < W { if p[(y * W + xx) * 4 + 3] > 24 { hit = true; break }; xx += 2 }
            if hit { top = min(top, y); bottom = y }
        }
        guard bottom > top, let crop = full.cropping(to: CGRect(x: 0, y: top, width: W, height: bottom - top + 1))
        else { return nil }
        return UIImage(cgImage: crop, scale: CGFloat(crop.height) / height, orientation: .up)
    }

    static func date(_ d: Date, greg: Bool) -> [(String, CGFloat)] {
        let t = Cal.dmy(d, greg: greg)
        // الشهر والسنة فقط — النظام يعرض اسم اليوم ورقمه بجانب الويدجت تلقائيًا
        return [((greg ? "gm" : "hm") + "\(t.m)", 1),
                (greg ? "gyl\(clampY(t.y, 2020, 2050))" : "hyl\(clampY(t.y, 1440, 1470))", 1.7)]
    }
}

// ── سطر فوق الساعة: الشهر والسنة بخط الثلث (هجري أو ميلادي) ──
struct LockInlineDate: View {
    let entry: HEntry
    var greg = false
    var body: some View {
        let t = Cal.dmy(entry.date, greg: greg)
        Group {
            // أكبر قليلًا من قبل (٢٥ بدل ٢٣ نقطة) ليقارب حجم اسم اليوم بجانبه
            if let img = InlineArt.image(InlineArt.date(entry.date, greg: greg), height: 25) {
                Image(uiImage: img).renderingMode(.template)
            } else if greg {
                Text(entry.date, format: .dateTime.month(.wide).year())
            } else {
                Text(verbatim: Lang.isEN ? "\(Words.hmEN[max(0, min(11, t.m - 1))]) \(t.y) AH" : "\(HM_NAMES[max(0, min(11, t.m - 1))]) \(ar(t.y))هـ")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

// ── سطر فوق الساعة: الصلاة القادمة ──
struct LockInlinePrayer: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.prevNext(at: entry.date)
        let name = Lang.isEN ? (Words.prEN[st.next.key.rawValue] ?? "") : (PR_NAMES[st.next.key] ?? "")
        Text(verbatim: "\(name) \(hm12(st.next.time))")
            .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - المزوّد والتعريفات

struct LockProvider: TimelineProvider {
    let sched: Sched
    func entry(_ d: Date, _ ctx: Context) -> HEntry {
        HEntry(date: d, slot: .mm, size: ctx.displaySize, tint: .white, greg: false, preview: ctx.isPreview)
    }
    func placeholder(in context: Context) -> HEntry { entry(Date(), context) }
    func getSnapshot(in context: Context, completion: @escaping (HEntry) -> Void) { completion(entry(Date(), context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HEntry>) -> Void) {
        Task {
            await LocationSync.refreshIfNeeded(inWidget: true)
            await Notify.refreshIfStale()
            let now = Date()
            let midnight = Cal.nextMidnight(after: now)
            let cap = now.addingTimeInterval(45 * 60)
            if sched == .prayer {
                // مدخل كل دقيقة لثلاث ساعات (لعرض العدّاد في وضع الشاشة دائمًا)،
                // ومدخل عند كل حد صلاة بالضبط، بلا تكرار
                let firstMinute = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.up) * 60)
                var set = Set<Int>([Int(now.timeIntervalSince1970)])
                var t = firstMinute
                let horizon = now.addingTimeInterval(3 * 3600)
                while t < horizon { set.insert(Int(t.timeIntervalSince1970)); t.addTimeInterval(60) }
                for b in Prayer.boundaries(from: now, hours: 3) { set.insert(Int(b.timeIntervalSince1970)) }
                let dates = set.sorted().map { Date(timeIntervalSince1970: TimeInterval($0)) }
                let end = dates.last ?? horizon
                completion(Timeline(entries: dates.map { entry($0, context) },
                                    policy: Settings.isAuto && end > cap ? .after(cap) : .after(end)))
            } else {
                completion(Timeline(entries: [entry(now, context), entry(midnight.addingTimeInterval(5), context)],
                                    policy: .atEnd))
            }
        }
    }
}

func lockWidget<V: View>(_ id: String, _ sched: Sched, _ name: String, _ desc: String, _ family: WidgetFamily,
                         @ViewBuilder _ v: @escaping (HEntry) -> V) -> some WidgetConfiguration {
    StaticConfiguration(kind: id, provider: LockProvider(sched: sched)) { e in v(e) }
        .configurationDisplayName(L(name))
        .description(L(desc))
        .supportedFamilies([family])
}

struct L_Next: Widget { var body: some WidgetConfiguration {
    lockWidget("lock.next", .prayer, "الصلاة القادمة", "اسم الصلاة بخط الثلث ووقتها، مع العدّاد", .accessoryRectangular) { LockNextView(entry: $0) } } }
struct L_PrevNext: Widget { var body: some WidgetConfiguration {
    lockWidget("lock.prevnext", .prayer, "الصلاة السابقة والقادمة", "الوقت المنقضي منذ الصلاة السابقة، والمتبقي على القادمة", .accessoryRectangular) { LockPrevNextView(entry: $0) } } }
struct L_Hijri: Widget { var body: some WidgetConfiguration {
    lockWidget("lock.hijri", .day, "التاريخ الهجري", "اليوم والشهر وتحتهما السنة", .accessoryRectangular) { LockHijriView(entry: $0) } } }
struct L_DayDate: Widget { var body: some WidgetConfiguration {
    lockWidget("lock.daydate", .day, "اسم اليوم والتاريخ", "اسم اليوم بخط الثلث، وتحته التاريخ الهجري", .accessoryRectangular) { LockDayDateView(entry: $0) } } }
struct L_DayCircle: Widget { var body: some WidgetConfiguration {
    lockWidget("lock.daycircle", .day, "رقم اليوم الهجري", "رقم اليوم الهجري واسم الشهر", .accessoryCircular) { LockDayCircle(entry: $0) } } }
struct L_PrayerCircle: Widget { var body: some WidgetConfiguration {
    lockWidget("lock.prayercircle", .prayer, "حلقة الصلاة القادمة", "اسم الصلاة القادمة ووقتها داخل حلقة تُظهر التقدّم", .accessoryCircular) { LockPrayerCircle(entry: $0) } } }
struct L_Weekday: Widget { var body: some WidgetConfiguration {
    lockWidget("lock.weekday", .day, "اسم اليوم", "اسم اليوم بخط الثلث", .accessoryCircular) { LockWeekdayCircle(entry: $0) } } }
struct L_InlineHijri: Widget { var body: some WidgetConfiguration {
    lockWidget("lock.inlinehijri", .day, "التاريخ الهجري (أعلى الساعة)", "الشهر والسنة الهجرية بخط الثلث", .accessoryInline) { LockInlineDate(entry: $0) } } }
struct L_InlineGreg: Widget { var body: some WidgetConfiguration {
    lockWidget("lock.inlinegreg", .day, "التاريخ الميلادي (أعلى الساعة)", "الشهر والسنة الميلادية بخط الثلث", .accessoryInline) { LockInlineDate(entry: $0, greg: true) } } }
struct L_DayPrayers: Widget { var body: some WidgetConfiguration {
    lockWidget("lock.dayprayers", .prayer, "مواقيت اليوم", "الصلاة القادمة مع العدّاد، وتحتها أوقات الصلوات الخمس بخط الثلث", .accessoryRectangular) { LockDayPrayersView(entry: $0) } } }
struct L_Greg: Widget { var body: some WidgetConfiguration {
    lockWidget("lock.greg", .day, "التاريخ الميلادي", "اليوم والشهر وتحتهما السنة الميلادية", .accessoryRectangular) { LockHijriView(entry: $0, greg: true) } } }
struct L_DayDateGreg: Widget { var body: some WidgetConfiguration {
    lockWidget("lock.daydategreg", .day, "اسم اليوم والتاريخ الميلادي", "اسم اليوم بخط الثلث، وتحته التاريخ الميلادي", .accessoryRectangular) { LockDayDateView(entry: $0, greg: true) } } }
struct L_DayCircleGreg: Widget { var body: some WidgetConfiguration {
    lockWidget("lock.daycirclegreg", .day, "رقم اليوم الميلادي", "رقم اليوم الميلادي واسم الشهر", .accessoryCircular) { LockDayCircle(entry: $0, greg: true) } } }
struct L_InlinePrayer: Widget { var body: some WidgetConfiguration {
    lockWidget("lock.inlineprayer", .prayer, "الصلاة القادمة (أعلى الساعة)", "سطر الصلاة القادمة ووقتها أعلى الساعة", .accessoryInline) { LockInlinePrayer(entry: $0) } } }

struct LockGroup: WidgetBundle {
    var body: some Widget {
        L_Next(); L_PrevNext(); L_Hijri(); L_DayDate(); L_DayCircle(); L_PrayerCircle(); L_Weekday(); L_InlineHijri(); L_InlinePrayer()
    }
}

struct LockGroup2: WidgetBundle {
    var body: some Widget {
        L_DayPrayers(); L_Greg(); L_DayDateGreg(); L_DayCircleGreg(); L_InlineGreg()
    }
}
