import SwiftUI
import WidgetKit
import AppIntents

// MARK: - الويدجت الجديدة (النظام المعتمد) — كل وحدة: بطل واحد، معلومة، تفاصيل

/// مقاس الويدجت الفعلي (أو مقاس افتراضي قبل أن يعرفه النظام) — مشتركة بين ويدجت R2 وR3
func dims(_ e: HEntry, _ fallback: CGSize) -> CGSize {
    e.size.width > 10 && e.size.height > 10 ? e.size : fallback
}
private let SMALL = CGSize(width: 170, height: 170)
private let MEDIUM = CGSize(width: 364, height: 170)
private let LARGE = CGSize(width: 364, height: 382)

private func isMedium(_ e: HEntry) -> Bool { e.family == .systemMedium || (e.family == nil && e.size.width > e.size.height * 1.5) }
private func isLarge(_ e: HEntry) -> Bool { e.family == .systemLarge || (e.family == nil && e.size.height > 300) }

// ═══════════════════════════ الصلاة ═══════════════════════════

/// الصلاة ١ — اليوم والصلاة (متوسط)
struct R2TodayView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date, sz = dims(entry, MEDIUM)
        let st = Prayer.state(at: d)
        let wd = "wd\(Cal.weekday(d))_t"
        Root(entry: entry) {
            VStack(spacing: 0) {
                T2(text: R2.hijriLine(d) + "  ·  " + R2.gregLine(d, year: false), size: 12.5)
                    .padding(.top, 11)
                Fit(wd, sz.width * 0.6, 58)
                    .frame(height: 56)
                PrayerRow2(date: d, nameH: 18, timeSize: 14, colW: (sz.width - 24) / 6)
                    .padding(.horizontal, 12)
                Hair2().padding(.horizontal, 18).padding(.top, 5)
                LeftLine2(next: st.next, at: d)
                    .padding(.top, 4)
                Spacer(minLength: 0)
            }
        }
    }
}

/// الصلاة ٢ — الصلاة القادمة (صغير): الشرطات حول الحافة تضيء كلما قرب الوقت
struct R2NextView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date, sz = dims(entry, SMALL)
        let st = Prayer.state(at: d)
        Root(entry: entry) {
            ZStack {
                TickRim(count: 60, lit: max(1, Int((st.progress * 60).rounded(.down))))
                VStack(spacing: 1) {
                    T2(text: L("باقي على"), size: 12)
                    Fit("pr_\(st.next.key.rawValue)_t", sz.width * 0.62, 44)
                        .frame(height: 46)
                    CountDown(to: st.next.time, size: 25, color: .white, width: sz.width - 30, at: d)
                    T2(text: (st.next.key.isPrayer ? L("الأذان") + " " : "") + R2.time(st.next.time), size: 11.5)
                        .padding(.top, 1)
                }
            }
        }
    }
}

/// الصلاة ٣ — السابقة والقادمة (صغير ومتوسط)
struct R2PrevNextView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date
        let st = Prayer.prevNext(at: d)
        Root(entry: entry) {
            if isMedium(entry) {
                HStack(spacing: 16) {
                    column(st.prev, up: true)
                        .opacity(0.55)
                    Hair2(vertical: true).padding(.vertical, 8)
                    column(st.next, up: false)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 0) {
                            T2(text: L("مضى على"), size: 11)
                            CountUp(from: st.prev.time, size: 14, color: .white, width: 74, at: d).fixedSize()
                        }
                        Spacer(minLength: 4)
                        PrName(st.prev.key, 58, 28)
                    }
                    .opacity(0.55)
                    Hair2().padding(.vertical, 7)
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 0) {
                            T2(text: L("باقي على"), size: 12)
                            CountDown(to: st.next.time, size: 21, color: .white, width: 92, at: d).fixedSize()
                        }
                        Spacer(minLength: 4)
                        PrName(st.next.key, 62, 38)
                    }
                    Spacer(minLength: 6)
                    Bar2(p: st.progress)
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
            }
        }
    }

    private func column(_ p: PTime, up: Bool) -> some View {
        VStack(spacing: 2) {
            T2(text: L(up ? "الصلاة السابقة" : "الصلاة القادمة"), size: 12)
            Fit("pr_\(p.key.rawValue)_t", 120, 42).frame(height: 44)
            Digits(text: hm12(p.time), size: 13, color: Color.white.opacity(R2.dim))
            Group {
                if up { CountUp(from: p.time, size: 22, color: .white, width: 110, at: entry.date) }
                else { CountDown(to: p.time, size: 24, color: .white, width: 110, at: entry.date) }
            }
            .fixedSize()
            T2(text: L(up ? "مضى" : "باقي"), size: 11)
        }
        .frame(maxWidth: .infinity)
    }
}

/// الصلاة ٤ — مواقيت اليوم (صغير)
struct R2ListView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date
        let times = Prayer.dayTimes(d)
        let nextIdx = times.firstIndex { $0.time > d }
        Root(entry: entry) {
            VStack(spacing: 0) {
                ForEach(Array(times.enumerated()), id: \.offset) { i, p in
                    let on = i == nextIdx
                    HStack {
                        PrName(p.key, 62, 17)
                        Spacer(minLength: 4)
                        // بلا فراغ السطر الكبير لخط الأرقام: كان يطيل الصفوف الستة فتخرج القائمة عن حواف الويدجت
                        Digits(text: hm12(p.time), size: 14, color: .white, bold: on, tight: true)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(on ? 0.17 : 0)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(on ? 0.35 : 0), lineWidth: 0.6))
                    .opacity((nextIdx.map { i < $0 } ?? true) ? R2.past : 1)
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
        }
    }
}

/// الصلاة ٥ — حلقات الصلوات (متوسط): الحالية تمتلئ، والماضية مكتملة باهتة
struct R2RingsView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date
        let times = Prayer.dayTimes(d)
        let cur = times.lastIndex { $0.time <= d }
        let st = Prayer.state(at: d)
        Root(entry: entry) {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(Array(times.enumerated()), id: \.offset) { i, p in
                        let fill: Double = {
                            guard let cur else { return 0 }
                            if i < cur { return 1 }
                            if i == cur, i + 1 < times.count {
                                let span = times[i + 1].time.timeIntervalSince(p.time)
                                return span > 0 ? min(1, d.timeIntervalSince(p.time) / span) : 0
                            }
                            return i == cur ? 1 : 0
                        }()
                        VStack(spacing: 4) {
                            ZStack {
                                Ring2(p: fill, line: 3, on: i == cur)
                                Digits(text: hm12(p.time), size: 11.5, color: .white, bold: i == cur)
                            }
                            .frame(width: 46, height: 46)
                            PrName(p.key, 50, 17)
                        }
                        .opacity(cur.map { i < $0 } ?? false ? R2.past : 1)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 10)
                LeftLine2(next: st.next, at: d, size: 13)
            }
        }
    }
}

/// الصلاة ٦ — الثلث الأخير (صغير)
struct R2ThirdView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date
        let lt = Prayer.lastThird(around: d)
        let inThird = d >= lt.start && d < lt.fajr
        let inNight = d >= lt.maghrib && d < lt.fajr
        let f = inNight ? d.timeIntervalSince(lt.maghrib) / max(1, lt.fajr.timeIntervalSince(lt.maghrib)) : -1
        Root(entry: entry) {
            ZStack {
                NightArc(nowFraction: f)
                    .frame(width: 132, height: 132)
                    .offset(y: 4)
                VStack(spacing: 2) {
                    Spacer(minLength: 0).frame(height: 40)
                    Fit("lbl_third_t", 104, 30).frame(height: 30)
                    T2(text: inThird ? L("الآن") : L("يبدأ") + " " + R2.time(lt.start), size: 11.5)
                    CountDown(to: inThird ? lt.fajr : lt.start, size: 20, color: .white, width: 130, at: d)
                    T2(text: inThird ? L("حتى الفجر") : "", size: 10.5)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// قوس الليل: من المغرب (يمين) إلى الفجر (يسار)، والثلث الأخير مضيء
private struct NightArc: View {
    let nowFraction: Double
    var body: some View {
        GeometryReader { g in
            let R = g.size.width / 2 - 4
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            ZStack {
                Circle().trim(from: 0.5, to: 1).stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: R * 2, height: R * 2).position(c)
                Circle().trim(from: 0.5, to: 0.5 + 0.5 / 3).stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: R * 2, height: R * 2).position(c)
                if nowFraction >= 0 {
                    let t = 1.0 - 0.5 * nowFraction
                    let a = 2 * Double.pi * t
                    Circle().fill(Color.white).frame(width: 7, height: 7)
                        .position(x: c.x + R * CGFloat(cos(a)), y: c.y + R * CGFloat(sin(a)))
                }
                Text(Lang.isEN ? "Fajr" : "الفجر").font(R2.font(9.5)).foregroundStyle(Color.white.opacity(0.5))
                    .position(x: c.x - R, y: c.y + 12)
                Text(Lang.isEN ? "Maghrib" : "المغرب").font(R2.font(9.5)).foregroundStyle(Color.white.opacity(0.5))
                    .position(x: c.x + R, y: c.y + 12)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// الصلاة ٧ — جدول الأسبوع (كبير)
struct R2WeekView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date
        let st = Prayer.state(at: d)
        let keys: [PKey] = [.fajr, .dhuhr, .asr, .maghrib, .isha]
        let idx = [0, 2, 3, 4, 5]
        let days: [Date] = (0..<7).compactMap { Cal.gregCal.date(byAdding: .day, value: $0, to: d) }
        Root(entry: entry) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom) {
                    Fit("wd\(Cal.weekday(d))_t", 150, 44)
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 1) {
                        T2(text: R2.hijriLine(d, year: false), size: 13)
                        T2(text: L("مواقيت الأسبوع") + (Settings.placeName.isEmpty ? "" : " · " + Settings.placeName), size: 11, op: R2.past)
                    }
                }
                .padding(.bottom, 8)
                HStack(spacing: 0) {
                    Color.clear.frame(width: 76)
                    ForEach(keys, id: \.self) { k in
                        PrName(k, 50, 16).frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 4)
                Hair2()
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    let t = Prayer.times(for: day)
                    let h = Cal.dmy(day, greg: false)
                    let friday = Cal.weekday(day) == 5
                    HStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Text(verbatim: R2.weekday(Cal.weekday(day)))
                                .font(R2.font(12, i == 0 || friday ? .bold : .medium)).foregroundStyle(.white)
                            Text(verbatim: R2.num(h.d)).font(R2.font(10.5)).foregroundStyle(Color.white.opacity(R2.past))
                        }
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: 76, alignment: .leading)
                        ForEach(0..<5, id: \.self) { j in
                            let on = i == 0 && st.next.time == t[idx[j]]
                            Digits(text: hm12(t[idx[j]]), size: 13, color: .white, bold: on, tight: true)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    // ارتفاع ثابت للصف: لا يختلف الجدول من خط لآخر (فراغ سطر الأرقام يختلف بين الخطوط)
                    .frame(height: 22)
                    .padding(.vertical, 4).padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(i == 0 ? 0.13 : 0)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(i == 0 ? 0.3 : 0), lineWidth: 0.6))
                    .opacity(i == 0 ? 1 : 0.86)
                }
                Spacer(minLength: 4)
                LeftLine2(next: st.next, at: d, size: 13)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
        }
    }
}

// ═══════════════════════════ التاريخ ═══════════════════════════

/// التاريخ ١ — التاريخ الهجري (صغير): تصميمك المعتمد بالحرف «(٨) جمادى الآخرة» وتحته السنة
struct R2HijriView: View {
    let entry: HEntry
    var body: some View {
        let greg = entry.greg
        let t = Cal.dmy(entry.date, greg: greg)
        let names = ["pn\(t.d)", (greg ? "gm" : "hm") + "\(t.m)"]
        let yname = greg ? "gy\(clampY(t.y, 2020, 2050))" : "hy\(clampY(t.y, 1440, 1470))"
        let sz = dims(entry, SMALL)
        let w = lineWidth(names, GAP_PX, 1)
        let s = min(0.72, (sz.width - 22) / w)
        let ys = s * 104 / 165
        // نفس نسب المعتمد (المتوسط): المسافة بين خط أساس الشهر وخط أساس السنة ١٤٦ بكسل × المقياس
        let gap = 146 * s
        let content = (LINE_UP * s * 0.72 + gap + YEAR_UP * ys * 0.35) / PX
        let top = max(0, (sz.height - content) / 2 - LINE_UP * s * 0.28 / PX)
        let between = (gap - LINE_DN * s - YEAR_UP * ys) / PX
        Root(entry: entry) {
            VStack(spacing: 0) {
                Color.clear.frame(height: top)
                VStack(spacing: between) {
                    CLine(names: names, s: s)
                    CImg(name: yname, s: ys)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// التاريخ ٢ — اسم اليوم (صغير ومتوسط)
struct R2DayView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date, sz = dims(entry, SMALL)
        let wd = "wd\(Cal.weekday(d))_t"
        Root(entry: entry) {
            if isMedium(entry) {
                VStack(spacing: 6) {
                    Fit(wd, sz.width * 0.66, 84).frame(height: 84)
                    T2(text: R2.hijriLine(d) + "  ·  " + R2.gregLine(d), size: 13)
                }
            } else {
                VStack(spacing: 3) {
                    Fit(wd, sz.width - 26, 68).frame(height: 70)
                    T2(text: R2.hijriLine(d, year: false), size: 12.5)
                    T2(text: R2.gregLine(d), size: 11, op: R2.past)
                }
            }
        }
    }
}

/// التاريخ ٣ — الهجري والميلادي (متوسط): السطر المعتمد مرتين جنب بعض
struct R2BothView: View {
    let entry: HEntry
    var body: some View {
        let sz = dims(entry, MEDIUM)
        Root(entry: entry) {
            HStack(spacing: 0) {
                DatePair2(date: entry.date, greg: false, maxW: sz.width / 2 - 24)
                    .frame(maxWidth: .infinity)
                Hair2(vertical: true).padding(.vertical, 40)
                DatePair2(date: entry.date, greg: true, maxW: sz.width / 2 - 24)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// «(اليوم) الشهر» وتحته السنة — بالمقاس المطلوب
struct DatePair2: View {
    let date: Date
    let greg: Bool
    let maxW: CGFloat
    var maxS: CGFloat = 0.6
    var body: some View {
        let t = Cal.dmy(date, greg: greg)
        let names = ["pn\(t.d)", (greg ? "gm" : "hm") + "\(t.m)"]
        let yname = greg ? "gy\(clampY(t.y, 2020, 2050))" : "hy\(clampY(t.y, 1440, 1470))"
        let s = min(maxS, maxW / lineWidth(names, GAP_PX, 1))
        let ys = s * 104 / 165
        let between = (146 * s - LINE_DN * s - YEAR_UP * ys) / PX
        VStack(spacing: between) {
            CLine(names: names, s: s)
            CImg(name: yname, s: ys)
        }
    }
}

/// التاريخ ٤ — التقويم الثلاثي (متوسط): رقمان كبيران واسم اليوم في الوسط
struct R2TripleView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date
        let h = Cal.dmy(d, greg: false), g = Cal.dmy(d, greg: true)
        Root(entry: entry) {
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    GradDigits(text: R2.num(h.d), size: 50)
                    Fit("hm\(h.m)_t", 100, 26)
                }
                .frame(maxWidth: .infinity)
                Hair2(vertical: true).padding(.vertical, 34)
                VStack(spacing: 6) {
                    Fit("wd\(Cal.weekday(d))_t", 128, 52)
                    T2(text: R2.num(h.y) + (Lang.isEN ? " AH · " : " هـ · ") + R2.num(g.y) + (Lang.isEN ? "" : " م"), size: 11, op: R2.past)
                }
                .frame(maxWidth: .infinity)
                Hair2(vertical: true).padding(.vertical, 34)
                VStack(spacing: 2) {
                    GradDigits(text: R2.num(g.d), size: 50)
                    Fit("gm\(g.m)_t", 100, 26)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
        }
    }
}

/// التاريخ ٥ — تقويم الشهر (صغير وكبير)
struct R2CalendarView: View {
    let entry: HEntry
    var body: some View {
        let big = isLarge(entry)
        let greg = entry.greg
        let d = entry.date
        let mi = Cal.monthInfo(d, greg: greg)
        let t = Cal.dmy(d, greg: greg)
        let lead = Cal.weekday(mi.first)
        Root(entry: entry) {
            VStack(spacing: big ? 10 : 5) {
                HStack(alignment: .center) {
                    Fit((greg ? "gm" : "hm") + "\(t.m)_t", big ? 170 : 92, big ? 40 : 21)
                    Spacer(minLength: 4)
                    if big {
                        VStack(alignment: .trailing, spacing: 0) {
                            Digits(text: R2.num(t.y) + (greg ? "" : (Lang.isEN ? " AH" : " هـ")), size: 18, color: .white, bold: true)
                            T2(text: otherMonths(mi.first, len: mi.len, greg: greg), size: 11, op: R2.past)
                        }
                    } else {
                        Digits(text: R2.num(t.y), size: 12, color: Color.white.opacity(R2.dim))
                    }
                }
                MonthGrid2(first: mi.first, len: mi.len, today: t.d, lead: lead, big: big, greg: greg)
                if big {
                    Spacer(minLength: 0)
                    Hair2()
                    if let o = Occasions.next(from: d) {
                        HStack {
                            T2(text: (o.days == 0 ? L("اليوم") : L("المناسبة القادمة")) + ": " + L(o.name), size: 13, op: 0.9)
                            Spacer(minLength: 4)
                            if o.days > 2 {
                                HStack(spacing: 4) {
                                    Digits(text: R2.num(o.days), size: 16, color: .white, bold: true)
                                    T2(text: L(Occasions.daysWord(o.days)), size: 12)
                                }
                            } else if o.days > 0 {
                                // «يوم واحد» و«يومان» تُكتب كلمات (لا «١ يومًا» ولا «٢ يومان»)
                                T2(text: daysCountText(o.days), size: 12)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, big ? 16 : 11).padding(.vertical, big ? 16 : 11)
        }
    }

    private func otherMonths(_ first: Date, len: Int, greg: Bool) -> String {
        let last = Cal.gregCal.date(byAdding: .day, value: len - 1, to: first) ?? first
        let a = Cal.dmy(first, greg: !greg), b = Cal.dmy(last, greg: !greg)
        let m1 = R2.month(a.m, greg: !greg), m2 = R2.month(b.m, greg: !greg)
        return a.m == b.m ? m1 : m1 + " – " + m2
    }
}

private struct MonthGrid2: View {
    let first: Date
    let len: Int
    let today: Int
    let lead: Int
    let big: Bool
    let greg: Bool
    var body: some View {
        let rows = Int(ceil(Double(lead + len) / 7))
        VStack(spacing: big ? 5 : 1) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { c in
                    Text(verbatim: (Lang.isEN ? Words.wlEN : Words.wl)[c])
                        .font(R2.font(big ? 11 : 8.5, .bold))
                        .foregroundStyle(Color.white.opacity(c == 5 ? 0.9 : R2.past))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { c in
                        let n = r * 7 + c - lead + 1
                        cell(n, friday: c == 5)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder private func cell(_ n: Int, friday: Bool) -> some View {
        if n < 1 || n > len {
            Color.clear.frame(height: big ? 34 : 13)
        } else {
            let other = Cal.gregCal.date(byAdding: .day, value: n - 1, to: first).map { Cal.dmy($0, greg: !greg).d } ?? 0
            let on = n == today
            VStack(spacing: 0) {
                Text(verbatim: R2.num(n))
                    .font(digitFont(big ? 15 : 10, bold: on || friday))
                    .foregroundStyle(Color.white.opacity(n < today && !on ? 0.5 : 1))
                if big {
                    Text(verbatim: R2.num(other)).font(digitFont(9.5, bold: false)).foregroundStyle(Color.white.opacity(R2.past))
                }
            }
            .frame(minWidth: big ? 34 : 17, minHeight: big ? 34 : 13)
            .background(RoundedRectangle(cornerRadius: big ? 10 : 5, style: .continuous).fill(Color.white.opacity(on ? 0.2 : 0)))
            .overlay(RoundedRectangle(cornerRadius: big ? 10 : 5, style: .continuous).stroke(Color.white.opacity(on ? 0.4 : 0), lineWidth: 0.6))
        }
    }
}

/// التاريخ ٦ — تقدّم الشهر (صغير)
struct R2ProgressView: View {
    let entry: HEntry
    var body: some View {
        let greg = entry.greg
        let mi = Cal.monthInfo(entry.date, greg: greg)
        let t = Cal.dmy(entry.date, greg: greg)
        let pct = Int((Double(t.d - 1) / Double(max(1, mi.len)) * 100).rounded())
        let left = mi.len - t.d
        Root(entry: entry) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Fit((greg ? "gm" : "hm") + "\(t.m)_t", 96, 24)
                    Spacer(minLength: 4)
                    Digits(text: R2.num(pct) + PCT, size: 19, color: .white, bold: true)
                }
                Spacer(minLength: 6)
                VStack(spacing: 6) {
                    ForEach(0..<Int(ceil(Double(mi.len) / 8)), id: \.self) { r in
                        HStack(spacing: 6) {
                            ForEach(0..<8, id: \.self) { c in
                                let i = r * 8 + c + 1
                                if i <= mi.len {
                                    Circle()
                                        .fill(Color.white.opacity(i < t.d ? 0.9 : (i == t.d ? 1 : 0.16)))
                                        .overlay(Circle().stroke(Color.white.opacity(i == t.d ? 0.4 : 0), lineWidth: 2).padding(-2))
                                        .frame(width: 11, height: 11)
                                } else {
                                    Color.clear.frame(width: 11, height: 11)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 6)
                T2(text: left == 0 ? L("آخر يوم في الشهر") : L("باقي") + " " + (left <= 2 ? daysCountText(left) : R2.num(left) + " " + L(Occasions.daysWord(left))), size: 11.5)
            }
            .padding(14)
        }
    }
}

/// التاريخ ٧ — المناسبة القادمة (صغير)
struct R2OccasionView: View {
    let entry: HEntry
    var body: some View {
        let o = Occasions.next(from: entry.date)
        Root(entry: entry) {
            VStack(spacing: 2) {
                T2(text: L(o?.days == 0 ? "اليوم" : "المناسبة القادمة"), size: 12)
                if let o {
                    Text(verbatim: L(Occasions.short(o.name)))
                        .font(.custom("DecoTypeThuluthII", size: 34))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.45)
                        .frame(height: 46)
                        .padding(.horizontal, 10)
                    if o.days > 2 {
                        HStack(alignment: .lastTextBaseline, spacing: 5) {
                            GradDigits(text: R2.num(o.days), size: 40)
                            T2(text: L(Occasions.daysWord(o.days)), size: 13, op: 0.9)
                        }
                    } else if o.days > 0 {
                        T2(text: daysCountText(o.days), size: 18, op: 0.9).frame(height: 46)
                    }
                    T2(text: R2.hijriLine(o.date, year: false) + " · " + R2.gregLine(o.date, year: false), size: 10.5, op: R2.past)
                        .padding(.top, 3)
                }
            }
        }
    }
}

// ═══════════════════════════ الساعة ═══════════════════════════

private func clockParts(_ d: Date) -> (h: String, m: String) {
    let c = Cal.gregCal.dateComponents([.hour, .minute], from: d)
    let h24 = c.hour ?? 0
    let h = Settings.use24h ? h24 : (h24 % 12 == 0 ? 12 : h24 % 12)
    let hs = Settings.use24h ? String(format: "%02d", h) : "\(h)"
    let ms = String(format: "%02d", c.minute ?? 0)
    return Lang.isEN || Settings.westernDigits ? (hs, ms) : (ar(hs), ar(ms))
}

private struct ClockDots: View {
    var size: CGFloat = 9
    var body: some View {
        VStack(spacing: size * 1.4) {
            Circle().fill(Color.white).frame(width: size, height: size)
            Circle().fill(Color.white).frame(width: size, height: size)
        }
    }
}

/// الساعة ١ — الساعة الكبيرة (متوسط)
struct R2ClockMView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date
        let p = clockParts(d)
        Root(entry: entry) {
            ZStack {
                TickRim(count: 120, lit: 0, major: 10)
                VStack(spacing: 0) {
                    T2(text: R2.weekday(Cal.weekday(d)) + " " + R2.gregLine(d, year: false), size: 12.5)
                    HStack(spacing: 14) {
                        GradDigits(text: p.h, size: 76)
                        ClockDots(size: 9)
                        GradDigits(text: p.m, size: 76)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.vertical, 2)
                    T2(text: R2.hijriLine(d), size: 12.5)
                }
            }
        }
    }
}

/// الساعة ٢ — ساعة الإطار (صغير): الشرطات تمتلئ مع الدقائق
struct R2ClockSView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date
        let p = clockParts(d)
        let minute = Cal.gregCal.component(.minute, from: d)
        Root(entry: entry) {
            ZStack {
                TickRim(count: 60, lit: max(1, minute))
                VStack(spacing: 2) {
                    Fit("wd\(Cal.weekday(d))_t", 104, 26).frame(height: 26)
                    HStack(spacing: 7) {
                        GradDigits(text: p.h, size: 46)
                        ClockDots(size: 6)
                        GradDigits(text: p.m, size: 46)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    T2(text: R2.hijriLine(d, year: false), size: 11)
                }
            }
        }
    }
}

/// الساعة ٣ — ساعة العقارب (صغير): زخرفة هندسية (نجمة اثنتي عشرة) خلف عقارب محترفة
struct R2AnalogView: View {
    let entry: HEntry
    var body: some View {
        Root(entry: entry) {
            AnalogFace(date: entry.date, inApp: entry.inApp, dayName: R2.weekday(Cal.weekday(entry.date)))
                .padding(9)
        }
    }
}

/// زخرفة أرابيسك: نجمة مركزية واثنتا عشرة بتلة سداسية
struct Arabesque12: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY), R = min(rect.width, rect.height) / 2
        func pt(_ r: CGFloat, _ deg: Double) -> CGPoint {
            let a = deg * .pi / 180
            return CGPoint(x: c.x + r * CGFloat(sin(a)), y: c.y - r * CGFloat(cos(a)))
        }
        for i in 0..<12 {
            let a = Double(i) * 30
            p.move(to: pt(R * 0.30, a))
            p.addLine(to: pt(R * 0.50, a - 10))
            p.addLine(to: pt(R * 0.86, a - 8))
            p.addLine(to: pt(R * 0.99, a))
            p.addLine(to: pt(R * 0.86, a + 8))
            p.addLine(to: pt(R * 0.50, a + 10))
            p.closeSubpath()
        }
        // النجمة المركزية
        for i in 0..<24 {
            let r = i % 2 == 0 ? R * 0.27 : R * 0.17
            let q = pt(r, Double(i) * 15)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }
}

struct AnalogFace: View {
    let date: Date
    var inApp = false
    var dayName: String = ""
    var body: some View {
        GeometryReader { g in
            let R = min(g.size.width, g.size.height) / 2
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            ZStack {
                Arabesque12().fill(Color.white.opacity(0.07))
                    .frame(width: R * 2, height: R * 2).position(c)
                Arabesque12().stroke(Color.white.opacity(0.13), lineWidth: 0.8)
                    .frame(width: R * 2, height: R * 2).position(c)
                ForEach(0..<4, id: \.self) { i in
                    let a = Double(i) * .pi / 2
                    Text(verbatim: R2.num([12, 3, 6, 9][i]))
                        .font(digitFont(16, bold: true)).foregroundStyle(Color.white.opacity(0.9))
                        .position(x: c.x + (R - 13) * CGFloat(sin(a)), y: c.y - (R - 13) * CGFloat(cos(a)))
                }
                if !dayName.isEmpty {
                    Text(verbatim: dayName).font(R2.font(10.5)).foregroundStyle(Color.white.opacity(0.55))
                        .position(x: c.x, y: c.y + R * 0.42)
                }
                ClockHands(size: R * 2, inApp: inApp, date: date).position(c)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}


// ═══════════════════════════ الطقس ═══════════════════════════

private func wxTemp(_ v: Double?) -> String {
    guard let v else { return "--" }
    return R2.num(Int((Settings.fahrenheit ? v * 9 / 5 + 32 : v).rounded()))
}

/// الحرارة الكبيرة بعلامة الدرجة
private struct BigTemp: View {
    let w: WeatherData?
    var size: CGFloat = 54
    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            GradDigits(text: wxTemp(w?.temp), size: size)
            Text(verbatim: "°").font(digitFont(size * 0.5, bold: true)).foregroundStyle(.white)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// الطقس ١ — الطقس (صغير)
struct R2WeatherView: View {
    let entry: HEntry
    var body: some View {
        let w = entry.weather
        Root(entry: entry) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    T2(text: Settings.placeName, size: 12, weight: .bold, op: 1)
                    Spacer(minLength: 4)
                    CImg(name: Weather.icon(w), s: 0.27)
                }
                BigTemp(w: w, size: 54).padding(.top, 4)
                Spacer(minLength: 2)
                Fit(Weather.word(w), 120, 26).frame(height: 26)
                T2(text: (Lang.isEN ? "H " : "ع ") + wxTemp(w?.hi) + "°  " + (Lang.isEN ? "L " : "ص ") + wxTemp(w?.lo) + "°", size: 11.5)
                    .padding(.top, 2)
            }
            .padding(14)
        }
    }
}

/// الطقس ٢ — الطقس والأيام (متوسط)
struct R2WeatherDaysView: View {
    let entry: HEntry
    var body: some View {
        let w = entry.weather
        let days = Array((w?.days ?? []).dropFirst().prefix(5))
        Root(entry: entry) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    T2(text: Settings.placeName, size: 12, weight: .bold, op: 1)
                    BigTemp(w: w, size: 50).padding(.top, 4)
                    Spacer(minLength: 2)
                    Fit(Weather.word(w), 110, 24).frame(height: 24)
                    T2(text: L("الرطوبة") + " " + (w?.humidity.map { R2.num($0) + PCT } ?? "--") + " · " + Weather.windText(w), size: 10.5)
                }
                .frame(width: 124, alignment: .leading)
                Hair2(vertical: true)
                VStack(spacing: 0) {
                    if days.isEmpty {
                        T2(text: L("غير متوفر"), size: 12)
                    }
                    ForEach(Array(days.enumerated()), id: \.offset) { _, dd in
                        let day = Date(timeIntervalSince1970: dd.t)
                        HStack(spacing: 6) {
                            Text(verbatim: R2.weekday(Cal.weekday(day))).font(R2.font(12.5)).foregroundStyle(.white)
                                .frame(width: 58, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
                            CImg(name: Weather.iconFor(code: dd.code), s: 0.2)
                            Spacer(minLength: 2)
                            HStack(spacing: 6) {
                                Digits(text: wxTemp(dd.hi) + "°", size: 13, color: .white, bold: true)
                                Digits(text: wxTemp(dd.lo) + "°", size: 13, color: Color.white.opacity(R2.past))
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
    }
}

/// الطقس ٣ — اليوم والطقس (متوسط)
struct R2DayWeatherView: View {
    let entry: HEntry
    var body: some View {
        let d = entry.date, w = entry.weather
        let st = Prayer.state(at: d)
        Root(entry: entry) {
            HStack(spacing: 12) {
                VStack(spacing: 3) {
                    Fit("wd\(Cal.weekday(d))_t", 170, 58).frame(height: 58)
                    T2(text: R2.hijriLine(d), size: 12)
                    LeftLine2(next: st.next, at: d, size: 12.5).padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                Hair2(vertical: true).padding(.vertical, 12)
                VStack(spacing: 2) {
                    CImg(name: Weather.icon(w), s: 0.4)
                    BigTemp(w: w, size: 42)
                    T2(text: (Lang.isEN ? "H " : "ع ") + wxTemp(w?.hi) + "°  " + (Lang.isEN ? "L " : "ص ") + wxTemp(w?.lo) + "°", size: 10.5)
                }
                .frame(width: 96)
            }
            .padding(.horizontal, 14)
        }
    }
}

// ═══════════════════════════ القرآن والأذكار ═══════════════════════════

/// القرآن ١ — الورد (صغير): ثلاثون نقطة للأجزاء، وزرّا التقدّم يعملان من الويدجت
struct R2WirdView: View {
    let entry: HEntry
    var body: some View {
        let juz = Wird.juz
        Root(entry: entry) {
            VStack(spacing: 4) {
                Fit("lbl_wird_t", 100, 30).frame(height: 30)
                HStack(spacing: 4) {
                    T2(text: L("الجزء"), size: 12.5, op: 0.9)
                    Digits(text: R2.num(juz), size: 15, color: .white, bold: true)
                    T2(text: L("من") + " " + R2.num(30), size: 12.5)
                }
                VStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { r in
                        HStack(spacing: 5) {
                            ForEach(0..<10, id: \.self) { c in
                                let i = r * 10 + c + 1
                                Circle()
                                    .fill(Color.white.opacity(i < juz ? 0.9 : (i == juz ? 1 : 0.16)))
                                    .overlay(Circle().stroke(Color.white.opacity(i == juz ? 0.4 : 0), lineWidth: 2).padding(-2))
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                }
                .padding(.top, 4)
                Spacer(minLength: 2)
                HStack(spacing: 10) {
                    Button(intent: WirdStepIntent(delta: -1)) { stepIcon("minus") }.buttonStyle(.plain)
                    T2(text: L("الختمة") + " " + R2.num(Int((Wird.progress * 100).rounded())) + PCT, size: 11)
                    Button(intent: WirdStepIntent(delta: 1)) { stepIcon("plus") }.buttonStyle(.plain)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.vertical, 12).padding(.horizontal, 10)
        }
    }
    private func stepIcon(_ s: String) -> some View {
        Image(systemName: s).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.white.opacity(0.14)))
            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.6))
    }
}

/// القرآن ٢ — آية اليوم (متوسط)
struct R2VerseView: View {
    let entry: HEntry
    var body: some View {
        let v = Verses.of(entry.date)
        Root(entry: entry) {
            VStack(spacing: 6) {
                HStack {
                    T2(text: L("آية اليوم"), size: 11.5)
                    Spacer()
                }
                Spacer(minLength: 0)
                Text(verbatim: "﴿" + v.0 + "﴾")
                    .font(.custom("Amiri-Bold", size: 24))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3).minimumScaleFactor(0.6)
                T2(text: L("سورة") + " " + v.1, size: 12)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
    }
}

/// القرآن ٣ — الذكر (صغير ومتوسط): الضغط على الحلقة يعدّ
struct R2DhikrView: View {
    let entry: HEntry
    var body: some View {
        let c = Adhkar.current(entry.date)
        let p = Double(c.count) / Double(max(1, c.item.times))
        let done = c.count >= c.item.times
        Root(entry: entry) {
            if isMedium(entry) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            T2(text: Adhkar.title(c.period), size: 12, weight: .bold, op: 0.9)
                            if !c.item.source.isEmpty { T2(text: "· " + L(c.item.source), size: 11) }
                        }
                        Text(verbatim: c.item.text)
                            .font(.custom("Amiri-Bold", size: 19))
                            .foregroundStyle(.white)
                            .lineLimit(3).minimumScaleFactor(0.6)
                            .lineSpacing(2)
                        Spacer(minLength: 0)
                        Button(intent: DhikrNextIntent()) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left.arrow.right").font(.system(size: 10, weight: .bold))
                                Text(verbatim: L("ذكر آخر")).font(R2.font(11, .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    counter(c.count, c.item.times, p: p, done: done, size: 112)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            } else {
                VStack(spacing: 4) {
                    counter(c.count, c.item.times, p: p, done: done, size: 104)
                    Text(verbatim: c.item.text)
                        .font(.custom("Amiri-Bold", size: 14))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.55)
                        .padding(.horizontal, 10)
                }
            }
        }
    }

    private func counter(_ n: Int, _ total: Int, p: Double, done: Bool, size: CGFloat) -> some View {
        Button(intent: DhikrTapIntent()) {
            ZStack {
                Ring2(p: p, line: 5)
                VStack(spacing: 0) {
                    if done {
                        Image(systemName: "checkmark").font(.system(size: size * 0.24, weight: .bold)).foregroundStyle(.white)
                    } else {
                        GradDigits(text: R2.num(n), size: size * 0.32)
                    }
                    T2(text: L("من") + " " + R2.num(total), size: 11)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// ═══════════════════════════ المسموع والمرئي ═══════════════════════════

private func liveRow(_ np: NowPlaying) -> some View {
    HStack(spacing: 5) {
        if np.live {
            Circle().fill(Color.white).frame(width: 6, height: 6).shadow(color: .white, radius: 3)
            Text(verbatim: Lang.isEN ? "LIVE" : "مباشر").font(R2.font(11, .bold)).foregroundStyle(.white)
        } else {
            Text(verbatim: L(np.playing ? "يُشغَّل الآن" : "تابع الاستماع")).font(R2.font(11, .bold))
                .foregroundStyle(Color.white.opacity(R2.dim))
        }
    }
}

private func sourceIcon(_ s: MediaSource) -> String {
    switch s {
    case .quran: return "book.closed"
    case .radio: return "dot.radiowaves.left.and.right"
    case .music: return "music.note"
    case .files: return "waveform"
    }
}

/// الوسائط ١ — المشغّل (صغير): الإذاعة أو القرآن أو Apple Music
struct R2PlayerView: View {
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    liveRow(np)
                    Spacer(minLength: 4)
                    Image(systemName: sourceIcon(np.source)).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                }
                Text(verbatim: np.title).font(R2.font(16, .bold)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.7).padding(.top, 8)
                T2(text: np.subtitle, size: 11.5)
                Spacer(minLength: 4)
                HStack {
                    MBtn(action: "prev", icon: "backward.fill", size: 34)
                    Spacer(minLength: 0)
                    MBtn(action: "toggle", icon: np.playing ? (np.live ? "stop.fill" : "pause.fill") : "play.fill", size: 48, solid: true)
                    Spacer(minLength: 0)
                    MBtn(action: "next", icon: "forward.fill", size: 34)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(14)
        }
    }
}

/// الوسائط ٢ — المشغّل الكبير (متوسط): ما يُشغَّل الآن، أو «تابع الاستماع» للقرآن
struct R2PlayerMView: View {
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    liveRow(np)
                    Group {
                        if np.source == .quran {
                            Text(verbatim: np.title).font(.custom("DecoTypeThuluthII", size: 38))
                        } else {
                            Text(verbatim: np.title).font(R2.font(19, .bold))
                        }
                    }
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                    .frame(height: 46, alignment: .leading)
                    T2(text: np.subtitle, size: 12)
                    Spacer(minLength: 4)
                    MProgress(np: np)
                    if !np.live { MTimes(np: np) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 10) {
                    MBtn(action: "toggle", icon: np.playing ? (np.live ? "stop.fill" : "pause.fill") : "play.fill", size: 56, solid: true)
                    HStack(spacing: 12) {
                        MBtn(action: "prev", icon: "backward.fill", size: 34)
                        MBtn(action: "next", icon: "forward.fill", size: 34)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }
}

/// الوسائط ٣ — بكرة الإذاعات (متوسط): الإذاعة الحالية وبجانبها قائمتك
struct R2TunerView: View {
    let entry: HEntry
    var body: some View {
        let np = NowPlaying.display(for: "radio")
        let list = Reel.window(Stations.reel, kind: "radio2", count: 3)
        let cur = AppGroup.defaults.string(forKey: "last_station")
        Root(entry: entry) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Circle().fill(Color.white.opacity(np.playing ? 1 : 0.4)).frame(width: 6, height: 6)
                        Text(verbatim: Lang.isEN ? "LIVE" : "مباشر").font(R2.font(11, .bold)).foregroundStyle(Color.white.opacity(0.85))
                    }
                    Text(verbatim: np.title).font(R2.font(17, .bold)).foregroundStyle(.white)
                        .lineLimit(2).minimumScaleFactor(0.7).padding(.top, 4)
                    T2(text: np.subtitle, size: 11.5)
                    Spacer(minLength: 4)
                    HStack(spacing: 10) {
                        MBtn(action: "prev", icon: "backward.fill", size: 32)
                        MBtn(action: "toggle", icon: np.playing ? "stop.fill" : "play.fill", size: 46, solid: true)
                        MBtn(action: "next", icon: "forward.fill", size: 32)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
                .frame(width: 150, alignment: .leading)
                Hair2(vertical: true)
                VStack(spacing: 5) {
                    ForEach(list, id: \.url) { s in
                        Button(intent: MediaControlIntent("station", source: s.url)) {
                            HStack(spacing: 8) {
                                ReelLogo(url: s.favicon, icon: "dot.radiowaves.left.and.right", color: .white, size: 24)
                                Text(verbatim: s.name).font(R2.font(12, .bold)).foregroundStyle(.white)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 7).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(s.url == cur ? 0.18 : 0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(s.url == cur ? 0.4 : 0.1), lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 10) {
                        Button(intent: ReelIntent("radio2", -1)) { arrow(Lang.isEN ? "chevron.left" : "chevron.right") }.buttonStyle(.plain)
                        Button(intent: ReelIntent("radio2", 1)) { arrow(Lang.isEN ? "chevron.right" : "chevron.left") }.buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
        }
    }
    private func arrow(_ s: String) -> some View {
        Image(systemName: s).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            .frame(width: 24, height: 24).background(Circle().fill(Color.white.opacity(0.12)))
    }
}

/// القنوات ١ — قناة (صغير)
struct R2ChannelView: View {
    let entry: HEntry
    var body: some View {
        let list = TVChannels.recentChannels.isEmpty ? TVChannels.reel : TVChannels.recentChannels
        let c = Reel.window(list, kind: "tv2", count: 1).first
        Root(entry: entry) {
            VStack(spacing: 6) {
                if let c {
                    Button(intent: OpenTVIntent(c.id)) {
                        VStack(spacing: 5) {
                            ReelLogo(url: c.logo, icon: c.cat.icon, color: .white, size: 70, corner: 20)
                            Text(verbatim: c.name).font(R2.font(13, .bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                            HStack(spacing: 4) {
                                Circle().fill(Color.white).frame(width: 5, height: 5)
                                Text(verbatim: L("اضغط للمشاهدة")).font(R2.font(10.5)).foregroundStyle(Color.white.opacity(R2.dim))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Button(intent: ReelIntent("tv2", 1)) { tvArrow("chevron.left") }.buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Button(intent: ReelIntent("tv2", -1)) { tvArrow("chevron.right") }.buttonStyle(.plain)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(12)
        }
    }
}

private func tvArrow(_ s: String) -> some View {
    Image(systemName: s).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        .frame(width: 26, height: 26).background(Circle().fill(Color.white.opacity(0.12)))
}

/// القنوات ٢ — بكرة القنوات (متوسط): شاهدت مؤخرًا أولًا
struct R2ChannelsView: View {
    let entry: HEntry
    var body: some View {
        let recent = TVChannels.recentChannels
        let all = recent + TVChannels.reel.filter { c in !recent.contains { $0.id == c.id } }
        let list = Reel.window(all, kind: "tv3", count: 4)
        Root(entry: entry) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "tv").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    Text(verbatim: L(recent.isEmpty ? "القنوات" : "شاهدت مؤخرًا")).font(R2.font(13, .bold)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Button(intent: ReelIntent("tv3", -1)) { tvArrow(Lang.isEN ? "chevron.left" : "chevron.right") }.buttonStyle(.plain)
                        Button(intent: ReelIntent("tv3", 1)) { tvArrow(Lang.isEN ? "chevron.right" : "chevron.left") }.buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(list) { c in
                        Link(destination: URL(string: "miqat://tv/" + c.id) ?? URL(string: "miqat://media")!) {
                            VStack(spacing: 5) {
                                ReelLogo(url: c.logo, icon: c.cat.icon, color: .white, size: 56, corner: 15)
                                Text(verbatim: c.name).font(R2.font(11, .bold)).foregroundStyle(.white)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
    }
}

// ═══════════════════════════ الأدوات ═══════════════════════════

/// زر يفتح صفحة في رفيقي
private struct OpenButton<Label: View>: View {
    let target: String
    @ViewBuilder let label: () -> Label
    var body: some View {
        Button(intent: OpenRafiqiIntent(target: target)) { label() }.buttonStyle(.plain)
    }
}

/// الأدوات ١ — الماسح (صغير)
struct R2ScanView: View {
    let entry: HEntry
    var body: some View {
        Root(entry: entry, url: URL(string: "miqat://open/scanner")) {
            VStack(spacing: 6) {
                OpenButton(target: "scanner") {
                    VStack(spacing: 7) {
                        ScanGlyph()
                            .frame(width: 44, height: 44)
                            .frame(width: 84, height: 84)
                            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.1)))
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 0.7))
                        Text(verbatim: L("مسح مستند")).font(R2.font(13.5, .bold)).foregroundStyle(.white)
                    }
                }
                HStack(spacing: 8) {
                    OpenButton(target: "qr") { chip("qrcode", L("رمز")) }
                    OpenButton(target: "idcard") { chip("person.text.rectangle", L("هوية")) }
                }
            }
            .padding(12)
        }
    }
    private func chip(_ icon: String, _ t: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(verbatim: t).font(R2.font(11, .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}

/// إطار الماسح (أربع زوايا وخط)
private struct ScanGlyph: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height), l = s * 0.28, r = s * 0.12
            Path { p in
                p.move(to: CGPoint(x: 0, y: l)); p.addLine(to: CGPoint(x: 0, y: r))
                p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero); p.addLine(to: CGPoint(x: l, y: 0))
                p.move(to: CGPoint(x: s - l, y: 0)); p.addLine(to: CGPoint(x: s - r, y: 0))
                p.addQuadCurve(to: CGPoint(x: s, y: r), control: CGPoint(x: s, y: 0)); p.addLine(to: CGPoint(x: s, y: l))
                p.move(to: CGPoint(x: s, y: s - l)); p.addLine(to: CGPoint(x: s, y: s - r))
                p.addQuadCurve(to: CGPoint(x: s - r, y: s), control: CGPoint(x: s, y: s)); p.addLine(to: CGPoint(x: s - l, y: s))
                p.move(to: CGPoint(x: l, y: s)); p.addLine(to: CGPoint(x: r, y: s))
                p.addQuadCurve(to: CGPoint(x: 0, y: s - r), control: CGPoint(x: 0, y: s)); p.addLine(to: CGPoint(x: 0, y: s - l))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            Path { p in p.move(to: CGPoint(x: s * 0.26, y: s / 2)); p.addLine(to: CGPoint(x: s * 0.74, y: s / 2)) }
                .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// الأدوات ٢ — المساحة (صغير)
struct R2StorageView: View {
    let entry: HEntry
    var body: some View {
        let v = WFilesStore.volume()
        let snap = WFilesStore.load()
        let used = v.map { Double($0.used) / Double(max(1, $0.total)) } ?? 0
        Root(entry: entry, url: URL(string: "miqat://open/storage")) {
            VStack(spacing: 6) {
                ZStack {
                    Ring2(p: used, line: 9)
                    // مسافة بين النسبة وكلمتها: كانت الأرقام تنزل على «مستخدم» في كل الخطوط
                    VStack(spacing: 7) {
                        GradDigits(text: R2.num(Int((used * 100).rounded())) + PCT, size: 25)
                        T2(text: L("مستخدم"), size: 11)
                    }
                }
                .frame(width: 112, height: 112)
                if let v {
                    T2(text: L("متاح") + " " + WFilesStore.gb(v.total - v.used), size: 11.5, op: 0.9)
                }
                if snap.rafiqiBytes > 0 {
                    T2(text: L("ملفات رفيقي") + " " + WFilesStore.gb(snap.rafiqiBytes), size: 10.5, op: R2.past)
                }
            }
        }
    }
}

/// الأدوات ٣ — آخر الملفات (متوسط)
struct R2FilesView: View {
    let entry: HEntry
    var body: some View {
        let snap = WFilesStore.load()
        Root(entry: entry, url: URL(string: "miqat://open/files")) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "doc").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    Text(verbatim: L("آخر الملفات")).font(R2.font(13, .bold)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    if let v = WFilesStore.volume() {
                        T2(text: WFilesStore.gb(v.total - v.used) + " " + L("متاحة"), size: 11)
                    }
                }
                Spacer(minLength: 0)
                if snap.locked {
                    VStack(spacing: 4) {
                        Image(systemName: "lock.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                        T2(text: L("الملفات مقفلة"), size: 12)
                    }
                    Spacer(minLength: 0)
                } else if snap.files.isEmpty {
                    T2(text: L("لا توجد ملفات بعد"), size: 12)
                    Spacer(minLength: 0)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(snap.files.prefix(4)) { f in
                            OpenButton(target: "file:" + f.rel) { FileTile2(file: f) }
                        }
                        ForEach(0..<max(0, 4 - min(4, snap.files.count)), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
    }
}

private struct FileTile2: View {
    let file: WFile
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.1))
                if let img = WFilesStore.thumb(file.thumb) {
                    SImage(img: img).scaledToFill()
                        .frame(width: 74, height: 56).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                if file.kind == "video" {
                    Image(systemName: "play.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Circle().fill(Color.black.opacity(0.4)))
                } else if WFilesStore.thumb(file.thumb) == nil {
                    Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: 74, height: 56)
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 0.6))
            // الصورة والاسم يُخفيان والجوال مقفل (StandBy وشاشة القفل)
            .privacySensitive()
            Text(verbatim: (file.name as NSString).deletingPathExtension)
                .font(R2.font(11, .bold)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                .privacySensitive()
            Text(verbatim: when).font(R2.font(9.5)).foregroundStyle(Color.white.opacity(R2.past)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
    private var icon: String {
        switch file.kind {
        case "image": return "photo"
        case "audio": return "waveform"
        case "document": return "doc.text"
        case "archive": return "doc.zipper"
        default: return "doc"
        }
    }
    private var when: String {
        let d = Date(timeIntervalSince1970: file.date)
        let g = Cal.gregCal
        if g.isDateInToday(d) { return R2.time(d) }
        if g.isDateInYesterday(d) { return L("أمس") }
        return R2.weekday(Cal.weekday(d))
    }
}

/// الأدوات ٤ — القبلة (صغير): الاتجاه من الشمال والمسافة (الويدجت لا تقرأ البوصلة؛ الضغطة تفتحها)
struct R2QiblaView: View {
    let entry: HEntry
    var body: some View {
        let b = QiblaMath.bearing()
        let km = QiblaMath.distance()
        Root(entry: entry, url: URL(string: "miqat://open/qibla")) {
            ZStack {
                QiblaDial(bearing: b).padding(10)
                VStack(spacing: 0) {
                    Text(verbatim: L("القبلة")).font(.custom("DecoTypeThuluthII", size: 30)).foregroundStyle(.white)
                        .frame(height: 34)
                    HStack(alignment: .top, spacing: 1) {
                        GradDigits(text: R2.num(Int(b.rounded())), size: 30)
                        Text(verbatim: "°").font(digitFont(16, bold: true)).foregroundStyle(.white)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    T2(text: L("من الشمال") + " · " + R2.num(Int(km.rounded())) + " " + L("كم"), size: 10.5)
                        .padding(.top, 3)
                }
                .padding(.top, 6)
            }
        }
    }
}

private struct QiblaDial: View {
    let bearing: Double
    var body: some View {
        GeometryReader { g in
            let R = min(g.size.width, g.size.height) / 2
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            let q = bearing * .pi / 180
            ZStack {
                Path { p in
                    for i in 0..<72 {
                        let a = Double(i) * 5 * .pi / 180
                        let major = i % 18 == 0
                        p.move(to: CGPoint(x: c.x + R * CGFloat(sin(a)), y: c.y - R * CGFloat(cos(a))))
                        p.addLine(to: CGPoint(x: c.x + (R - (major ? 7 : 4)) * CGFloat(sin(a)), y: c.y - (R - (major ? 7 : 4)) * CGFloat(cos(a))))
                    }
                }
                .stroke(Color.white.opacity(0.32), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                Text(verbatim: Lang.isEN ? "N" : "ش").font(R2.font(10, .bold)).foregroundStyle(.white)
                    .position(x: c.x, y: c.y - R + 14)
                Path { p in
                    p.move(to: CGPoint(x: c.x + (R + 1) * CGFloat(sin(q - 0.09)), y: c.y - (R + 1) * CGFloat(cos(q - 0.09))))
                    p.addLine(to: CGPoint(x: c.x + (R - 13) * CGFloat(sin(q)), y: c.y - (R - 13) * CGFloat(cos(q))))
                    p.addLine(to: CGPoint(x: c.x + (R + 1) * CGFloat(sin(q + 0.09)), y: c.y - (R + 1) * CGFloat(cos(q + 0.09))))
                    p.closeSubpath()
                }
                .fill(Color.white)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}
