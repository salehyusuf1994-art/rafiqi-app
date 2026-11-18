import SwiftUI
import WidgetKit

// MARK: - عقارب الساعة المتحركة
// مقتبس من ClockHandKit (رخصة MIT) — https://github.com/giljihun/ClockHandKit
// يستخدم تأثير WidgetKit الداخلي اللي يحرّك العقارب بدون تحديث الويدجت.

enum HandPeriod { case hour, minute, second }

private struct ClockHandData: Encodable {
    let period: [String: EmptyPayload]
    let timeZone: TZ
    let anchor: Anchor
    struct EmptyPayload: Encodable {}
    struct TZ: Encodable { let identifier: String }
    struct Anchor: Encodable { let x: Double; let y: Double }
}

private func applyModifier<V: View, M: ViewModifier>(_ view: V, _ m: M) -> some View { view.modifier(m) }

extension View {
    func clockHand(_ period: HandPeriod) -> AnyView {
        guard let type = _typeByName("9WidgetKit24_ClockHandRotationEffectV"),
              let decodable = type as? any Decodable.Type else { return AnyView(self) }
        let key: String
        switch period {
        case .hour: key = "hourHand"
        case .minute: key = "minuteHand"
        case .second: key = "secondHand"
        }
        let payload = ClockHandData(period: [key: .init()], timeZone: .init(identifier: TimeZone.current.identifier),
                                    anchor: .init(x: 0.5, y: 0.5))
        guard let data = try? JSONEncoder().encode(payload),
              let decoded = try? JSONDecoder().decode(decodable, from: data),
              let modifier = decoded as? any ViewModifier else { return AnyView(self) }
        return AnyView(applyModifier(self, modifier))
    }
}


struct ClockFace: View {
    let size: CGFloat
    let numerals: Bool
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.28), lineWidth: 1.2).frame(width: size, height: size)
            ForEach(0..<60, id: \.self) { i in
                let major = i % 5 == 0
                if !(numerals && major) {
                    VStack(spacing: 0) {
                        Capsule().fill(TXT.opacity(major ? 0.9 : 0.4)).frame(width: major ? 2.4 : 1, height: major ? 9 : 4)
                        Spacer(minLength: 0)
                    }
                    .frame(width: size - 6, height: size - 6)
                    .rotationEffect(.degrees(Double(i) * 6))
                }
            }
            if numerals {
                ForEach(1...12, id: \.self) { k in
                    VStack(spacing: 0) {
                        Digits(text: ar(k), size: 15, color: TXT, bold: true)
                            .rotationEffect(.degrees(Double(-k) * 30))
                            .frame(width: 22, height: 20)
                        Spacer(minLength: 0)
                    }
                    .frame(width: size - 8, height: size - 8)
                    .rotationEffect(.degrees(Double(k) * 30))
                }
            }
        }
    }
}

struct ClockHands: View {
    let size: CGFloat
    var inApp = false
    /// وقت مدخل الويدجت (يتجدّد كل دقيقة)
    var date: Date = Date()
    var body: some View {
        if inApp {
            // داخل التطبيق: نحسب الزاوية كل ثانية
            TimelineView(.periodic(from: .now, by: 1)) { t in hands(t.date) }
        } else {
            // في الويدجت: الطريقة الخفية لتدوير العقارب لم تعد تعمل في iOS 26 (كانت العقارب تقف على ١٢)
            // فنرسم العقربين بزاويتهما من وقت المدخل، والويدجت يتجدّد كل دقيقة؛ وعقرب الثواني لا يمكن تحريكه في الويدجت
            hands(date, seconds: false)
        }
    }

    var pin: some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 9, height: 9)
            Circle().fill(Color(red: 0.9, green: 0.33, blue: 0.29)).frame(width: 3.5, height: 3.5)
        }
    }

    func hands(_ d: Date, seconds: Bool = true) -> some View {
        let c = Cal.gregCal.dateComponents([.hour, .minute, .second], from: d)
        let s = Double(c.second ?? 0), m = Double(c.minute ?? 0) + s / 60, h = Double((c.hour ?? 0) % 12) + m / 60
        let r = size / 2
        // عقرب مثل الساعات الفاخرة: ساق رفيعة من المركز، ثم كبسولة بيضاء بخط غائر في وسطها، وظل خفيف
        func hand(_ deg: Double, _ w: CGFloat, _ len: CGFloat) -> some View {
            VStack(spacing: 0) {
                ZStack {
                    Capsule().fill(Color.white)
                    Capsule().fill(Color.black.opacity(0.32))
                        .frame(width: max(1, w * 0.3)).padding(.vertical, w * 0.55)
                }
                .frame(width: w, height: len * 0.76)
                .shadow(color: Color.black.opacity(0.4), radius: 1.2, y: 0.6)
                Capsule().fill(Color.white).frame(width: max(1.6, w * 0.36), height: len * 0.24)
                Color.clear.frame(width: w, height: len)
            }
            .rotationEffect(.degrees(deg))
        }
        func needle(_ deg: Double, _ len: CGFloat) -> some View {
            VStack(spacing: 0) {
                Capsule().fill(Color(red: 0.9, green: 0.33, blue: 0.29)).frame(width: 1.2, height: len * 1.2)
                Color.clear.frame(width: 1.2, height: len * 0.8)
            }
            .rotationEffect(.degrees(deg))
        }
        return ZStack {
            hand(h * 30, max(4.5, r * 0.075), r * 0.52)
            hand(m * 6, max(3.4, r * 0.055), r * 0.78)
            if seconds { needle(s * 6, r * 0.42 + r * 0.42) }
            pin
        }
        .frame(width: size, height: size)
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - ساعة بعقارب — صغير (اسم اليوم خلفها) / بالأرقام

struct AnalogClockView: View {
    let entry: HEntry
    let numerals: Bool
    var body: some View {
        let size: CGFloat = 150
        let h = Cal.dmy(entry.date, greg: false)
        let hl = ["pn\(h.d)", "hm\(h.m)"]
        Root(entry: entry) {
            ZStack {
                if numerals {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        CLine(names: hl, s: min(0.5, 76 / lineWidth(hl, GAP_PX, 1)))
                        Color.clear.frame(height: 22)
                    }
                    .frame(width: size, height: size)
                } else {
                    Fit("wd\(Cal.weekday(entry.date))_t", 122, 104, 0.2)
                }
                ClockFace(size: size, numerals: numerals)
                ClockHands(size: size, inApp: entry.inApp, date: entry.date)
            }
            // وجه الساعة لا يُعكس مع اتجاه العربية (٣ يمين و٩ يسار دائمًا)
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}

// MARK: - ساعة بعقارب + اليوم والتاريخين — متوسط

struct ClockDatesView: View {
    let entry: HEntry
    var body: some View {
        let size: CGFloat = 140
        let h = Cal.dmy(entry.date, greg: false), g = Cal.dmy(entry.date, greg: true)
        let r1 = ["pn\(h.d)", "hm\(h.m)"], r2 = ["pn\(g.d)", "gm\(g.m)"]
        let s = min(0.75, 180 / lineWidth(r1, GAP_PX, 1), 180 / lineWidth(r2, GAP_PX, 1))
        Root(entry: entry) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Fit("wd\(Cal.weekday(entry.date))_t", 150, 42)
                    VStack(alignment: .leading, spacing: -(LINE_DN + LINE_UP) * s / PX * 0.42) {
                        CLine(names: r1, s: s)
                        CLine(names: r2, s: s * 0.82)
                    }
                }
                Spacer(minLength: 0)
                ZStack { ClockFace(size: size, numerals: false); ClockHands(size: size, inApp: entry.inApp, date: entry.date) }
                    .frame(width: size, height: size)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(16)
        }
    }
}

// MARK: - ساعة رقمية حيّة (تتحدث كل دقيقة) — صغير

struct DigitalClockView: View {
    let entry: HEntry
    var body: some View {
        let h = Cal.dmy(entry.date, greg: false)
        let hl = ["pn\(h.d)", "hm\(h.m)"]
        Root(entry: entry) {
            VStack(spacing: 2) {
                Fit("wd\(Cal.weekday(entry.date))_t", 124, 40)
                // الأرقام بلا فراغ السطر الزائد: كان اسم اليوم يلامس الحافة العلوية
                Digits(text: hm12(entry.date), size: 46, color: .white, bold: true, tight: true)
                    .padding(.vertical, 4)
                    .environment(\.layoutDirection, .leftToRight)
                CLine(names: hl, s: min(0.55, 140 / lineWidth(hl, GAP_PX, 1)))
            }
        }
    }
}
