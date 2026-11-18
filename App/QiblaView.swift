import SwiftUI
import CoreLocation
import CoreMotion

// MARK: - القبلة: بوصلة الجوال واتجاه الكعبة المشرفة من موقعك

enum Qibla {
    static let kaaba = CLLocationCoordinate2D(latitude: 21.422487, longitude: 39.826206)

    /// اتجاه القبلة بالدرجات من الشمال الحقيقي (٠…٣٦٠)
    static func bearing(lat: Double, lng: Double) -> Double {
        let r = Double.pi / 180
        let p1 = lat * r, p2 = kaaba.latitude * r, dl = (kaaba.longitude - lng) * r
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let b = atan2(y, x) / r
        return (b + 360).truncatingRemainder(dividingBy: 360)
    }

    /// المسافة إلى مكة المكرمة بالكيلومتر
    static func distance(lat: Double, lng: Double) -> Double {
        CLLocation(latitude: lat, longitude: lng)
            .distance(from: CLLocation(latitude: kaaba.latitude, longitude: kaaba.longitude)) / 1000
    }

    /// اسم الجهة لزاوية (ش، ش ق، ق …)
    static func direction(_ deg: Double) -> String {
        let names = ["شمال", "شمال شرق", "شرق", "جنوب شرق", "جنوب", "جنوب غرب", "غرب", "شمال غرب"]
        let i = Int(((deg.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45).rounded(.down)) % 8
        return L(names[i])
    }
}

/// البوصلة: اتجاه الجوال (الشمال الحقيقي)، مُنعَّم بلا ارتجاف، ودقّته
final class Compass: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// الاتجاه المُنعَّم (٠…٣٦٠)
    @Published var heading: Double = 0
    @Published var accuracy: Double = -1
    @Published var hasHeading = false
    /// هل الاتجاه حقيقي (يحتاج الموقع)، وإلا مغناطيسي
    @Published var isTrue = false
    /// الموقع الحالي (لحساب القبلة من مكانك الفعلي إن تحرّكت)
    @Published var coord: CLLocationCoordinate2D?
    let available = CLLocationManager.headingAvailable()
    private let m = CLLocationManager()
    private var sx = 0.0, sy = 0.0, primed = false

    override init() {
        super.init()
        m.delegate = self
        m.headingFilter = kCLHeadingFilterNone
        m.headingOrientation = .portrait
    }

    func start() {
        guard available else { return }
        m.startUpdatingHeading()
        // الشمال الحقيقي لا يُحسب إلا مع تشغيل الموقع؛ بدونه نأخذ المغناطيسي (فرقه في المدينة ٣–٤ درجات)
        let st = m.authorizationStatus
        if st == .authorizedWhenInUse || st == .authorizedAlways {
            m.desiredAccuracy = kCLLocationAccuracyKilometer
            m.startUpdatingLocation()
        }
    }

    func stop() { m.stopUpdatingHeading(); m.stopUpdatingLocation() }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let c = locations.last?.coordinate { coord = c }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        let raw = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        isTrue = h.trueHeading >= 0
        // تنعيم دائري (جيب وجيب تمام) حتى لا يرتجف المؤشر، ولا يقفز بين ٣٥٩ و٠
        let r = raw * .pi / 180
        if !primed { sx = cos(r); sy = sin(r); primed = true }
        let a = 0.22
        sx += a * (cos(r) - sx); sy += a * (sin(r) - sy)
        heading = (atan2(sy, sx) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        accuracy = h.headingAccuracy
        hasHeading = true
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}

/// ميزان الاستواء: ميل الجوال (البوصلة تحتاج الجوال مستويًا)
final class Level: ObservableObject {
    /// ميل الجوال على المحورين (−١…١)
    @Published var x: Double = 0
    @Published var y: Double = 0
    /// زاوية الميل عن الأفق بالدرجات
    @Published var tilt: Double = 0
    private let mm = CMMotionManager()

    func start() {
        guard mm.isDeviceMotionAvailable else { return }
        mm.deviceMotionUpdateInterval = 1 / 30
        mm.startDeviceMotionUpdates(to: .main) { [weak self] d, _ in
            guard let self, let g = d?.gravity else { return }
            self.x += 0.3 * (g.x - self.x)
            self.y += 0.3 * (g.y - self.y)
            self.tilt = acos(min(1, abs(g.z))) * 180 / .pi
        }
    }

    func stop() { mm.stopDeviceMotionUpdates() }
}

struct QiblaView: View {
    @StateObject private var compass = Compass()
    @StateObject private var level = Level()
    /// زاوية القرص بلا قفزات (من ٣٥٩ إلى ٠)
    @State private var dial: Double = 0
    @State private var lastRaw: Double = 0
    @State private var aligned = false
    @State private var near = false

    private var lat: Double { compass.coord?.latitude ?? Settings.lat }
    private var lng: Double { compass.coord?.longitude ?? Settings.lng }
    private var qibla: Double { Qibla.bearing(lat: lat, lng: lng) }
    private var km: Double { Qibla.distance(lat: lat, lng: lng) }
    /// الفرق بين اتجاه الجوال والقبلة (−١٨٠…١٨٠)
    private var diff: Double { (qibla - compass.heading + 540).truncatingRemainder(dividingBy: 360) - 180 }
    private var flat: Bool { level.tilt < 30 }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                BackRow()
                PageHeader(title: "القبلة",
                           subtitle: Settings.placeName.isEmpty ? L("موقعك الحالي") : Settings.placeName)

                status
                compassFace
                    .padding(.vertical, 4)

                HStack(spacing: 10) {
                    info("location.north.line.fill", "اتجاه القبلة", "\(ar(Int(qibla.rounded())))°")
                    info("safari.fill", "اتجاه الجوال", compass.hasHeading ? "\(ar(Int(compass.heading.rounded())))°" : "—")
                    info("map.fill", "المسافة إلى مكة", LF("%@ كم", ar(Int(km.rounded()))))
                }

                tips
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .barSpace()
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { compass.start(); level.start() }
        .onDisappear { compass.stop(); level.stop() }
        .onChange(of: compass.heading) { _, h in
            let d = (h - lastRaw + 540).truncatingRemainder(dividingBy: 360) - 180
            lastRaw = h
            dial += d
            // دخول الاتجاه الصحيح عند أقل من ٣° وخروجه بعد ٥° (بلا تذبذب على الحد)
            let a = abs(diff)
            let nowAligned = aligned ? a < 5 : a < 3
            if nowAligned && !aligned { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            aligned = nowAligned
            let nowNear = a < 15
            if nowNear && !near && !nowAligned { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            near = nowNear
        }
    }

    // ── الحالة فوق البوصلة: أدِر يمينًا/يسارًا أو أنت باتجاه القبلة ──
    private var status: some View {
        let d = Int(abs(diff).rounded())
        let text: String = !compass.available ? L("البوصلة غير متوفرة")
            : !compass.hasHeading ? L("جارٍ تحديد الاتجاه…")
            : aligned ? L("أنت باتجاه القبلة")
            : (diff > 0 ? LF("أدِر يمينًا %@°", ar(d)) : LF("أدِر يسارًا %@°", ar(d)))
        let color: Color = aligned ? Color(red: 0.30, green: 0.85, blue: 0.55) : .white
        return HStack(spacing: 8) {
            Image(systemName: aligned ? "checkmark.circle.fill" : (diff > 0 ? "arrow.turn.up.right" : "arrow.turn.up.left"))
                .font(.system(size: 17, weight: .bold))
                .opacity(compass.hasHeading ? 1 : 0)
            Text(verbatim: text).font(Theme.title(20))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Capsule().fill(aligned ? Color.green.opacity(0.16) : Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(aligned ? Color.green.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 1))
        .animation(.easeInOut(duration: 0.25), value: aligned)
    }

    // ── البوصلة ──
    private var compassFace: some View {
        GeometryReader { g in
            let size = min(g.size.width, 360)
            ZStack {
                // التوهّج حين يتجه الجوال للقبلة
                Circle()
                    .fill(RadialGradient(colors: [Color.green.opacity(aligned ? 0.35 : 0), .clear],
                                         center: .center, startRadius: size * 0.3, endRadius: size * 0.62))
                    .frame(width: size * 1.2, height: size * 1.2)
                    .animation(.easeInOut(duration: 0.3), value: aligned)
                CompassBezel(size: size)
                CompassDial(size: size * 0.86, qibla: qibla, aligned: aligned)
                    .rotationEffect(.degrees(-dial))
                    .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: dial)
                // خط اتجاه الجوال (ثابت في الأعلى)
                VStack(spacing: 0) {
                    Capsule().fill(aligned ? Color(red: 0.30, green: 0.90, blue: 0.55) : .white)
                        .frame(width: 4, height: size * 0.11)
                        .shadow(color: (aligned ? Color.green : .white).opacity(0.7), radius: 6)
                    Spacer(minLength: 0)
                }
                .frame(width: size, height: size)
                CompassCenter(size: size * 0.30, heading: compass.heading, hasHeading: compass.hasHeading,
                              levelX: level.x, levelY: level.y, flat: flat)
            }
            .frame(width: g.size.width, height: g.size.height)
            .environment(\.layoutDirection, .leftToRight)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 380)
    }

    // ── تنبيهات حسب الحالة ──
    @ViewBuilder private var tips: some View {
        if !compass.available {
            note("iphone.slash", "البوصلة غير متوفرة في هذا الجوال. اتجاه القبلة من الشمال مكتوب أعلاه.")
        } else if !flat {
            note("level.fill", "ضع الجوال مستويًا على راحة يدك (الفقاعة في المنتصف) لتكون القراءة دقيقة.")
        } else if compass.hasHeading && (compass.accuracy < 0 || compass.accuracy > 15) {
            note("arrow.triangle.2.circlepath", "دقة البوصلة منخفضة: حرّك الجوال في الهواء على شكل الرقم ٨ عدة مرات، وابتعد عن المعادن والسيارات والمغناطيس.")
        } else {
            note("hand.point.up.left.fill", "أدِر جسمك حتى يصبح الخط الأبيض فوق الكعبة. يهتز الجوال ويضيء الأخضر عند الاتجاه الصحيح.")
        }
        if compass.hasHeading {
            HStack(spacing: 8) {
                Image(systemName: compass.isTrue ? "location.fill" : "location.slash")
                Text(verbatim: compass.isTrue ? L("الشمال الحقيقي (بموقعك)") : L("الشمال المغناطيسي — فعّل الموقع لدقة أعلى"))
                Spacer(minLength: 0)
                if compass.accuracy >= 0 {
                    Text(verbatim: "±\(ar(Int(compass.accuracy.rounded())))°").environment(\.layoutDirection, .leftToRight)
                }
            }
            .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            .padding(.horizontal, 6)
        }
    }

    func info(_ icon: String, _ title: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.gold)
            Text(L(title)).font(Theme.f(.caption2)).foregroundStyle(Theme.sub).lineLimit(1).minimumScaleFactor(0.8)
            Text(verbatim: value).font(Theme.title(17)).foregroundStyle(.white)
                .environment(\.layoutDirection, .leftToRight)
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 12, radius: 20)
    }

    func note(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.gold)
            Text(L(text)).font(Theme.f(.footnote)).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .glassCard(padding: 14, radius: 20)
    }
}

// MARK: - رسومات البوصلة

/// الإطار المعدني الخارجي (ثابت)
struct CompassBezel: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [Color(white: 0.55), Color(white: 0.22), Color(white: 0.62), Color(white: 0.18),
                                               Color(white: 0.50), Color(white: 0.20), Color(white: 0.55)],
                                      center: .center))
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                              lineWidth: 1.2)
            Circle()
                .fill(Color.black)
                .padding(size * 0.055)
                .shadow(color: .black.opacity(0.8), radius: 6)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
    }
}

/// وجه البوصلة الدوّار: العلامات كل درجة، والأرقام، والجهات، ونجمة إسلامية، وقوس القبلة والكعبة
struct CompassDial: View {
    let size: CGFloat
    let qibla: Double
    let aligned: Bool
    var body: some View {
        ZStack {
            face
            qiblaArc
            DialTicks()
            numerals
            cardinals
            kaabaPointer
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var face: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.13, green: 0.14, blue: 0.17), Color(red: 0.04, green: 0.045, blue: 0.06)],
                                     center: .center, startRadius: 0, endRadius: size * 0.55))
            // نجمة ثمانية خافتة
            EightStar().stroke(Theme.gold.opacity(0.10), lineWidth: 1).frame(width: size * 0.62, height: size * 0.62)
            EightStar().stroke(Theme.gold.opacity(0.06), lineWidth: 1).frame(width: size * 0.62, height: size * 0.62)
                .rotationEffect(.degrees(22.5))
        }
    }

    /// قوس القبلة (±٥°) على الحافة
    private var qiblaArc: some View {
        let w: CGFloat = size * 0.035
        let start: Double = qibla - 95
        return Circle()
            .trim(from: 0, to: 10.0 / 360)
            .stroke(Theme.gold.opacity(aligned ? 1 : 0.75), style: StrokeStyle(lineWidth: w, lineCap: .round))
            .rotationEffect(.degrees(start))
            .padding(size * 0.018)
    }

    /// الأرقام كل ٣٠ (غير الجهات)
    private var numerals: some View {
        ForEach([1, 2, 4, 5, 7, 8, 10, 11], id: \.self) { (i: Int) in
            DialLabel(text: ar(i * 30), angle: Double(i) * 30, size: size, top: size * 0.19,
                      font: .system(size: size * 0.042, weight: .semibold).monospacedDigit(),
                      color: .white.opacity(0.75))
                .opacity(nearQibla(Double(i) * 30) ? 0 : 1)
        }
    }

    /// الجهات
    private var cardinals: some View {
        ForEach(0..<4, id: \.self) { (i: Int) in
            DialLabel(text: L(["ش", "ق", "ج", "غ"][i]), angle: Double(i) * 90, size: size, top: size * 0.16,
                      font: Theme.title(size * 0.075),
                      color: i == 0 ? Color(red: 1, green: 0.40, blue: 0.36) : .white)
                .opacity(nearQibla(Double(i) * 90) ? 0 : 1)
        }
    }

    /// الكعبة تحل محل الحرف أو الرقم القريب من اتجاهها (لا يتداخلان)
    private func nearQibla(_ a: Double) -> Bool {
        abs((a - qibla + 540).truncatingRemainder(dividingBy: 360) - 180) < 13
    }

    /// خط القبلة والكعبة على اتجاهها
    private var kaabaPointer: some View {
        let k: CGFloat = size * 0.12
        return VStack(spacing: 0) {
            KaabaIcon()
                .frame(width: k, height: k)
                .shadow(color: Theme.gold.opacity(aligned ? 0.95 : 0.5), radius: aligned ? 14 : 6)
                .rotationEffect(.degrees(-qibla))
            Rectangle()
                .fill(LinearGradient(colors: [Theme.gold, Theme.gold.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: 2.5, height: size * 0.17)
            Spacer()
        }
        .padding(.top, size * 0.075)
        .frame(width: size, height: size)
        .rotationEffect(.degrees(qibla))
    }
}

/// نص على محيط القرص، يبقى قائمًا بالنسبة للقرص
struct DialLabel: View {
    let text: String
    let angle: Double
    let size: CGFloat
    let top: CGFloat
    let font: Font
    let color: Color
    var body: some View {
        VStack {
            Text(verbatim: text).font(font).foregroundStyle(color)
                .rotationEffect(.degrees(-angle))
            Spacer()
        }
        .padding(.top, top)
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
    }
}

/// العلامات كل درجة
struct DialTicks: View {
    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let r: CGFloat = sz.width / 2
            let outer: CGFloat = r - r * 0.06
            for i in 0..<360 {
                let major = i % 30 == 0, mid = i % 10 == 0, five = i % 5 == 0
                let len: CGFloat = major ? r * 0.10 : (mid ? r * 0.075 : (five ? r * 0.05 : r * 0.03))
                let w: CGFloat = major ? 2.2 : (mid ? 1.4 : 0.9)
                let a: CGFloat = CGFloat(i) * .pi / 180
                let sa: CGFloat = sin(a), ca: CGFloat = cos(a)
                let p1 = CGPoint(x: c.x + sa * outer, y: c.y - ca * outer)
                let p2 = CGPoint(x: c.x + sa * (outer - len), y: c.y - ca * (outer - len))
                var p = Path()
                p.move(to: p1)
                p.addLine(to: p2)
                let op: Double = major ? 0.95 : (mid ? 0.7 : 0.4)
                let col: Color = i == 0 ? Color(red: 1, green: 0.36, blue: 0.32) : Color.white.opacity(op)
                ctx.stroke(p, with: .color(col), lineWidth: w)
            }
        }
    }
}

/// المركز الزجاجي: الاتجاه بالدرجات واسم الجهة، وفقاعة الاستواء
struct CompassCenter: View {
    let size: CGFloat
    let heading: Double
    let hasHeading: Bool
    let levelX: Double
    let levelY: Double
    let flat: Bool
    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            Circle().fill(Color.black.opacity(0.35))
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                                  lineWidth: 1)
            // علامة المنتصف وفقاعة الاستواء
            Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1).frame(width: size * 0.26, height: size * 0.26)
            Circle()
                .fill(flat ? Color(red: 0.30, green: 0.85, blue: 0.55).opacity(0.85) : Color.orange.opacity(0.85))
                .frame(width: size * 0.13, height: size * 0.13)
                .offset(x: CGFloat(max(-1, min(1, levelX))) * size * 0.32,
                        y: CGFloat(max(-1, min(1, -levelY))) * size * 0.32)
                .animation(.easeOut(duration: 0.1), value: levelX)
            VStack(spacing: 0) {
                Text(verbatim: hasHeading ? "\(ar(Int(heading.rounded()) % 360))°" : "—")
                    .font(digitFont(size * 0.24, bold: true)).foregroundStyle(.white)
                Text(verbatim: hasHeading ? Qibla.direction(heading) : "")
                    .font(Theme.title(size * 0.10)).foregroundStyle(Theme.sub)
            }
            .offset(y: -size * 0.02)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.5), radius: 10)
    }
}

/// نجمة ثمانية (مربعان متداخلان)
struct EightStar: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), R = min(r.width, r.height) / 2
        for k in 0..<2 {
            let off = CGFloat(k) * .pi / 4
            for i in 0..<4 {
                let a: CGFloat = off + CGFloat(i) * .pi / 2
                let pt = CGPoint(x: c.x + cos(a) * R, y: c.y + sin(a) * R)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
        return p
    }
}

/// الكعبة المشرفة: مكعّب أسود بحزام ذهبي وباب
struct KaabaIcon: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: w * 0.10, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.03)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: w * 0.10, style: .continuous)
                    .strokeBorder(Theme.gold.opacity(0.85), lineWidth: max(1, w * 0.03))
                // الحزام المذهّب
                Rectangle().fill(LinearGradient(colors: [Theme.gold, Theme.goldDeep], startPoint: .top, endPoint: .bottom))
                    .frame(height: w * 0.11).padding(.top, w * 0.22)
                // الباب
                RoundedRectangle(cornerRadius: w * 0.03)
                    .fill(LinearGradient(colors: [Theme.gold, Theme.goldDeep], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.20, height: w * 0.30)
                    .offset(x: w * 0.16, y: w * 0.52)
            }
        }
    }
}

