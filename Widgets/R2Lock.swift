import SwiftUI
import WidgetKit
import AppIntents

// MARK: - شاشة القفل بالنظام الجديد: ثلاث ويدجت بالمقاس (مستطيل، دائري، سطر)،
// وتُختار الويدجت نفسها من «تعديل الأداة». شاشة القفل يرسمها النظام بلون واحد،
// فالثلث يظهر أبيض نقيًا بلا زجاج.

// ── المستطيل ──

/// القفل ١ — الصلاة القادمة
struct R2LockNextView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.prevNext(at: entry.date)
        LockRoot {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: L("باقي على")).font(R2.font(11)).opacity(0.8)
                    CountDown(to: st.next.time, size: 20, color: .white, width: 92, at: entry.date)
                        .fixedSize().widgetAccentable()
                    Text(verbatim: R2.time(st.next.time)).font(R2.font(10.5)).opacity(0.7)
                }
                Spacer(minLength: 2)
                Fit("pr_\(st.next.key.rawValue)_t", 70, 44)
            }
        }
    }
}

/// القفل ٢ — مواقيت اليوم
struct R2LockDayView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.prevNext(at: entry.date)
        let times = Prayer.dayTimes(entry.date).filter { $0.key != .sunrise }
        LockRoot {
            VStack(spacing: 2) {
                HStack {
                    Fit("pr_\(st.next.key.rawValue)_t", 56, 26)
                    Spacer(minLength: 2)
                    CountDown(to: st.next.time, size: 17, color: .white, width: 84, at: entry.date)
                        .fixedSize().widgetAccentable()
                }
                HStack(spacing: 0) {
                    ForEach(Array(times.enumerated()), id: \.offset) { _, p in
                        Text(verbatim: hm12(p.time))
                            .font(digitFont(11, bold: p.time == st.next.time))
                            .opacity(p.time == st.next.time ? 1 : 0.72)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

/// القفل ٣ — السابقة والقادمة
struct R2LockPrevNextView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.prevNext(at: entry.date)
        LockRoot {
            HStack(spacing: 8) {
                VStack(spacing: 0) {
                    Fit("pr_\(st.prev.key.rawValue)_t", 52, 22).opacity(0.7)
                    CountUp(from: st.prev.time, size: 14, color: .white, width: 72, at: entry.date).fixedSize().opacity(0.7)
                    Text(verbatim: L("مضى")).font(R2.font(9.5)).opacity(0.6)
                }
                .frame(maxWidth: .infinity)
                Rectangle().frame(width: 0.6).opacity(0.35).padding(.vertical, 6)
                VStack(spacing: 0) {
                    Fit("pr_\(st.next.key.rawValue)_t", 52, 22)
                    CountDown(to: st.next.time, size: 15, color: .white, width: 72, at: entry.date).fixedSize().widgetAccentable()
                    Text(verbatim: L("باقي")).font(R2.font(9.5)).opacity(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// القفل ٤ — التاريخ («(اليوم) الشهر» وتحته السنة، هجري أو ميلادي)
struct R2LockDateView: View {
    let entry: HEntry
    var body: some View {
        LockRoot {
            DatePair2(date: entry.date, greg: entry.greg, maxW: 160, maxS: 0.42)
        }
    }
}

/// القفل ٥ — اليوم والتاريخ
struct R2LockDayDateView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date
        LockRoot {
            VStack(spacing: 0) {
                Fit("wd\(Cal.weekday(d))_t", 130, 40)
                Text(verbatim: entry.greg ? R2.gregLine(d) : R2.hijriLine(d))
                    .font(R2.font(12, .bold)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}

// ── الدائري ──

/// القفل ٦ — رقم اليوم
struct R2LockDayNumView: View {
    let entry: HEntry
    var body: some View {
        let t = Cal.dmy(entry.date, greg: entry.greg)
        LockRoot(circle: true) {
            VStack(spacing: -2) {
                Text(verbatim: R2.num(t.d)).font(digitFont(26, bold: true)).widgetAccentable()
                Text(verbatim: R2.month(t.m, greg: entry.greg)).font(R2.font(9, .bold))
                    .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 6)
            }
        }
    }
}

/// القفل ٧ — حلقة الصلاة القادمة
struct R2LockRingView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.state(at: entry.date)
        LockRoot(circle: true) {
            ZStack {
                Ring2(p: st.progress, line: 4).padding(3).widgetAccentable()
                Fit("pr_\(st.next.key.rawValue)_t", 42, 24)
            }
        }
    }
}

/// القفل ٨ — اسم اليوم
struct R2LockWeekdayView: View {
    let entry: HEntry
    var body: some View {
        LockRoot(circle: true) {
            Fit("wd\(Cal.weekday(entry.date))_t", 58, 34)
        }
    }
}

/// القفل ٩ — التسبيح: الضغطة تعدّ من شاشة القفل
struct R2LockTasbihView: View {
    let entry: HEntry
    var body: some View {
        let c = Adhkar.current(entry.date)
        let p = Double(c.count) / Double(max(1, c.item.times))
        LockRoot(circle: true) {
            Button(intent: DhikrTapIntent()) {
                ZStack {
                    Ring2(p: p, line: 4).padding(3).widgetAccentable()
                    VStack(spacing: -1) {
                        Text(verbatim: R2.num(c.count)).font(digitFont(19, bold: true))
                        Text(verbatim: L("تسبيح")).font(R2.font(8.5, .bold))
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// القفل ١٠ — المناسبة القادمة
struct R2LockOccasionView: View {
    let entry: HEntry
    var body: some View {
        let o = Occasions.next(from: entry.date)
        LockRoot(circle: true) {
            VStack(spacing: -2) {
                Text(verbatim: R2.num(o?.days ?? 0)).font(digitFont(22, bold: true)).widgetAccentable()
                Text(verbatim: L(Occasions.short(o?.name ?? ""))).font(R2.font(8.5, .bold))
                    .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 6)
            }
        }
    }
}

// ── السطر (أعلى الساعة) ──

/// القفل ١١ — التاريخ أعلى الساعة
struct R2LockInlineDateView: View {
    let entry: HEntry
    var body: some View {
        Text(verbatim: entry.greg ? R2.gregLine(entry.date) : R2.hijriLine(entry.date))
            .containerBackground(for: .widget) { Color.clear }
    }
}

/// القفل ١٢ — الصلاة أعلى الساعة
struct R2LockInlinePrayerView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.prevNext(at: entry.date)
        Text(verbatim: R2.prayer(st.next.key) + " " + R2.time(st.next.time))
            .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - الإعداد («تعديل الأداة»)

enum LockRectDesign: String, AppEnum {
    case next = "r2.lock.next", day = "r2.lock.day", prevnext = "r2.lock.prevnext", date = "r2.lock.date", daydate = "r2.lock.daydate"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "الويدجت"
    static let caseDisplayRepresentations: [LockRectDesign: DisplayRepresentation] = [
        .next: DisplayRepresentation(title: "القفل ١", subtitle: "الصلاة القادمة"),
        .day: DisplayRepresentation(title: "القفل ٢", subtitle: "مواقيت اليوم"),
        .prevnext: DisplayRepresentation(title: "القفل ٣", subtitle: "السابقة والقادمة"),
        .date: DisplayRepresentation(title: "القفل ٤", subtitle: "التاريخ"),
        .daydate: DisplayRepresentation(title: "القفل ٥", subtitle: "اليوم والتاريخ"),
    ]
}

enum LockCircleDesign: String, AppEnum {
    case daynum = "r2.lock.daynum", ring = "r2.lock.ring", weekday = "r2.lock.weekday", tasbih = "r2.lock.tasbih", occasion = "r2.lock.occasion"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "الويدجت"
    static let caseDisplayRepresentations: [LockCircleDesign: DisplayRepresentation] = [
        .daynum: DisplayRepresentation(title: "القفل ٦", subtitle: "رقم اليوم"),
        .ring: DisplayRepresentation(title: "القفل ٧", subtitle: "حلقة الصلاة"),
        .weekday: DisplayRepresentation(title: "القفل ٨", subtitle: "اسم اليوم"),
        .tasbih: DisplayRepresentation(title: "القفل ٩", subtitle: "التسبيح"),
        .occasion: DisplayRepresentation(title: "القفل ١٠", subtitle: "المناسبة القادمة"),
    ]
}

enum LockInlineDesign: String, AppEnum {
    case date = "r2.lock.idate", prayer = "r2.lock.iprayer"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "الويدجت"
    static let caseDisplayRepresentations: [LockInlineDesign: DisplayRepresentation] = [
        .date: DisplayRepresentation(title: "القفل ١١", subtitle: "التاريخ أعلى الساعة"),
        .prayer: DisplayRepresentation(title: "القفل ١٢", subtitle: "الصلاة أعلى الساعة"),
    ]
}

protocol LockConfig: WidgetConfigurationIntent {
    var designID: String { get }
    var isGregorian: Bool { get }
    var shamiChoice: Bool? { get }
}

struct LockRectIntent: LockConfig {
    static let title: LocalizedStringResource = "إعداد الويدجت"
    static let description = IntentDescription("اختر الويدجت برقمها، ثم التقويم.")
    @Parameter(title: "الويدجت", default: .next) var design: LockRectDesign
    @Parameter(title: "التقويم", default: .hijri) var calendar: CalOpt
    var designID: String { design.rawValue }
    var isGregorian: Bool { calendar.isGregorian }
    var shamiChoice: Bool? { calendar.shami }
    init() {}
}

struct LockCircleIntent: LockConfig {
    static let title: LocalizedStringResource = "إعداد الويدجت"
    static let description = IntentDescription("اختر الويدجت برقمها، ثم التقويم.")
    @Parameter(title: "الويدجت", default: .ring) var design: LockCircleDesign
    @Parameter(title: "التقويم", default: .hijri) var calendar: CalOpt
    var designID: String { design.rawValue }
    var isGregorian: Bool { calendar.isGregorian }
    var shamiChoice: Bool? { calendar.shami }
    init() {}
}

struct LockInlineIntent: LockConfig {
    static let title: LocalizedStringResource = "إعداد الويدجت"
    static let description = IntentDescription("اختر الويدجت برقمها، ثم التقويم.")
    @Parameter(title: "الويدجت", default: .date) var design: LockInlineDesign
    @Parameter(title: "التقويم", default: .hijri) var calendar: CalOpt
    var designID: String { design.rawValue }
    var isGregorian: Bool { calendar.isGregorian }
    var shamiChoice: Bool? { calendar.shami }
    init() {}
}

/// مزوّد ويدجت القفل المختارة: نفس جدولة ويدجت القفل الحالية
struct R2LockProvider<I: LockConfig>: AppIntentTimelineProvider {
    let fallback: String

    private func entry(_ d: Date, _ c: I?, _ ctx: Context) -> HEntry {
        var e = HEntry(date: d, slot: .mm, size: ctx.displaySize, tint: .white, greg: c?.isGregorian ?? false, preview: ctx.isPreview)
        e.kind = c?.designID ?? fallback
        e.shami = c?.shamiChoice
        e.family = ctx.family
        return e
    }

    func placeholder(in context: Context) -> HEntry { entry(Date(), nil, context) }
    func snapshot(for configuration: I, in context: Context) async -> HEntry { entry(Date(), configuration, context) }

    func timeline(for configuration: I, in context: Context) async -> Timeline<HEntry> {
        await LocationSync.refreshIfNeeded(inWidget: true)
        await Notify.refreshIfStale()
        let now = Date()
        let midnight = Cal.nextMidnight(after: now)
        let cap = now.addingTimeInterval(45 * 60)
        let sched = Catalog.info(configuration.designID).sched
        func e(_ d: Date) -> HEntry { entry(d, configuration, context) }
        if sched == .prayer {
            // مدخل كل دقيقة لثلاث ساعات (لوضع الشاشة دائمًا)، ومدخل عند كل حد صلاة
            let firstMinute = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.up) * 60)
            var set = Set<Int>([Int(now.timeIntervalSince1970)])
            var t = firstMinute
            let horizon = now.addingTimeInterval(3 * 3600)
            while t < horizon { set.insert(Int(t.timeIntervalSince1970)); t.addTimeInterval(60) }
            for b in Prayer.boundaries(from: now, hours: 3) { set.insert(Int(b.timeIntervalSince1970)) }
            let dates = set.sorted().map { Date(timeIntervalSince1970: TimeInterval($0)) }
            let end = dates.last ?? horizon
            return Timeline(entries: dates.map { e($0) }, policy: Settings.isAuto && end > cap ? .after(cap) : .after(end))
        }
        return Timeline(entries: [e(now), e(midnight.addingTimeInterval(5))], policy: .atEnd)
    }
}

struct RafiqiLockRect: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "rafiqi.lock.rect", intent: LockRectIntent.self,
                               provider: R2LockProvider<LockRectIntent>(fallback: "r2.lock.next")) { e in
            ShamiScope(shami: e.shami) { Catalog.info(e.kind).render(e) }
        }
        .configurationDisplayName(L("رفيقي — مستطيل"))
        .description(L("اختر الويدجت برقمها من «تعديل الأداة»."))
        .supportedFamilies([.accessoryRectangular])
    }
}

struct RafiqiLockCircle: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "rafiqi.lock.circle", intent: LockCircleIntent.self,
                               provider: R2LockProvider<LockCircleIntent>(fallback: "r2.lock.ring")) { e in
            ShamiScope(shami: e.shami) { Catalog.info(e.kind).render(e) }
        }
        .configurationDisplayName(L("رفيقي — دائري"))
        .description(L("اختر الويدجت برقمها من «تعديل الأداة»."))
        .supportedFamilies([.accessoryCircular])
    }
}

struct RafiqiLockInline: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "rafiqi.lock.inline", intent: LockInlineIntent.self,
                               provider: R2LockProvider<LockInlineIntent>(fallback: "r2.lock.idate")) { e in
            ShamiScope(shami: e.shami) { Catalog.info(e.kind).render(e) }
        }
        .configurationDisplayName(L("رفيقي — سطر"))
        .description(L("اختر الويدجت برقمها من «تعديل الأداة»."))
        .supportedFamilies([.accessoryInline])
    }
}
