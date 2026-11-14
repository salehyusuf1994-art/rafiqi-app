import SwiftUI
import WidgetKit
import AppIntents

// ويدجت الإصدار ١٫٢ — بنفس روح التصميم المعتمد (خط الثلث، لون TXT، خلفية الويدجت)

func yLine(_ y: Int, greg: Bool) -> String {
    greg ? "gyl\(clampY(y, 2020, 2050))" : "hyl\(clampY(y, 1440, 1470))"
}

/// يحوّل الأرقام العربية في نص ثابت إلى الإنجليزية إن اختيرت
func prefDigits(_ s: String) -> String {
    guard Settings.westernDigits else { return s }
    return String(s.map { c -> Character in
        if let i = arDigits.firstIndex(of: c) { return Character(String(i)) }
        return c
    })
}

/// قائمة صلوات اليوم (وبعد العشاء: الغد)
func prayerListDay(_ now: Date) -> Date {
    let t = Prayer.dayTimes(now)
    if now >= t[5].time { return Cal.gregCal.date(byAdding: .day, value: 1, to: now) ?? now }
    return now
}

/// نوافذ الصلوات الخمس وتقدّم كل وحدة (٠…١)
func prayerWindows(_ now: Date) -> [(key: PKey, time: Date, p: Double)] {
    let g = Cal.gregCal
    let today = Prayer.dayTimes(now)
    let day = now < today[0].time ? (g.date(byAdding: .day, value: -1, to: now) ?? now) : now
    let t = Prayer.dayTimes(day)
    let mid = Prayer.midnight(after: day)?.time ?? t[5].time.addingTimeInterval(4 * 3600)
    let spans: [(PTime, Date)] = [(t[0], t[1].time), (t[2], t[3].time), (t[3], t[4].time), (t[4], t[5].time), (t[5], mid)]
    var out: [(key: PKey, time: Date, p: Double)] = []
    for (s, end) in spans {
        let len = end.timeIntervalSince(s.time)
        let p = len > 0 ? now.timeIntervalSince(s.time) / len : 0
        out.append((key: s.key, time: s.time, p: min(1, max(0, p))))
    }
    return out
}

// MARK: - قائمة الصلوات بالنقاط — صغير

struct PrayerDotsView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.state(at: entry.date, sunrise: true)
        let list = Prayer.dayTimes(prayerListDay(entry.date))
        Root(entry: entry) {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, p in
                    let on = p.time == st.next.time
                    HStack(spacing: 7) {
                        Circle().fill(on ? Color.white : TXT.opacity(0.38))
                            .frame(width: on ? 8 : 5, height: on ? 8 : 5)
                            .frame(width: 10)
                        PrName(p.key, 58, 19, on ? 1 : 0.75)
                            .frame(width: 60, alignment: .leading)
                        Spacer(minLength: 0)
                        Digits(text: hm12(p.time), size: on ? 15 : 14, color: on ? .white : Color.white.opacity(0.72), bold: on)
                    }
                    .frame(height: 22)
                    .padding(.horizontal, 6)
                    .background {
                        if on { Capsule().fill(Color.white.opacity(0.14)) }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - حلقات الصلوات الخمس — متوسط

struct PrayerRingsView: View {
    let entry: HEntry
    /// سطر واحد بدون بطاقة الصلاة القادمة
    var compact = false
    var body: some View {
        let ws = prayerWindows(entry.date)
        let st = Prayer.state(at: entry.date)
        Root(entry: entry) {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(Array(ws.enumerated()), id: \.offset) { _, w in
                        let cur = w.p > 0 && w.p < 1
                        VStack(spacing: 3) {
                            PrName(w.key, 58, 19, cur ? 1 : 0.8)
                            ZStack {
                                Circle().fill(Color.white.opacity(0.06))
                                Circle().stroke(Color.white.opacity(0.18), lineWidth: 4)
                                Circle().trim(from: 0, to: max(0.001, w.p))
                                    .stroke(cur ? Color.white : TXT.opacity(0.71), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .ringStart()
                                PrIcon(key: w.key, size: 15, color: cur ? .white : TXT.opacity(0.71))
                            }
                            .frame(width: compact ? 50 : 44, height: compact ? 50 : 44)
                            if !compact {
                                Digits(text: hm12(w.time), size: 12.5, color: cur ? .white : Color.white.opacity(0.72), bold: cur)
                            }
                        }
                        .frame(width: 66)
                    }
                }
                if !compact {
                    HStack(spacing: 8) {
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 6) {
                                    Fit("pr_\(st.next.key.rawValue)_t", 62, 24)
                                    Digits(text: hm12(st.next.time), size: 16, color: .white, bold: true)
                                }
                                Fit("lbl_next2_t", 76, 14, 0.7)
                            }
                            Spacer(minLength: 0)
                            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 30)
                            Spacer(minLength: 0)
                            VStack(spacing: 0) {
                                CountDown(to: st.next.time, size: 18, color: .white, width: 90, at: entry.date)
                                Fit("lbl_left_t", 40, 14, 0.7)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.18), lineWidth: 3)
                            Circle().trim(from: 0, to: max(0.01, st.progress))
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .ringStart()
                            PrIcon(key: st.next.key, size: 13, color: .white)
                        }
                        .frame(width: 34, height: 34)
                        .frame(width: 50, height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .frame(width: 336)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - أعمدة الصلوات — متوسط

struct PrayerCapsView: View {
    let entry: HEntry
    var body: some View {
        let ws = prayerWindows(entry.date)
        let st = Prayer.state(at: entry.date)
        Root(entry: entry) {
            HStack(spacing: 10) {
                VStack(spacing: 2) {
                    Fit("lbl_next2_t", 110, 22, 0.8)
                    Fit("pr_\(st.next.key.rawValue)_t", 110, 44)
                    Digits(text: hm12(st.next.time), size: 16, color: TXT)
                    CountDown(to: st.next.time, size: 22, color: .white, width: 112, at: entry.date)
                }
                .frame(width: 118)
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 110)
                HStack(spacing: 6) {
                    ForEach(Array(ws.enumerated()), id: \.offset) { _, w in
                        let cur = w.p > 0 && w.p < 1
                        VStack(spacing: 3) {
                            ZStack(alignment: .bottom) {
                                Capsule().fill(Color.white.opacity(0.16))
                                Capsule().fill(cur ? Color.white : TXT.opacity(0.67))
                                    .frame(height: max(cur ? 6 : 0, 76 * w.p))
                            }
                            .frame(width: 18, height: 76)
                            PrName(w.key, 40, 16, cur ? 1 : 0.8)
                            Digits(text: hm12(w.time), size: 11, color: cur ? .white : Color.white.opacity(0.7), bold: cur)
                        }
                        .frame(width: 40)
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - حلقة الإفطار / الإمساك — صغير

struct IftarRingView: View {
    let entry: HEntry
    var body: some View {
        let now = entry.date
        let t = Prayer.times(for: now)
        let ram = Cal.ramadan(now).inRamadan
        let day = now >= t[0] && now < t[4]
        let n = Prayer.night(around: now)
        let start = day ? t[0] : n.maghrib, end = day ? t[4] : n.fajr
        let len = end.timeIntervalSince(start)
        let p = len > 0 ? min(1, max(0.003, now.timeIntervalSince(start) / len)) : 0
        let label = day ? (ram ? "lbl_iftar_t" : "pr_maghrib_t") : (ram ? "lbl_imsak_t" : "pr_fajr_t")
        Root(entry: entry) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.22), lineWidth: 6).frame(width: 142, height: 142)
                Circle().trim(from: 0, to: p)
                    .stroke(TXT, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .ringStart().frame(width: 142, height: 142)
                VStack(spacing: 2) {
                    Image(systemName: day ? "sunset.fill" : "sparkles").font(.system(size: 14)).foregroundStyle(TXT.opacity(0.67))
                    Fit(label, 96, 36)
                    Digits(text: hm12(end), size: 16, color: TXT)
                    CountDown(to: end, size: 19, color: .white, width: 110, at: entry.date)
                }
            }
        }
    }
}

// MARK: - الثلث الأخير من الليل — صغير

struct LastThirdView: View {
    let entry: HEntry
    var body: some View {
        let now = entry.date
        let lt = Prayer.lastThird(around: now)
        let len = lt.fajr.timeIntervalSince(lt.maghrib)
        let f = len > 0 ? now.timeIntervalSince(lt.maghrib) / len : 0
        let inNight = f >= 0 && f <= 1
        let inThird = now >= lt.start && now < lt.fajr
        let R: CGFloat = 68
        Root(entry: entry) {
            ZStack {
                // القوس: من المغرب (يمين) إلى الفجر (يسار) عبر الأعلى
                Circle().trim(from: 0.5, to: 1).stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: R * 2, height: R * 2)
                Circle().trim(from: 0.5, to: 1 - 2.0 / 3.0 * 0.5)
                    .stroke(TXT, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: R * 2, height: R * 2)
                if inNight {
                    let q = 1 - min(1, max(0, f)) * 0.5
                    let a = q * 2 * Double.pi
                    Circle().fill(Color.white).frame(width: 10, height: 10)
                        .shadow(color: .white.opacity(0.8), radius: 4)
                        .offset(x: R * CGFloat(cos(a)), y: R * CGFloat(sin(a)))
                }
                PrIcon(key: .maghrib, size: 12, color: TXT.opacity(0.63)).offset(x: R, y: 14)
                PrIcon(key: .fajr, size: 12, color: TXT.opacity(0.63)).offset(x: -R, y: 14)
                VStack(spacing: 1) {
                    Color.clear.frame(height: 30)
                    Fit("lbl_third_t", 112, 32)
                    Digits(text: hm12(lt.start), size: 18, color: .white, bold: true)
                    HStack(spacing: 4) {
                        Fit(inThird ? "lbl_now_t" : "lbl_left_t", 38, 19, 0.85)
                        CountDown(to: inThird ? lt.fajr : lt.start, size: 15, color: TXT, width: 76, at: entry.date)
                    }
                }
                .offset(y: 8)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}

// MARK: - رمضان: العد التنازلي، ثم أيام الشهر — صغير

struct RamadanView: View {
    let entry: HEntry
    var body: some View {
        let r = Cal.ramadan(entry.date)
        Root(entry: entry) {
            if r.inRamadan { during(r) } else { before(r) }
        }
    }

    func before(_ r: (inRamadan: Bool, day: Int, len: Int, daysLeft: Int)) -> some View {
        // يوم / يومان / ٣–١٠ أيام / ١١ يومًا فأكثر
        let n = r.daysLeft
        let word = n == 2 ? "lbl_days2_t" : ((3...10).contains(n) ? "lbl_days_t" : (n >= 11 ? "lbl_dayn_t" : "lbl_day_t"))
        return VStack(spacing: 4) {
            Image(systemName: "moon.stars.fill").font(.system(size: 22)).foregroundStyle(TXT)
            Digits(text: ar(r.daysLeft), size: 56, color: .white, bold: true, tight: true)
            HStack(spacing: 6) {
                Fit(word, 40, 24)
                Fit("lbl_ramadan_left_t", 92, 26)
            }
        }
    }

    func during(_ r: (inRamadan: Bool, day: Int, len: Int, daysLeft: Int)) -> some View {
        let t = Prayer.times(for: entry.date)
        let day = entry.date >= t[0] && entry.date < t[4]
        let p = Double(r.day) / Double(max(1, r.len))
        return VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 5)
                Circle().trim(from: 0, to: p).stroke(TXT, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .ringStart()
                VStack(spacing: -4) {
                    Fit("hm9_t", 64, 26)
                    Fit("bn\(max(1, min(31, r.day)))", 50, 40)
                }
            }
            .frame(width: 104, height: 104)
            HStack(spacing: 4) {
                Fit(day ? "lbl_iftar_t" : "lbl_imsak_t", 50, 22, 0.85)
                CountDown(to: day ? t[4] : Prayer.night(around: entry.date).fajr, size: 15, color: .white, width: 74, at: entry.date)
            }
        }
    }
}

// MARK: - التقويم الثلاثي: الميلادي | اليوم | الهجري — متوسط

struct TripleDateView: View {
    let entry: HEntry
    var body: some View {
        let h = Cal.dmy(entry.date, greg: false), g = Cal.dmy(entry.date, greg: true)
        Root(entry: entry) {
            HStack(spacing: 0) {
                column(d: h.d, month: "hm\(h.m)_t", year: yLine(h.y, greg: false) + "_t")
                Rectangle().fill(Color.white.opacity(0.22)).frame(width: 1, height: 100)
                VStack(spacing: 6) {
                    Fit("wd\(Cal.weekday(entry.date))_t", 108, 56)
                    Image(systemName: "moon.stars").font(.system(size: 13)).foregroundStyle(TXT.opacity(0.5))
                }
                .frame(width: 116)
                Rectangle().fill(Color.white.opacity(0.22)).frame(width: 1, height: 100)
                column(d: g.d, month: "gm\(g.m)_t", year: yLine(g.y, greg: true) + "_t")
            }
            .padding(.horizontal, 6)
        }
    }

    func column(d: Int, month: String, year: String) -> some View {
        VStack(spacing: 2) {
            Fit("bn\(max(1, min(31, d)))", 80, 62)
            Fit(month, 104, 30)
            Fit(year, 64, 16, 0.75)
        }
        .frame(width: 118)
    }
}

// MARK: - اليوم والتاريخان — صغير

struct DayTwoDatesView: View {
    let entry: HEntry
    var body: some View {
        let h = Cal.dmy(entry.date, greg: false), g = Cal.dmy(entry.date, greg: true)
        let hl = ["pn\(h.d)", "hm\(h.m)"], gl = ["pn\(g.d)", "gm\(g.m)"]
        Root(entry: entry) {
            VStack(spacing: 4) {
                Fit("wd\(Cal.weekday(entry.date))_t", 142, 56)
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 70, height: 1)
                // السطران بالحجم نفسه (مثل نسخة السنة): أكبر مقياس يتسع له أطولهما
                let ds = min(0.5, 140 / lineWidth(hl, GAP_PX, 1), 140 / lineWidth(gl, GAP_PX, 1))
                CLine(names: hl, s: ds)
                CLine(names: gl, s: ds)
            }
        }
    }
}

/// «اليوم والتاريخان مع السنة»: مثل «اليوم والتاريخان» مع السنة في آخر كل سطر
/// اسم اليوم أصغر قليلًا ليتسع السطران، والهجري أكبر من الميلادي (تسلسل واضح بلا ازدحام)
struct DayTwoDatesYearView: View {
    let entry: HEntry
    var body: some View {
        let h = Cal.dmy(entry.date, greg: false), g = Cal.dmy(entry.date, greg: true)
        let hl = ["pn\(h.d)", "hm\(h.m)"], hy = "hyl\(clampY(h.y, 1440, 1470))"
        let gl = ["pn\(g.d)", "gm\(g.m)"], gy = "gyl\(clampY(g.y, 2020, 2050))"
        Root(entry: entry) {
            VStack(spacing: 5) {
                Fit("wd\(Cal.weekday(entry.date))_t", 132, 46)
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 64, height: 1)
                    .padding(.vertical, 1)
                // السطران بالحجم نفسه: نأخذ أصغر مقياس يتسع به الاثنان
                let sc = min(YearLine.scale(hl, hy, 150, 0.42), YearLine.scale(gl, gy, 150, 0.42))
                YearLine(names: hl, year: hy, maxW: 150, maxS: 0.42, fixed: sc)
                YearLine(names: gl, year: gy, maxW: 150, maxS: 0.42, fixed: sc)
            }
            .padding(.horizontal, 8)
        }
    }
}

/// سطر تاريخ بخط الثلث والسنة في آخره مكبّرة (صورة السنة صغيرة أصلًا) — على خط الأساس نفسه
struct YearLine: View {
    let names: [String]
    let year: String
    let maxW: CGFloat
    let maxS: CGFloat
    /// مقياس محدد (لتوحيد حجم سطرين)
    var fixed: CGFloat? = nil
    /// تكبير السنة بالنسبة لباقي السطر
    var k: CGFloat = 1.7
    static func scale(_ names: [String], _ year: String, _ maxW: CGFloat, _ maxS: CGFloat, k: CGFloat = 1.7) -> CGFloat {
        let raw = lineWidth(names, GAP_PX, 1) + GAP_PX / PX + wOf(year, 1) * k
        return min(maxS, maxW / raw)
    }
    var body: some View {
        let gap = GAP_PX / PX
        let s = fixed ?? YearLine.scale(names, year, maxW, maxS, k: k)
        let lineH = hOf(year, s)
        HStack(alignment: .top, spacing: gap * s) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, n in CImg(name: n, s: s) }
            // نكبّر حول خط الأساس: نرفعها بمقدار ما زاد فوقه، ونُبقي ارتفاعها في الترتيب كباقي السطر
            CImg(name: year, s: s * k)
                .offset(y: -LINE_UP / PX * s * (k - 1))
                .frame(height: lineH, alignment: .top)
        }
    }
}

// MARK: - شبكة أيام الشهر (قابلة لإعادة الاستخدام)

struct MonthGrid: View {
    let date: Date
    let greg: Bool
    var cell: CGFloat = 26
    var font: CGFloat = 13
    var body: some View {
        let mi = Cal.monthInfo(date, greg: greg)
        let lead = Cal.weekday(mi.first)
        let rows = Int(ceil(Double(lead + mi.len) / 7))
        let rowH: CGFloat = rows > 5 ? 17 : 20
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                ForEach(0..<7, id: \.self) { i in
                    CImg(name: "wl\(i)", s: 0.23).frame(width: cell, height: 20)
                }
            }
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 1) {
                    ForEach(0..<7, id: \.self) { c in
                        let k = r * 7 + c - lead + 1
                        let outside = k < 1 || k > mi.len
                        let on = !outside && k == mi.day
                        let friday = c == 5
                        ZStack {
                            if on { Circle().fill(Color.white).frame(width: rowH + 2, height: rowH + 2) }
                            if !outside {
                                Digits(text: ar(k), size: font, color: on ? .white : (friday ? .white : TXT.opacity(0.84)), bold: on || friday)
                                    .blendMode(on ? .destinationOut : .normal)
                            }
                        }
                        .compositingGroup()
                        .frame(width: cell, height: rowH)
                    }
                }
            }
        }
    }
}

// MARK: - تقويم الشهر الكبير — متوسط

struct MonthCalendarMediumView: View {
    let entry: HEntry
    var body: some View {
        let greg = entry.greg
        let t = Cal.dmy(entry.date, greg: greg)
        Root(entry: entry) {
            HStack(spacing: 10) {
                VStack(spacing: 2) {
                    Fit("wd\(Cal.weekday(entry.date))_t", 108, 34, 0.9)
                    Fit("bn\(max(1, min(31, t.d)))", 84, 64)
                    Fit((greg ? "gm" : "hm") + "\(t.m)_t", 112, 30)
                    Fit(yLine(t.y, greg: greg) + "_t", 64, 15, 0.75)
                }
                .frame(width: 120)
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 120)
                MonthGrid(date: entry.date, greg: greg, cell: 28, font: 13)
                    .frame(width: 202)
            }
            .padding(10)
        }
    }
}

// MARK: - الأشهر الهجرية كاملة — متوسط

struct HijriMonthsView: View {
    let entry: HEntry
    var body: some View {
        let h = Cal.dmy(entry.date, greg: false)
        let mi = Cal.monthInfo(entry.date, greg: false)
        // مقياس واحد لكل الأشهر (أصغر مقياس يتسع له أطولها) بدل أن يكبر الاسم القصير ويصغر الطويل
        let ms = (1...12).map { fitS("hm\($0)_t", 84, 34) }.min() ?? 0.2
        Root(entry: entry) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Fit(yLine(h.y, greg: false) + "_t", 92, 22)
                    Spacer(minLength: 0)
                    Fit("pn\(h.d)", 40, 24)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2)).frame(width: 90, height: 4)
                        Capsule().fill(TXT).frame(width: max(4, 90 * Double(mi.day) / Double(mi.len)), height: 4)
                    }
                    .environment(\.layoutDirection, Lang.dir)
                }
                .frame(width: 336)
                ForEach(0..<3, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { c in
                            let m = r * 4 + c + 1
                            let on = m == h.m
                            CImg(name: "hm\(m)_t", s: ms, opacity: on ? 1 : (m < h.m ? 0.45 : 0.75))
                                .frame(width: 80, height: 36)
                                .background {
                                    if on { Capsule().fill(Color.white.opacity(0.16)) }
                                }
                        }
                    }
                }
            }
            .padding(10)
        }
    }
}

// MARK: - ساعة الدقائق: حلقة ٦٠ علامة تمتلئ مع الساعة — صغير

struct MinuteRingClockView: View {
    let entry: HEntry
    var body: some View {
        let m = Cal.gregCal.component(.minute, from: entry.date)
        let h = Cal.dmy(entry.date, greg: false)
        let hl = ["pn\(h.d)", "hm\(h.m)"]
        let size: CGFloat = 150
        Root(entry: entry) {
            ZStack {
                ForEach(0..<60, id: \.self) { i in
                    let major = i % 5 == 0
                    let done = i <= m
                    VStack(spacing: 0) {
                        Capsule().fill(done ? Color.white : TXT.opacity(0.21))
                            .frame(width: major ? 2.6 : 1.6, height: major ? 10 : 6)
                        Spacer(minLength: 0)
                    }
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(Double(i) * 6))
                }
                VStack(spacing: 0) {
                    Fit("wd\(Cal.weekday(entry.date))_t", 84, 26, 0.9)
                    Digits(text: hm12(entry.date), size: 34, color: .white, bold: true)
                        .environment(\.layoutDirection, .leftToRight)
                    CLine(names: hl, s: min(0.32, 84 / lineWidth(hl, GAP_PX, 1)))
                }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}

// MARK: - الساعة الرقمية الطويلة — صغير

struct TallClockView: View {
    let entry: HEntry
    var body: some View {
        let c = Cal.gregCal.dateComponents([.hour, .minute], from: entry.date)
        let hr = c.hour ?? 0
        let h12 = Settings.use24h ? hr : (hr % 12 == 0 ? 12 : hr % 12)
        // الساعة بدون صفر بادئ (الصفر العربي «٠» يبدو نقطة)، والدقائق برقمين
        let hh = Settings.use24h ? ar(h12).leftPad2 : ar(h12), mm = ar(c.minute ?? 0).leftPad2
        let hj = Cal.dmy(entry.date, greg: false)
        Root(entry: entry) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Fit("wd\(Cal.weekday(entry.date))_t", 70, 34)
                    Fit("bn\(max(1, min(31, hj.d)))", 44, 36)
                    Fit("hm\(hj.m)_t", 70, 24, 0.85)
                }
                .frame(width: 72)
                VStack(spacing: -16) {
                    Digits(text: hh, size: 72, color: .white, bold: true, tight: true)
                    Digits(text: mm, size: 72, color: TXT, bold: false, tight: true)
                }
                .scaleEffect(x: 0.8, y: 1)
                .frame(width: 84)
                .environment(\.layoutDirection, .leftToRight)
            }
        }
    }
}

// MARK: - ساعة عقارب مزخرفة بنجمة ثمانية — صغير

struct DecoDialView: View {
    let entry: HEntry
    var body: some View {
        let size: CGFloat = 150
        Root(entry: entry) {
            ZStack {
                Star8().fill(TXT.opacity(0.06)).frame(width: 128, height: 128)
                Star8().stroke(TXT.opacity(0.18), lineWidth: 0.8).frame(width: 128, height: 128)
                    .rotationEffect(.degrees(22.5))
                Circle().stroke(TXT.opacity(0.29), lineWidth: 1).frame(width: size, height: size)
                Circle().stroke(TXT.opacity(0.13), lineWidth: 0.6).frame(width: size - 10, height: size - 10)
                ForEach(0..<12, id: \.self) { i in
                    VStack(spacing: 0) {
                        if i % 3 == 0 {
                            Digits(text: ar(i == 0 ? 12 : i), size: 15, color: TXT, bold: true)
                                .rotationEffect(.degrees(Double(-i) * 30))
                                .frame(width: 24, height: 20)
                        } else {
                            Rectangle().fill(TXT.opacity(0.71)).frame(width: 5, height: 5)
                                .rotationEffect(.degrees(45))
                                .padding(.top, 5)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: size - 12, height: size - 12)
                    .rotationEffect(.degrees(Double(i) * 30))
                }
                ClockHands(size: size - 8, inApp: entry.inApp, date: entry.date)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}

// MARK: - اسم اليوم مع ساعة رقمية — متوسط

struct DayClockView: View {
    let entry: HEntry
    var body: some View {
        let h = Cal.dmy(entry.date, greg: false), g = Cal.dmy(entry.date, greg: true)
        let r1 = ["pn\(h.d)", "hm\(h.m)", yLine(h.y, greg: false)]
        let r2 = ["pn\(g.d)", "gm\(g.m)", yLine(g.y, greg: true)]
        let st = Prayer.state(at: entry.date)
        Root(entry: entry) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Fit("wd\(Cal.weekday(entry.date))_t", 176, 66)
                    CLine(names: r1, s: min(0.45, 180 / lineWidth(r1, GAP_PX, 1)))
                    CLine(names: r2, s: min(0.38, 170 / lineWidth(r2, GAP_PX, 1))).opacity(0.78)
                }
                .frame(width: 184, alignment: .leading)
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    Digits(text: hm12(entry.date), size: 50, color: .white, bold: true, tight: true)
                        .environment(\.layoutDirection, .leftToRight)
                    Rectangle().fill(Color.white.opacity(0.25)).frame(width: 110, height: 1)
                    HStack(spacing: 4) {
                        Fit("pr_\(st.next.key.rawValue)_t", 52, 20, 0.9)
                        CountDown(to: st.next.time, size: 15, color: TXT, width: 70, at: entry.date)
                    }
                }
                .frame(width: 140)
            }
            .padding(.horizontal, 14)
        }
    }
}

// MARK: - ورد القرآن (تفاعلي) — صغير

struct WirdView: View {
    let entry: HEntry
    var body: some View {
        let juz = Wird.juz, k = Wird.khatmas
        Root(entry: entry) {
            VStack(spacing: 5) {
                Fit("lbl_wird_t", 96, 28)
                ZStack {
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 5)
                    Circle().trim(from: 0, to: max(0.004, Wird.progress))
                        .stroke(TXT, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .ringStart()
                    VStack(spacing: -2) {
                        Fit("lbl_juz_t", 40, 20, 0.85)
                        Digits(text: ar(juz), size: 28, color: .white, bold: true, tight: true)
                    }
                }
                .frame(width: 80, height: 80)
                HStack(spacing: 10) {
                    Button(intent: WirdStepIntent(delta: 1)) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 30, height: 30).background(Circle().fill(Color.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 3) {
                        Fit("lbl_khatma_t", 38, 17, 0.8)
                        Digits(text: ar(k), size: 13, color: TXT, bold: true)
                    }
                    Button(intent: WirdStepIntent(delta: -1)) {
                        Image(systemName: "minus").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 30, height: 30).background(Circle().fill(Color.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - آية اليوم وأوقات الصلاة — متوسط

struct VerseText: View {
    let text: String
    let ref: String
    @Environment(\.wfont) private var wf
    var body: some View {
        VStack(spacing: 2) {
            Text("﴿" + text + "﴾")
                .font(.custom(wf == .thuluth ? "DecoTypeThuluthII" : wf.ps, size: wf == .thuluth ? 24 : 21))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.55)
            Text(prefDigits(ref))
                .font(.custom(wf == .thuluth ? "Amiri-Bold" : wf.ps, size: 11))
                .foregroundStyle(TXT.opacity(0.59))
        }
    }
}

struct VersePrayersView: View {
    let entry: HEntry
    var body: some View {
        let v = Verses.of(entry.date)
        let st = Prayer.state(at: entry.date)
        Root(entry: entry) {
            VStack(spacing: 4) {
                VerseText(text: v.0, ref: v.1)
                    .frame(width: 330, height: 66)
                PrayerRow(date: prayerListDay(entry.date), nextKey: st.next.key)
            }
            .padding(10)
        }
    }
}

// MARK: - توقعات الأيام — متوسط

struct WeatherWeekView: View {
    let entry: HEntry
    var body: some View {
        let w = entry.weather
        let days = Array((w?.days ?? []).prefix(6))
        Root(entry: entry) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    CityLabel(maxW: 150, maxH: 30)
                    Spacer(minLength: 0)
                    WxIcon(w: w, size: 30)
                    Digits(text: Weather.deg(w?.temp), size: 30, color: .white, bold: true)
                }
                .frame(width: 336)
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                        let date = Date(timeIntervalSince1970: d.t)
                        VStack(spacing: 4) {
                            Fit(i == 0 ? "lbl_today_t" : "wd\(Cal.weekday(date))_t", 50, 20, i == 0 ? 1 : 0.85)
                            if let u = Calli.ui(Weather.iconFor(code: d.code)) {
                                WxImage(img: u).frame(width: 26, height: 26)
                            }
                            Digits(text: Weather.deg(d.hi), size: 14, color: .white, bold: true)
                            Digits(text: Weather.deg(d.lo), size: 13, color: DIM)
                        }
                        .frame(width: 56)
                    }
                }
                if days.isEmpty {
                    Text(L("افتح التطبيق لتحديث الطقس")).font(.caption).foregroundStyle(TXT.opacity(0.59))
                }
            }
            .padding(12)
        }
    }
}

// MARK: - الطقس المفصّل — متوسط

struct WeatherFullView: View {
    let entry: HEntry
    var body: some View {
        let w = entry.weather
        Root(entry: entry) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    CityLabel(maxW: 160, maxH: 30)
                    HStack(spacing: 6) {
                        Digits(text: Weather.deg(w?.temp), size: 50, color: .white, bold: true, tight: true)
                        WxIcon(w: w, size: 38)
                    }
                    Fit(Weather.word(w), 110, 26)
                    HiLo(w: w, size: 14)
                }
                .frame(width: 160, alignment: .leading)
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 116)
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        stat("lbl_humidity_t", w?.humidity.map { ar($0) + PCT } ?? "--")
                        stat("lbl_wind_t", Weather.windText(w))
                    }
                    HStack(spacing: 6) {
                        stat("lbl_sunrise_t", w?.sunrise.map { hm12(Date(timeIntervalSince1970: $0)) } ?? "--")
                        stat("lbl_sunset_t", w?.sunset.map { hm12(Date(timeIntervalSince1970: $0)) } ?? "--")
                    }
                }
                .frame(width: 160)
            }
            .padding(.horizontal, 14)
        }
    }

    func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Fit(label, 66, 20, 0.8)
            Text(value).font(digitFont(15, bold: true)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(width: 76, height: 50)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}
