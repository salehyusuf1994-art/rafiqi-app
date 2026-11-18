import SwiftUI

// MARK: - تقويم أم القرى
// يعتمد على جداول تقويم أم القرى الرسمية (مدينة الملك عبدالعزيز للعلوم والتقنية) المضمّنة في نظام iOS،
// وهي نفسها المعتمدة في المملكة للتواريخ الرسمية. التعديل اليدوي للتاريخ (±يومين) يُطبّق هنا أيضًا
// حتى يطابق التقويم الرئيسية والويدجت.

enum UQ {
    static var hijri: Calendar {
        var c = Calendar(identifier: .islamicUmmAlQura)
        c.timeZone = .current
        return c
    }
    static var greg: Calendar { Cal.gregCal }

    /// تعديل المستخدم بالثواني (يوم = ٨٦٤٠٠)
    static var off: TimeInterval { Double(Settings.hijriOffset) * 86400 }
    /// التاريخ الهجري لليوم (مع التعديل)
    static func h(_ d: Date) -> DateComponents { hijri.dateComponents([.year, .month, .day], from: d.addingTimeInterval(off)) }
    /// أول يوم (بالتاريخ الفعلي) وطول الشهر الهجري أو الميلادي الذي فيه «d»
    static func month(of d: Date, hijriMode: Bool) -> (first: Date, len: Int) {
        let c = hijriMode ? hijri : greg
        let sd = hijriMode ? d.addingTimeInterval(off) : d
        let start = c.dateInterval(of: .month, for: sd)?.start ?? sd
        let len = c.range(of: .day, in: .month, for: sd)?.count ?? 30
        return (hijriMode ? start.addingTimeInterval(-off) : start, len)
    }

    static func monthName(_ m: Int, hijri: Bool) -> String {
        let i = max(0, min(11, m - 1))
        if Lang.isEN { return hijri ? Words.hmEN[i] : Words.gmEN[i] }
        return hijri ? Words.hm[i] : (Settings.shamiMonths ? Words.gs[i] : Words.gm[i])
    }

    /// المناسبات (هجري: شهر/يوم — ميلادي: شهر/يوم)
    static func occasion(_ d: Date) -> (String, Bool)? {
        let h = Self.h(d), g = greg.dateComponents([.month, .day], from: d)
        let hm = h.month ?? 0, hd = h.day ?? 0
        switch (hm, hd) {
        case (1, 1): return ("رأس السنة الهجرية", true)
        case (1, 10): return ("يوم عاشوراء", true)
        case (9, 1): return ("بداية شهر رمضان", true)
        case (10, 1): return ("عيد الفطر", true)
        case (12, 8): return ("يوم التروية", true)
        case (12, 9): return ("يوم عرفة", true)
        case (12, 10): return ("عيد الأضحى", true)
        case (12, 11), (12, 12), (12, 13): return ("أيام التشريق", true)
        default: break
        }
        switch (g.month ?? 0, g.day ?? 0) {
        case (2, 22): return ("يوم التأسيس", true)
        case (3, 11): return ("يوم العلم", true)
        case (9, 23): return ("اليوم الوطني السعودي", true)
        default: break
        }
        if hm != 9, (13...15).contains(hd) { return ("الأيام البيض", false) }
        return nil
    }
}

struct UmmAlQuraView: View {
    @State private var hijriMode = true
    @State private var anchor = Date()
    @State private var selected = Date()
    @State private var showConverter = SHOT == "calendar2"

    private var cal: Calendar { hijriMode ? UQ.hijri : UQ.greg }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                BackRow()
                PageHeader(title: "تقويم أم القرى", subtitle: L("التقويم الرسمي للمملكة العربية السعودية"))

                // أدوات التقويم بأسماء واضحة (كان المحوّل خلف زر بلا اسم)
                HStack(spacing: 10) {
                    NavigationLink { MonthlyTimetableView() } label: {
                        Label("جدول المواقيت والإمساكية", systemImage: "tablecells").font(Theme.f(.footnote, .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 10).background(Capsule().fill(Theme.cardHi))
                    }
                    Button { withAnimation(.snappy) { showConverter.toggle() } } label: {
                        Label("محوّل التاريخ", systemImage: "arrow.left.arrow.right").font(Theme.f(.footnote, .bold))
                            .foregroundStyle(showConverter ? .black : .white)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Capsule().fill(showConverter ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(Theme.cardHi)))
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Chip(title: "هجري", on: hijriMode) { withAnimation(.snappy) { hijriMode = true } }
                    Chip(title: "ميلادي", on: !hijriMode) { withAnimation(.snappy) { hijriMode = false } }
                    Spacer()
                    Chip(title: "اليوم", icon: "scope", on: false) {
                        withAnimation(.snappy) { anchor = Date(); selected = Date() }
                    }
                }

                if showConverter { DateConverter().transition(.opacity.combined(with: .move(edge: .top))) }

                monthCard
                dayCard
                occasionsCard

                VStack(spacing: 6) {
                    if Settings.hijriOffset != 0 {
                        Text(LF("يُطبّق تعديلك اليدوي للتاريخ (%@) على هذا التقويم كما في الرئيسية والويدجت.", offsetLabel))
                            .font(Theme.f(.caption)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
                    }
                    Link(destination: URL(string: "https://www.ummulqura.org.sa")!) {
                        Label("الموقع الرسمي لتقويم أم القرى", systemImage: "safari").font(Theme.f(.footnote, .semibold))
                    }
                    .foregroundStyle(Theme.gold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .barSpace()
        .background(AppBackground())
        .hiddenNavBar()
    }

    private var offsetLabel: String {
        let o = Settings.hijriOffset
        return (o > 0 ? "+" : "−") + ar(abs(o))
    }

    // ── الشهر ──
    var monthCard: some View {
        let (first, len) = UQ.month(of: anchor, hijriMode: hijriMode)
        let g = UQ.greg
        let lead = Cal.weekday(first)
        let rows = Int(ceil(Double(lead + len) / 7))
        let mc = hijriMode ? UQ.h(first) : g.dateComponents([.year, .month], from: first)
        let last = g.date(byAdding: .day, value: len - 1, to: first) ?? first
        let other = otherSpan(first, last)
        return VStack(spacing: 12) {
            HStack {
                CircleButton(icon: Lang.isEN ? "chevron.left" : "chevron.right", size: 36) { shift(-1) }
                Spacer()
                VStack(spacing: 2) {
                    Text(verbatim: "\(UQ.monthName(mc.month ?? 1, hijri: hijriMode)) \(ar(mc.year ?? 0))\(hijriMode ? (Lang.isEN ? " AH" : " هـ") : "")")
                        .font(Theme.title(21)).foregroundStyle(.white)
                    Text(verbatim: other).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                }
                Spacer()
                CircleButton(icon: Lang.isEN ? "chevron.right" : "chevron.left", size: 36) { shift(1) }
            }
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(L(Lang.isEN ? Words.wlEN[i] : Words.wl[i]))
                        .font(Theme.title(13)).foregroundStyle(i == 5 ? Theme.gold : Theme.sub)
                        .frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 6) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            let k = r * 7 + col - lead
                            if k >= 0 && k < len, let d = g.date(byAdding: .day, value: k, to: first) {
                                dayCell(d, col: col)
                            } else {
                                Color.clear.frame(maxWidth: .infinity).frame(height: 50)
                            }
                        }
                    }
                }
            }
            .environment(\.layoutDirection, Lang.dir)
        }
        .glassCard(padding: 14)
        // السحب أفقيًا فقط (لا يعطّل تمرير الصفحة للأعلى والأسفل)
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
            let dx = v.translation.width * (Lang.isEN ? 1 : -1)
            if abs(dx) > 40 && abs(v.translation.width) > abs(v.translation.height) * 1.5 { shift(dx < 0 ? 1 : -1) }
        })
    }

    func dayCell(_ d: Date, col: Int) -> some View {
        let hd = UQ.h(d).day ?? 1, gd = UQ.greg.component(.day, from: d)
        let main = hijriMode ? hd : gd
        let alt = hijriMode ? gd : hd
        let isToday = Cal.gregCal.isDateInToday(d)
        let isSel = Cal.gregCal.isDate(d, inSameDayAs: selected)
        let occ = UQ.occasion(d)
        return Button { withAnimation(.snappy(duration: 0.2)) { selected = d } } label: {
            VStack(spacing: 1) {
                Text(ar(main)).font(digitFont(18, bold: true))
                    .foregroundStyle(isSel ? Color.black : (col == 5 ? Theme.gold : .white))
                Text(ar(alt)).font(Theme.font(10, .medium).monospacedDigit())
                    .foregroundStyle(isSel ? Color.black.opacity(0.6) : Theme.sub)
                Circle().fill(occ == nil ? Color.clear : (occ!.1 ? Theme.gold : Color.white.opacity(0.5)))
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .background {
                if isSel {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.gold)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.gold, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    func shift(_ n: Int) {
        withAnimation(.snappy) {
            // ننتقل من منتصف الشهر الحالي حتى لا يتأثر بطول الشهر أو التعديل
            let (first, _) = UQ.month(of: anchor, hijriMode: hijriMode)
            let mid = first.addingTimeInterval(14 * 86400)
            let base = hijriMode ? mid.addingTimeInterval(UQ.off) : mid
            let moved = cal.date(byAdding: .month, value: n, to: base) ?? base
            anchor = hijriMode ? moved.addingTimeInterval(-UQ.off) : moved
        }
    }

    /// أسماء أشهر التقويم الآخر في هذا الشهر
    func otherSpan(_ a: Date, _ b: Date) -> String {
        let ca = hijriMode ? UQ.greg.dateComponents([.year, .month], from: a) : UQ.h(a)
        let cb = hijriMode ? UQ.greg.dateComponents([.year, .month], from: b) : UQ.h(b)
        let n1 = UQ.monthName(ca.month ?? 1, hijri: !hijriMode), n2 = UQ.monthName(cb.month ?? 1, hijri: !hijriMode)
        let y = ar(cb.year ?? 0) + (hijriMode ? "" : (Lang.isEN ? " AH" : " هـ"))
        return ca.month == cb.month ? "\(n1) \(y)" : "\(n1) – \(n2) \(y)"
    }

    // ── اليوم المختار ──
    var dayCard: some View {
        let h = UQ.h(selected)
        let g = UQ.greg.dateComponents([.year, .month, .day], from: selected)
        let wd = Lang.isEN ? Words.wdEN[Cal.weekday(selected)] : Words.wd[Cal.weekday(selected)]
        let times = Prayer.dayTimes(selected)
        return VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: wd).font(Theme.title(22)).foregroundStyle(.white)
                    Text(verbatim: "\(ar(h.day ?? 1)) \(UQ.monthName(h.month ?? 1, hijri: true)) \(ar(h.year ?? 0))\(Lang.isEN ? " AH" : " هـ")")
                        .font(Theme.title(16)).foregroundStyle(Theme.gold)
                    Text(verbatim: "\(ar(g.day ?? 1)) \(UQ.monthName(g.month ?? 1, hijri: false)) \(ar(g.year ?? 0))")
                        .font(Theme.f(.subheadline)).foregroundStyle(Theme.sub)
                }
                Spacer()
                if let occ = UQ.occasion(selected) {
                    Text(L(occ.0)).font(Theme.title(13)).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(occ.1 ? Theme.gold : Color.white.opacity(0.7)))
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(times.enumerated()), id: \.offset) { _, p in
                    VStack(spacing: 3) {
                        Image(systemName: APP_PR_ICON[p.key] ?? "sun.max").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold.opacity(0.9))
                        PrName(p.key, 46, 18, 0.95)
                        Digits(text: hm12(p.time), size: 12.5, color: .white)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
        }
        .glassCard(padding: 16)
    }

    // ── مناسبات الشهر ──
    var occasionsCard: some View {
        let (first, len) = UQ.month(of: anchor, hijriMode: hijriMode)
        var list: [(Date, String)] = []
        var seen = Set<String>()
        for k in 0..<len {
            if let d = UQ.greg.date(byAdding: .day, value: k, to: first), let o = UQ.occasion(d), o.1, !seen.contains(o.0) {
                seen.insert(o.0)
                list.append((d, o.0))
            }
        }
        return Group {
            if !list.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("مناسبات الشهر").font(Theme.title(17)).foregroundStyle(.white)
                    ForEach(Array(list.enumerated()), id: \.offset) { _, it in
                        let h = UQ.h(it.0)
                        let g = UQ.greg.dateComponents([.month, .day], from: it.0)
                        HStack(spacing: 10) {
                            Circle().fill(Theme.gold).frame(width: 7, height: 7)
                            Text(L(it.1)).foregroundStyle(.white)
                            Spacer()
                            Text(verbatim: "\(ar(h.day ?? 1)) \(UQ.monthName(h.month ?? 1, hijri: true))  ·  \(ar(g.day ?? 1)) \(UQ.monthName(g.month ?? 1, hijri: false))")
                                .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                        }
                    }
                }
                .glassCard(padding: 16)
            }
        }
    }
}

// MARK: - محوّل التاريخ (هجري ⇄ ميلادي)

struct DateConverter: View {
    @State private var toGreg = true
    @State private var hd = UQ.h(Date()).day ?? 1
    @State private var hm = UQ.h(Date()).month ?? 1
    @State private var hy = UQ.h(Date()).year ?? 1448
    @State private var gDate = Date()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("محوّل التاريخ").font(Theme.title(17)).foregroundStyle(.white)
                Spacer()
                Picker("", selection: $toGreg) {
                    Text("هجري ← ميلادي").tag(true)
                    Text("ميلادي ← هجري").tag(false)
                }
                .pickerStyle(.segmented).frame(width: 220)
            }
            if toGreg {
                HStack(spacing: 0) {
                    // عمود الشهر أعرض (أسماء مثل «جمادى الأولى» كانت تُقص)
                    Picker("", selection: $hd) { ForEach(1...30, id: \.self) { Text(ar($0)).tag($0) } }
                        .pickerStyle(.wheel).frame(width: 64)
                    Picker("", selection: $hm) { ForEach(1...12, id: \.self) { Text(UQ.monthName($0, hijri: true)).lineLimit(1).minimumScaleFactor(0.8).tag($0) } }
                        .pickerStyle(.wheel).frame(maxWidth: .infinity)
                    Picker("", selection: $hy) { ForEach(1356...1500, id: \.self) { Text(ar($0)).tag($0) } }
                        .pickerStyle(.wheel).frame(width: 84)
                }
                .frame(height: 130)
                result(hijriToGreg)
            } else {
                DatePicker("", selection: $gDate, displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden()
                    .environment(\.calendar, UQ.greg)
                    .frame(height: 150)
                result(gregToHijri)
            }
        }
        .glassCard(padding: 16)
    }

    var hijriToGreg: String {
        let c = UQ.hijri
        guard let first = c.date(from: DateComponents(year: hy, month: hm, day: 1)) else { return "—" }
        let len = c.range(of: .day, in: .month, for: first)?.count ?? 30
        if hd > len { return LF("شهر %@ في هذه السنة %@ يومًا فقط", UQ.monthName(hm, hijri: true), ar(len)) }
        guard let d0 = c.date(byAdding: .day, value: hd - 1, to: first) else { return "—" }
        let d = d0.addingTimeInterval(-UQ.off)
        let g = UQ.greg.dateComponents([.year, .month, .day], from: d)
        let wd = Lang.isEN ? Words.wdEN[Cal.weekday(d)] : Words.wd[Cal.weekday(d)]
        return "\(wd) \(ar(g.day ?? 1)) \(UQ.monthName(g.month ?? 1, hijri: false)) \(ar(g.year ?? 0))"
    }

    var gregToHijri: String {
        let h = UQ.h(gDate)
        let wd = Lang.isEN ? Words.wdEN[Cal.weekday(gDate)] : Words.wd[Cal.weekday(gDate)]
        return "\(wd) \(ar(h.day ?? 1)) \(UQ.monthName(h.month ?? 1, hijri: true)) \(ar(h.year ?? 0))\(Lang.isEN ? " AH" : " هـ")"
    }

    func result(_ text: String) -> some View {
        Text(verbatim: text).font(Theme.title(18)).foregroundStyle(Theme.gold)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.gold.opacity(0.12)))
    }
}
