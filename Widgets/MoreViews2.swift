import SwiftUI
import WidgetKit

// ويدجت الدفعة الثانية — مستوحاة من «الويدجت العربي» بتصميم رفيقي

// MARK: - عناصر مشتركة

/// سطر التاريخين: «٣٠ أكتوبر ٢٠٢٦ | ١٩ جمادى الأولى ١٤٤٨»
struct DateStrip: View {
    let date: Date
    var width: CGFloat = 320
    var maxS: CGFloat = 0.3
    var body: some View {
        let h = Cal.dmy(date, greg: false), g = Cal.dmy(date, greg: true)
        let gl = ["dg\(g.d)", "gm\(g.m)", yLine(g.y, greg: true)]
        let hl = ["dg\(h.d)", "hm\(h.m)", yLine(h.y, greg: false)]
        let total = lineWidth(gl, GAP_PX, 1) + lineWidth(hl, GAP_PX, 1)
        let s = min(maxS, (width - 16) / max(1, total))
        HStack(spacing: 7) {
            CLine(names: gl, s: s)
            Rectangle().fill(TXT.opacity(0.42)).frame(width: 1, height: 14)
            CLine(names: hl, s: s)
        }
        .frame(height: 107 * s * 0.62)
    }
}

/// التاريخان في سطرين (الهجري ثم الميلادي أصغر قليلًا) — أوضح من سطر واحد صغير تحت الخط الكبير
struct DatesTwoLines: View {
    let date: Date
    var width: CGFloat = 300
    var maxS: CGFloat = 0.36
    var body: some View {
        let h = Cal.dmy(date, greg: false), g = Cal.dmy(date, greg: true)
        let hl = ["dg\(h.d)", "hm\(h.m)", yLine(h.y, greg: false)]
        let gl = ["dg\(g.d)", "gm\(g.m)", yLine(g.y, greg: true)]
        let s = min(maxS, width / max(1, lineWidth(hl, GAP_PX, 1)), width / max(1, lineWidth(gl, GAP_PX, 1)))
        VStack(spacing: 0) {
            CLine(names: hl, s: s).frame(height: 107 * s * 0.62)
            CLine(names: gl, s: s * 0.86).opacity(0.85).frame(height: 107 * s * 0.86 * 0.62)
        }
    }
}

/// صف الصلوات الست: الاسم فوق والوقت تحته، والقادمة داخل كبسولة
struct PrayerRowCapsule: View {
    let date: Date
    var width: CGFloat = 336
    var note = false
    var body: some View {
        let st = Prayer.state(at: date, sunrise: true)
        let list = Prayer.dayTimes(prayerListDay(date))
        HStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { _, p in
                let on = p.time == st.next.time
                VStack(spacing: 2) {
                    PrName(p.key, 50, 19, on ? 1 : 0.82)
                    Digits(text: hm12(p.time), size: 13.5, color: on ? .white : TXT.opacity(0.74), bold: on)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background {
                            if on {
                                Capsule().fill(Color.white.opacity(0.14))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1))
                            }
                        }
                    if note && on {
                        CountDown(to: p.time, size: 10, color: TXT.opacity(0.67), width: 56, at: date)
                    }
                }
                .frame(width: width / 6)
            }
        }
    }
}

/// «باقي على الظهر ٢:٢٦»
struct LeftToLine: View {
    let date: Date
    var body: some View {
        let st = Prayer.state(at: date, sunrise: true)
        HStack(spacing: 5) {
            Fit("lbl_leftto_t", 62, 19, 0.85)
            Fit("pr_\(st.next.key.rawValue)_t", 52, 19)
            CountDown(to: st.next.time, size: 14, color: .white, width: 66, at: date)
        }
    }
}

/// صفوف أيام الطقس: اليوم، الرمز، العظمى، الصغرى
struct WxRows: View {
    let days: [WDay]
    var width: CGFloat = 190
    /// مقياس واحد لأسماء الأيام في القائمة
    private var dayS: CGFloat { (0...6).map { fitS("wd\($0)_t", 58, 19) }.min() ?? 0.1 }
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                let date = Date(timeIntervalSince1970: d.t)
                HStack(spacing: 6) {
                    CImg(name: "wd\(Cal.weekday(date))_t", s: dayS, opacity: 0.9)
                        .frame(width: 62, alignment: .leading)
                    Spacer(minLength: 0)
                    if let u = Calli.ui(Weather.iconFor(code: d.code)) {
                        WxImage(img: u).frame(width: 20, height: 20)
                    }
                    Digits(text: Weather.deg(d.hi), size: 14, color: .white, bold: true).frame(width: 34)
                    Digits(text: Weather.deg(d.lo), size: 13, color: DIM).frame(width: 30)
                }
                .frame(width: width, height: 30)
                if i < days.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: width, height: 1)
                }
            }
        }
    }
}

/// علامات حول إطار مستطيل (مثل ساعة الإطار)، تمتلئ مع الدقائق
struct TickFrame: Shape {
    var from = 0
    var to = 60
    var majors: Bool? = nil   // nil = الكل، true = الكبيرة فقط، false = الصغيرة فقط
    var inset: CGFloat = 9
    var majorLen: CGFloat = 10
    var minorLen: CGFloat = 5
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let a = r.width / 2 - inset, b = r.height / 2 - inset
        guard from < to else { return p }
        for i in from..<to {
            let major = i % 5 == 0
            if let m = majors, m != major { continue }
            let th = Double(i) / 60 * 2 * Double.pi
            let dx = CGFloat(sin(th)), dy = CGFloat(-cos(th))
            let tx: CGFloat = abs(dx) > 0.0001 ? a / abs(dx) : 100000
            let ty: CGFloat = abs(dy) > 0.0001 ? b / abs(dy) : 100000
            let t = min(tx, ty)
            let len = major ? majorLen : minorLen
            p.move(to: CGPoint(x: c.x + dx * t, y: c.y + dy * t))
            p.addLine(to: CGPoint(x: c.x + dx * (t - len), y: c.y + dy * (t - len)))
        }
        return p
    }
}

struct TickFrameView: View {
    let minute: Int
    var body: some View {
        let m = max(0, min(59, minute))
        ZStack {
            TickFrame(from: m + 1, to: 60, majors: false).stroke(TXT.opacity(0.24), lineWidth: 1.3)
            TickFrame(from: m + 1, to: 60, majors: true).stroke(TXT.opacity(0.29), lineWidth: 2.4)
            TickFrame(from: 0, to: m + 1, majors: false).stroke(Color.white, lineWidth: 1.3)
            TickFrame(from: 0, to: m + 1, majors: true).stroke(Color.white, lineWidth: 2.4)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - اليوم والصلاة — متوسط

struct DayPrayersMView: View {
    let entry: HEntry
    var clock = false
    var body: some View {
        Root(entry: entry) {
            VStack(spacing: 3) {
                DateStrip(date: entry.date)
                ZStack {
                    if clock {
                        // الساعة خلفية باهتة كبيرة (لا تُقرأ مع حروف اسم اليوم كأنها جزء منه)
                        Digits(text: hm12(entry.date), size: 80, color: .white, bold: true, tight: true)
                            .mask(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    Fit("wd\(Cal.weekday(entry.date))_t", 240, 60)
                }
                .frame(height: 58)
                PrayerRowCapsule(date: entry.date)
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 320, height: 1)
                LeftToLine(date: entry.date)
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: - اليوم والصلوات بالنقاط — متوسط

struct DayDotsView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.state(at: entry.date, sunrise: true)
        let list = Prayer.dayTimes(prayerListDay(entry.date))
        Root(entry: entry) {
            VStack(spacing: 4) {
                DateStrip(date: entry.date)
                ZStack {
                    Digits(text: hm12(entry.date), size: 72, color: .white, bold: true, tight: true)
                        .mask(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                        .environment(\.layoutDirection, .leftToRight)
                    Fit("wd\(Cal.weekday(entry.date))_t", 220, 56)
                }
                .frame(height: 54)
                VStack(spacing: 3) {
                    ForEach(0..<2, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { c in
                                let p = list[r * 3 + c]
                                let on = p.time == st.next.time
                                HStack(spacing: 4) {
                                    Circle().fill(on ? Color.white : Color.clear)
                                        .overlay(Circle().stroke(TXT.opacity(0.59), lineWidth: 1))
                                        .frame(width: 6, height: 6)
                                    PrName(p.key, 44, 17, on ? 1 : 0.8)
                                    Digits(text: hm12(p.time), size: 13, color: on ? .white : TXT.opacity(0.71), bold: on)
                                }
                                .frame(width: 110)
                            }
                        }
                    }
                }
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 320, height: 1)
                LeftToLine(date: entry.date)
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - اليوم والطقس — متوسط

struct DayWeatherView: View {
    let entry: HEntry
    var body: some View {
        let w = entry.weather
        let days = Array((w?.days ?? []).dropFirst().prefix(5))
        // مقياس واحد لأسماء الأيام ولكلمات الطقس في الصف (لا يكبر «الأحد» ويصغر «الثلاثاء»)
        let dayS = (0...6).map { fitS("wd\($0)_t", 52, 16) }.min() ?? 0.1
        let wxS = days.map { fitS("wx_\(Weather.key($0.code))_t", 58, 14) }.min() ?? 0.1
        Root(entry: entry) {
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    WxIcon(w: w, size: 18)
                    Fit(Weather.word(w), 90, 18)
                    Digits(text: Weather.deg(w?.temp), size: 14, color: .white, bold: true)
                }
                Fit("wd\(Cal.weekday(entry.date))_t", 200, 46)
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                        VStack(spacing: 2) {
                            CImg(name: "wd\(Cal.weekday(Date(timeIntervalSince1970: d.t)))_t", s: dayS, opacity: 0.85)
                            if let u = Calli.ui(Weather.iconFor(code: d.code)) {
                                WxImage(img: u).frame(width: 18, height: 18)
                            }
                            CImg(name: "wx_\(Weather.key(d.code))_t", s: wxS, opacity: 0.75)
                        }
                        .frame(width: 66)
                    }
                }
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 320, height: 1)
                LeftToLine(date: entry.date)
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - طقس الأيام (صفوف) — متوسط

struct WeatherDaysView: View {
    let entry: HEntry
    var dayName = false
    var body: some View {
        let w = entry.weather
        let days = Array((w?.days ?? []).dropFirst().prefix(4))
        Root(entry: entry) {
            HStack(spacing: 10) {
                VStack(spacing: 4) {
                    if dayName {
                        HStack { Spacer(minLength: 0); Digits(text: Weather.deg(w?.temp), size: 13, color: TXT) }
                        Fit("wd\(Cal.weekday(entry.date))_t", 124, 66)
                    } else {
                        WxIcon(w: w, size: 52)
                        Digits(text: Weather.deg(w?.temp), size: 40, color: .white, bold: true, tight: true)
                    }
                    Spacer(minLength: 0)
                    CityLabel(maxW: 120, maxH: 22)
                }
                .frame(width: 128)
                .padding(.vertical, 12)
                WxRows(days: days, width: 196)
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - اسم الشهر والتاريخ بالأرقام — صغير

struct MonthDateView: View {
    let entry: HEntry
    var body: some View {
        let t = Cal.dmy(entry.date, greg: entry.greg)
        let num = ar(t.y) + "/" + ar(t.m) + "/" + ar(t.d)
        Root(entry: entry) {
            VStack(spacing: 8) {
                Fit((entry.greg ? "gm" : "hm") + "\(t.m)_t", 146, 60)
                Digits(text: num, size: 15, color: TXT.opacity(0.71))
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
    }
}

// MARK: - الشهر ورقم اليوم الكبير — متوسط

struct MonthGhostMView: View {
    let entry: HEntry
    var body: some View {
        let t = Cal.dmy(entry.date, greg: entry.greg)
        Root(entry: entry) {
            VStack(spacing: 2) {
                ZStack {
                    Fit("wm\(max(1, min(31, t.d)))", 200, 100)
                    Fit((entry.greg ? "gm" : "hm") + "\(t.m)_t", 300, 76)
                }
                .frame(height: 100)
                DatesTwoLines(date: entry.date, maxS: 0.32)
            }
        }
    }
}

// MARK: - اسم اليوم الكبير والتاريخ — متوسط

struct DayNameMView: View {
    let entry: HEntry
    var body: some View {
        Root(entry: entry) {
            VStack(spacing: 0) {
                Fit("wd\(Cal.weekday(entry.date))_t", 300, 86)
                DatesTwoLines(date: entry.date)
            }
        }
    }
}

// MARK: - التقويم المزدوج: «أكتوبر ٣٠ | ١٩ جمادى الأولى» — متوسط

struct DualDateView: View {
    let entry: HEntry
    var body: some View {
        let h = Cal.dmy(entry.date, greg: false), g = Cal.dmy(entry.date, greg: true)
        Root(entry: entry) {
            HStack(spacing: 10) {
                Fit("gm\(g.m)_t", 104, 46)
                Fit("bn\(max(1, min(31, g.d)))", 52, 50)
                Rectangle().fill(TXT.opacity(0.34)).frame(width: 1, height: 56)
                Fit("bn\(max(1, min(31, h.d)))", 52, 50)
                Fit("hm\(h.m)_t", 110, 46)
            }
        }
    }
}

// MARK: - التقويم الثلاثي والصلاة — متوسط

struct TriplePrayerView: View {
    let entry: HEntry
    var body: some View {
        let h = Cal.dmy(entry.date, greg: false), g = Cal.dmy(entry.date, greg: true)
        Root(entry: entry) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Fit("hm\(h.m)_t", 104, 44)
                    Rectangle().fill(TXT.opacity(0.34)).frame(width: 1, height: 44)
                    Fit("wd\(Cal.weekday(entry.date))_t", 104, 50)
                    Rectangle().fill(TXT.opacity(0.34)).frame(width: 1, height: 44)
                    Fit("gm\(g.m)_t", 96, 44)
                }
                PrayerRowCapsule(date: entry.date, note: true)
            }
            .padding(.vertical, 10)
        }
    }
}

// MARK: - كبسولات الصلاة بالأيقونات — متوسط

struct PrayerIconCapsView: View {
    let entry: HEntry
    var body: some View {
        let st = Prayer.state(at: entry.date, sunrise: true)
        let list = Prayer.dayTimes(prayerListDay(entry.date))
        Root(entry: entry) {
            VStack(spacing: 8) {
                HStack(spacing: 7) {
                    ForEach(Array(list.enumerated()), id: \.offset) { _, p in
                        let on = p.time == st.next.time
                        VStack(spacing: 6) {
                            PrIcon(key: p.key, size: 15, color: .white)
                            Spacer(minLength: 0)
                            VStack(spacing: 1) {
                                PrName(p.key, 40, 16)
                                Digits(text: hm12(p.time), size: 11.5, color: .white, bold: on)
                            }
                            .colorMultiply(on ? Color(white: 0.12) : .white)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(on ? Color.white : Color.white.opacity(0.08)))
                        }
                        .padding(.vertical, 8)
                        .frame(width: 50, height: 108)
                        .background(Capsule().fill(Color.white.opacity(on ? 0.16 : 0.07)))
                        .overlay(Capsule().stroke(Color.white.opacity(on ? 0.45 : 0.14), lineWidth: 1))
                    }
                }
                LeftToLine(date: entry.date)
            }
        }
    }
}

// MARK: - ساعة الإطار — صغير

struct TickBoxView: View {
    let entry: HEntry
    var body: some View {
        let m = Cal.gregCal.component(.minute, from: entry.date)
        let g = Cal.dmy(entry.date, greg: true)
        let w = entry.weather ?? Weather.cached()
        Root(entry: entry) {
            ZStack {
                TickFrameView(minute: m)
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Fit("wd\(Cal.weekday(entry.date))_t", 52, 18, 0.9)
                        Digits(text: ar(g.d) + "/" + ar(g.m), size: 12, color: TXT)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    Digits(text: hm12(entry.date), size: 36, color: .white, bold: true)
                        .environment(\.layoutDirection, .leftToRight)
                    HStack(spacing: 4) {
                        WxIcon(w: w, size: 16)
                        Digits(text: Weather.deg(w?.temp), size: 13, color: TXT)
                    }
                }
            }
        }
    }
}

// MARK: - ساعة الإطار مع الطقس — متوسط

struct TickClockMView: View {
    let entry: HEntry
    var body: some View {
        let c = Cal.gregCal.dateComponents([.hour, .minute], from: entry.date)
        let hr = c.hour ?? 0
        let h12 = Settings.use24h ? hr : (hr % 12 == 0 ? 12 : hr % 12)
        let w = entry.weather ?? Weather.cached()
        let g = Cal.dmy(entry.date, greg: true)
        Root(entry: entry) {
            ZStack {
                TickFrameView(minute: c.minute ?? 0)
                HStack(spacing: 0) {
                    Digits(text: Settings.use24h ? ar(h12).leftPad2 : ar(h12), size: 74, color: .white, bold: true, tight: true)
                        .frame(width: 120)
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Fit("wd\(Cal.weekday(entry.date))_t", 56, 20, 0.9)
                            Fit("pn\(g.d)", 28, 20, 0.9)
                            Fit("gm\(g.m)_t", 56, 20, 0.9)
                        }
                        .environment(\.layoutDirection, Lang.dir)
                        // ساعة عقارب صغيرة في الوسط
                        ClockHands(size: 44, inApp: entry.inApp, date: entry.date)
                            .frame(width: 44, height: 44)
                        HStack(spacing: 4) {
                            WxIcon(w: w, size: 16)
                            Fit(Weather.word(w), 56, 16, 0.85)
                            Digits(text: Weather.deg(w?.temp), size: 12, color: TXT)
                        }
                        .environment(\.layoutDirection, Lang.dir)
                    }
                    .frame(width: 124)
                    Digits(text: ar(c.minute ?? 0).leftPad2, size: 74, color: .white, bold: true, tight: true)
                        .frame(width: 120)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
        }
    }
}

// MARK: - الساعة الممدّدة: الوقت بخط طويل ضيّق — صغير

struct TallLineClockView: View {
    let entry: HEntry
    var body: some View {
        let g = Cal.dmy(entry.date, greg: true)
        let gl = ["pn\(g.d)", "gm\(g.m)"]
        Root(entry: entry) {
            VStack(spacing: 2) {
                Digits(text: hm12(entry.date), size: 92, color: .white, bold: true, tight: true)
                    .scaleEffect(x: 0.5, y: 1.25)
                    .frame(width: 150, height: 104)
                    .environment(\.layoutDirection, .leftToRight)
                HStack(spacing: 4) {
                    Fit("wd\(Cal.weekday(entry.date))_t", 56, 20, 0.9)
                    CLine(names: gl, s: min(0.24, 84 / lineWidth(gl, GAP_PX, 1)))
                }
                .frame(height: 22)
            }
        }
    }
}

// MARK: - ساعة الزخرفة الدائرية: اسم اليوم يدور حول المركز — صغير

struct RosetteClockView: View {
    let entry: HEntry
    var body: some View {
        let size: CGFloat = 150
        let wd = "wd\(Cal.weekday(entry.date))_t"
        Root(entry: entry) {
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    VStack(spacing: 0) {
                        Fit(wd, 58, 30, 0.26)
                        Spacer(minLength: 0)
                    }
                    .frame(width: 112, height: 112)
                    .rotationEffect(.degrees(Double(i) * 45))
                }
                ForEach(0..<12, id: \.self) { i in
                    VStack(spacing: 0) {
                        Capsule().fill(TXT.opacity(i % 3 == 0 ? 0.9 : 0.45))
                            .frame(width: i % 3 == 0 ? 2.6 : 1.4, height: i % 3 == 0 ? 11 : 6)
                        Spacer(minLength: 0)
                    }
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(Double(i) * 30))
                }
                ClockHands(size: size - 16, inApp: entry.inApp, date: entry.date)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}


// MARK: - التقويم الثلاثي بالأسماء: «أكتوبر | الجمعة | جمادى الأولى» — متوسط

struct TripleNamesView: View {
    let entry: HEntry
    var body: some View {
        let h = Cal.dmy(entry.date, greg: false), g = Cal.dmy(entry.date, greg: true)
        Root(entry: entry) {
            HStack(spacing: 10) {
                // الهجري يمينًا والميلادي يسارًا — مثل «التقويم الثلاثي»
                Fit("hm\(h.m)_t", 112, 52)
                Rectangle().fill(TXT.opacity(0.34)).frame(width: 1, height: 52)
                Fit("wd\(Cal.weekday(entry.date))_t", 112, 60)
                Rectangle().fill(TXT.opacity(0.34)).frame(width: 1, height: 52)
                Fit("gm\(g.m)_t", 104, 52)
            }
        }
    }
}

// MARK: - ساعة الإطار: الساعة كبيرة والدقائق باهتة تحتها — صغير

struct TickStackView: View {
    let entry: HEntry
    var body: some View {
        let c = Cal.gregCal.dateComponents([.hour, .minute], from: entry.date)
        let hr = c.hour ?? 0
        let h12 = Settings.use24h ? hr : (hr % 12 == 0 ? 12 : hr % 12)
        let ampm = Lang.isEN ? (hr < 12 ? "AM" : "PM") : (hr < 12 ? "ص" : "م")
        Root(entry: entry) {
            ZStack {
                TickFrameView(minute: c.minute ?? 0)
                HStack(spacing: 6) {
                    if !Settings.use24h {
                        Text(ampm).font(.system(size: 11, weight: .semibold)).foregroundStyle(TXT)
                    }
                    VStack(spacing: -4) {
                        Digits(text: Settings.use24h ? ar(h12).leftPad2 : ar(h12), size: 58, color: .white, bold: true, tight: true)
                        Digits(text: ar(c.minute ?? 0).leftPad2, size: 58, color: .white, bold: true, tight: true)
                            .mask(LinearGradient(colors: [.white, .white.opacity(0.15)], startPoint: .top, endPoint: .bottom))
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
        }
    }
}
