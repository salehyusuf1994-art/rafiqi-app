import SwiftUI
import WidgetKit

func clampY(_ y: Int, _ a: Int, _ b: Int) -> Int { min(b, max(a, y)) }

// MARK: - التاريخ المعتمد: "(اليوم) الشهر" وتحته السنة — متوسط

struct DateLineView: View {
    let entry: HEntry
    var body: some View {
        let greg = entry.greg
        let t = Cal.dmy(entry.date, greg: greg)
        let names = ["pn\(t.d)", (greg ? "gm" : "hm") + "\(t.m)"]
        let yname = greg ? "gy\(clampY(t.y, 2020, 2050))" : "hy\(clampY(t.y, 1440, 1470))"
        let w = lineWidth(names, GAP_PX, 1)
        let s: CGFloat = w > 337 ? 337 / w : 1
        let ys: CGFloat = 104 / 165
        let MB: CGFloat = 312, YB: CGFloat = 458
        let top = (MB - LINE_UP * s) / PX
        let between = ((YB - MB) - LINE_DN * s - YEAR_UP * ys) / PX
        Root(entry: entry) {
            VStack(spacing: 0) {
                Color.clear.frame(height: max(0, top))
                VStack(spacing: between) {
                    CLine(names: names, s: s)
                    CImg(name: yname, s: ys)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - الهجري والميلادي معاً — متوسط

struct BothDatesView: View {
    let entry: HEntry
    var body: some View {
        let h = Cal.dmy(entry.date, greg: false), g = Cal.dmy(entry.date, greg: true)
        let r1 = ["pn\(h.d)", "hm\(h.m)", "hyl\(clampY(h.y, 1440, 1470))"]
        let r2 = ["pn\(g.d)", "gm\(g.m)", "gyl\(clampY(g.y, 2020, 2050))"]
        // أكبر حجم يتسع له أطول سطر (جمادى) — والسطرين بنفس الحجم
        let w1 = max(lineWidth(r1, GAP_PX, 1), lineWidth(r2, GAP_PX, 1))
        let s: CGFloat = min(0.82, 344 / w1)
        let B1: CGFloat = 63, B2: CGFloat = 137
        let top = B1 - LINE_UP * s / PX
        let between = (B2 - B1) - (LINE_DN + LINE_UP) * s / PX
        return Root(entry: entry) {
            VStack(spacing: 0) {
                Color.clear.frame(height: max(0, top))
                VStack(spacing: between) {
                    CLine(names: r1, s: s)
                    CLine(names: r2, s: s)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - اسم اليوم — صغير

struct DayNameView: View {
    let entry: HEntry
    var body: some View {
        Root(entry: entry) {
            CArt(name: "d\(Cal.weekday(entry.date))")
        }
    }
}

// MARK: - اليوم + رقم كبير + الشهر — صغير

struct DayNumberView: View {
    let entry: HEntry
    var body: some View {
        let t = Cal.dmy(entry.date, greg: entry.greg)
        let mName = (entry.greg ? "gm" : "hm") + "\(t.m)_t"
        Root(entry: entry) {
            VStack(spacing: 0) {
                Fit("wd\(Cal.weekday(entry.date))_t", 124, 40)
                Fit("bn\(t.d)", 130, 70)
                Fit(mName, 142, 42)
            }
        }
    }
}

// MARK: - اسم الشهر ورقم اليوم كبير باهت خلفه — صغير

struct MonthGhostView: View {
    let entry: HEntry
    var body: some View {
        let t = Cal.dmy(entry.date, greg: entry.greg)
        Root(entry: entry) {
            ZStack {
                Fit("wm\(t.d)", 150, 150)
                Fit((entry.greg ? "gm" : "hm") + "\(t.m)_t", 138, 62)
            }
        }
    }
}

// MARK: - تقويم الشهر — صغير

struct MonthCalendarView: View {
    let entry: HEntry
    var body: some View {
        let greg = entry.greg
        let mi = Cal.monthInfo(entry.date, greg: greg)
        let t = Cal.dmy(entry.date, greg: greg)
        let lead = Cal.weekday(mi.first)
        let rows = Int(ceil(Double(lead + mi.len) / 7))
        let cell: CGFloat = 20, rowH: CGFloat = rows > 5 ? 15 : 17
        let mT = (greg ? "gm" : "hm") + "\(t.m)_t"
        let yT = (greg ? "gyl\(clampY(t.y, 2020, 2050))" : "hyl\(clampY(t.y, 1440, 1470))") + "_t"
        Root(entry: entry) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 6) {
                    Fit(mT, 98, 22)
                    Fit(yT, 58, 15, 0.85)
                    Spacer(minLength: 0)
                }
                .frame(width: 146, height: 28)
                HStack(spacing: 1) {
                    ForEach(0..<7, id: \.self) { i in
                        CImg(name: "wl\(i)", s: 0.22).frame(width: cell, height: 18)
                    }
                }
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 1) {
                        ForEach(0..<7, id: \.self) { c in
                            let k = r * 7 + c - lead + 1
                            let outside = k < 1 || k > mi.len
                            let label = k < 1 ? mi.prevLen + k : (k > mi.len ? k - mi.len : k)
                            let on = !outside && k == mi.day
                            ZStack {
                                if on { Circle().fill(Color.white).frame(width: rowH + 1, height: rowH + 1) }
                                Digits(text: ar(label), size: 12.5, color: on ? Color(white: 0.11) : (outside ? Color.white.opacity(0.44) : TXT), bold: on)
                            }
                            .frame(width: cell, height: rowH)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(9)
        }
    }
}

// MARK: - تقدّم الشهر / السنة بالنقاط — صغير

struct DotField: View {
    let count: Int
    let today: Int
    let columns: Int
    let dot: CGFloat
    let spacing: CGFloat
    var body: some View {
        let rows = Int(ceil(Double(count) / Double(columns)))
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: spacing) {
                    ForEach(0..<min(columns, count - r * columns), id: \.self) { c in
                        let i = r * columns + c + 1
                        Circle()
                            .fill(i == today ? Color.white : (i < today ? TXT : Color.white))
                            .opacity(i == today ? 1 : (i < today ? 0.95 : 0.22))
                            .frame(width: dot, height: dot)
                    }
                }
            }
        }
    }
}

struct ProgressHeader: View {
    let name: String
    let pct: Int
    var body: some View {
        HStack(spacing: 0) {
            Fit(name, 112, 28)
            Spacer(minLength: 0)
            Digits(text: ar(pct) + PCT, size: 20, color: .white, bold: true)
        }
        .frame(width: 148, height: 34)
    }
}

struct MonthProgressView: View {
    let entry: HEntry
    var body: some View {
        let mi = Cal.monthInfo(entry.date, greg: entry.greg)
        let t = Cal.dmy(entry.date, greg: entry.greg)
        let pct = Int((100 * Double(mi.day) / Double(mi.len)).rounded())
        Root(entry: entry) {
            VStack(spacing: 10) {
                ProgressHeader(name: (entry.greg ? "gm" : "hm") + "\(t.m)_t", pct: pct)
                DotField(count: mi.len, today: mi.day, columns: 7, dot: 9, spacing: 10.5)
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }
}

struct YearProgressView: View {
    let entry: HEntry
    var body: some View {
        let yi = Cal.yearInfo(entry.date, greg: entry.greg)
        let t = Cal.dmy(entry.date, greg: entry.greg)
        let pct = Int((100 * Double(yi.day) / Double(yi.len)).rounded())
        let yName = (entry.greg ? "gyl\(clampY(t.y, 2020, 2050))" : "hyl\(clampY(t.y, 1440, 1470))") + "_t"
        Root(entry: entry) {
            VStack(spacing: 8) {
                ProgressHeader(name: yName, pct: pct)
                DotField(count: yi.len, today: yi.day, columns: 21, dot: 3.9, spacing: 2.95)
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }
}
