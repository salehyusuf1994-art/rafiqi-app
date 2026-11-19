import SwiftUI
import WidgetKit

let PR_ICON: [PKey: String] = [.fajr: "sparkles", .sunrise: "sunrise", .dhuhr: "sun.max", .jumuah: "sun.max",
                               .asr: "sun.min", .maghrib: "sunset", .isha: "moon.stars", .midnight: "moon.zzz"]

struct PrIcon: View {
    let key: PKey
    let size: CGFloat
    var color: Color = TXT
    var body: some View {
        Image(systemName: PR_ICON[key] ?? "sun.max").font(.system(size: size)).foregroundStyle(color)
    }
}

// MARK: - الحلقة: الوقت + اسم الصلاة + عدّاد — صغير

struct PrayerRingView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.state(at: entry.date)
        let p = max(0.005, st.progress)
        Root(entry: entry) {
            ZStack {
                CArt(name: "p_\(st.next.key.rawValue)")
                Circle().stroke(Color.white.opacity(0.32), lineWidth: 4).frame(width: 146, height: 146)
                Circle().trim(from: 0, to: p).stroke(TXT, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .ringStart().frame(width: 146, height: 146)
                VStack(spacing: 0) {
                    Color.clear.frame(height: 33)
                    Digits(text: hm12(st.next.time), size: 19, color: .white, bold: true).frame(width: 140)
                    Color.clear.frame(height: 64)
                    CountDown(to: st.next.time, size: 17, color: TXT, width: 146, at: entry.date)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - جدول الصلوات الست + شريط اليوم

struct PrayerRow: View {
    let date: Date
    let nextKey: PKey
    var dots = false
    var body: some View {
        let times = Prayer.dayTimes(date)
        HStack(spacing: 1) {
            ForEach(Array(times.enumerated()), id: \.offset) { _, p in
                let on = p.key == nextKey
                VStack(spacing: dots ? -2 : -6) {
                    if dots { Circle().fill(on ? TXT : Color.white.opacity(0.55)).frame(width: on ? 9 : 5, height: on ? 9 : 5) }
                    CImg(name: "pr_\(p.key.rawValue)", s: 0.31, opacity: on ? 1 : 0.72)
                    Digits(text: hm12(p.time), size: 14, color: on ? .white : Color.white.opacity(0.72), bold: on)
                }
                .frame(width: 56, height: dots ? 66 : 58)
            }
        }
    }
}

struct DayBar: View {
    let date: Date
    var width: CGFloat = 344
    var body: some View {
        let t = Prayer.dayTimes(date)
        let f = min(1, max(0, date.timeIntervalSince(t[0].time) / t[5].time.timeIntervalSince(t[0].time)))
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.2)).frame(width: width, height: 4)
            Capsule().fill(TXT).frame(width: max(4, f * width), height: 4)
        }
    }
}

// MARK: - الصلاة القادمة كبيرة + الجدول — متوسط

struct NextPrayerView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.state(at: entry.date)
        Root(entry: entry) {
            VStack(spacing: 3) {
                HStack(spacing: 0) {
                    CImg(name: "pr_\(st.next.key.rawValue)", s: 1.0)
                    Spacer(minLength: 0)
                    // بعض الخطوط (النسخ والكوفي) أطول سطرًا: نصغّر حتى يتسع في الارتفاع
                    ViewThatFits(in: .vertical) {
                        side(st.next, 1)
                        side(st.next, 0.86)
                        side(st.next, 0.74)
                    }
                }
                .frame(width: 352, height: 90)
                PrayerRow(date: entry.date, nextKey: st.next.key)
                DayBar(date: entry.date)
            }
            .padding(10)
        }
    }

    private func side(_ next: PTime, _ k: CGFloat) -> some View {
        VStack(spacing: -4) {
            Digits(text: hm12(next.time), size: 30 * k, color: .white, bold: true)
            CImg(name: "lbl_next", s: 0.36 * k)
            CountDown(to: next.time, size: 26 * k, color: .white, width: 140, at: entry.date)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - التاريخ + الصلاة القادمة + الجدول بالنقاط — متوسط

struct AgendaView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.state(at: entry.date)
        let h = Cal.dmy(entry.date, greg: false), g = Cal.dmy(entry.date, greg: true)
        let hl = ["wd\(Cal.weekday(entry.date))", "pn\(h.d)", "hm\(h.m)", "hyl\(clampY(h.y, 1440, 1470))"]
        let gl = ["pn\(g.d)", "gm\(g.m)", "gyl\(clampY(g.y, 2020, 2050))"]
        let s1 = min(0.42, 240 / lineWidth(hl, GAP_PX, 1))
        let s2 = min(0.36, 240 / lineWidth(gl, GAP_PX, 1))
        Root(entry: entry) {
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: -12) {
                        CLine(names: hl, s: s1)
                        CLine(names: gl, s: s2)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: -4) {
                        CImg(name: "pr_\(st.next.key.rawValue)", s: 0.42)
                        CountDown(to: st.next.time, size: 20, color: .white, width: 110, at: entry.date)
                    }
                }
                .frame(width: 350, height: 80)
                Spacer(minLength: 0)
                PrayerRow(date: entry.date, nextKey: st.next.key, dots: true)
                DayBar(date: entry.date)
            }
            .padding(12)
        }
    }
}

// MARK: - الهجري يمين والميلادي يسار + العدّاد + الجدول — متوسط

struct ComboView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.state(at: entry.date)
        let h = Cal.dmy(entry.date, greg: false), g = Cal.dmy(entry.date, greg: true)
        let hn = ["pn\(h.d)", "hm\(h.m)"], gn = ["pn\(g.d)", "gm\(g.m)"]
        // كان المحتوى أطول من الويدجت فيلتصق شريط اليوم بالحافة السفلى ويُقصّ: رأس أقصر قليلًا
        let s = min(0.36, 165 / lineWidth(hn, GAP_PX, 1), 165 / lineWidth(gn, GAP_PX, 1))
        Root(entry: entry) {
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    VStack(spacing: -6) { CLine(names: hn, s: s); CImg(name: "hy\(clampY(h.y, 1440, 1470))", s: s * 0.75) }
                    Spacer(minLength: 0)
                    VStack(spacing: -6) { CLine(names: gn, s: s); CImg(name: "gy\(clampY(g.y, 2020, 2050))", s: s * 0.75) }
                }
                .frame(width: 350, height: 62)
                HStack(spacing: 8) {
                    Rectangle().fill(Color.white.opacity(0.25)).frame(width: 92, height: 1)
                    CountDown(to: st.next.time, size: 20, color: .white, width: 120, at: entry.date)
                    Rectangle().fill(Color.white.opacity(0.25)).frame(width: 92, height: 1)
                }
                PrayerRow(date: entry.date, nextKey: st.next.key)
                DayBar(date: entry.date)
            }
            .padding(12)
        }
    }
}

// MARK: - الصلاة السابقة والقادمة (مع الشروق) — صغير ومتوسط

struct PrevNextView: View {
    let entry: HEntry
    @Environment(\.widgetFamily) var envFamily
    var body: some View {
        let st = Prayer.prevNext(at: entry.date)
        let family = entry.family ?? envFamily
        Root(entry: entry) {
            if family == .systemMedium { medium(st) } else { small(st) }
        }
    }

    func small(_ st: (prev: PTime, next: PTime, progress: Double)) -> some View {
        func nameRow(_ q: PTime) -> some View {
            HStack(spacing: 6) {
                PrIcon(key: q.key, size: 17, color: .white)
                Fit("pr_\(q.key.rawValue)_t", q.key == .midnight ? 88 : 82, 40)
                Digits(text: hm12(q.time), size: 18, color: .white)
            }
        }
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            nameRow(st.prev)
            HStack(spacing: 5) { Fit("lbl_ago_t", 54, 27); CountUp(from: st.prev.time, size: 20, color: .white, width: 86, at: entry.date) }
            Color.clear.frame(height: 6)
            Rectangle().fill(Color.white.opacity(0.28)).frame(width: 96, height: 1)
            Color.clear.frame(height: 6)
            nameRow(st.next)
            HStack(spacing: 5) { Fit("lbl_left_t", 54, 27); CountDown(to: st.next.time, size: 20, color: .white, width: 86, at: entry.date) }
            Spacer(minLength: 0)
        }
    }

    func medium(_ st: (prev: PTime, next: PTime, progress: Double)) -> some View {
        func block(_ q: PTime, _ lbl: String, prev: Bool) -> some View {
            VStack(spacing: 2) {
                Fit(lbl, 130, 20, 0.8)
                Fit("pr_\(q.key.rawValue)_t", 150, 54, prev ? 0.9 : 1)
                HStack(spacing: 5) { PrIcon(key: q.key, size: 15, color: TXT); Digits(text: hm12(q.time), size: 17, color: TXT) }
                if prev { CountUp(from: q.time, size: 26, color: .white, width: 160, at: entry.date) }
                else { CountDown(to: q.time, size: 26, color: .white, width: 160, at: entry.date) }
            }
            .frame(width: 165, height: 132)
        }
        let lp = "lbl_prev_t"
        let ln = st.next.key.isPrayer ? "lbl_next2_t" : "lbl_next_m_t"
        return VStack(spacing: 6) {
            HStack(spacing: 0) {
                block(st.prev, lp, prev: true)
                Rectangle().fill(Color.white.opacity(0.22)).frame(width: 1, height: 96)
                block(st.next, ln, prev: false)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 344, height: 4)
                Capsule().fill(TXT).frame(width: max(4, st.progress * 344), height: 4)
            }
        }
        .padding(14)
    }
}
