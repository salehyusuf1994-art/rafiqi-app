import SwiftUI

// MARK: - الهوية البصرية للتطبيق

enum Theme {
    static let bg = Color(red: 0.031, green: 0.035, blue: 0.055)
    static let card = Color.white.opacity(0.06)
    static let cardHi = Color.white.opacity(0.10)
    static let stroke = Color.white.opacity(0.10)
    static let gold = Color(red: 0.89, green: 0.76, blue: 0.50)
    static let goldDeep = Color(red: 0.62, green: 0.50, blue: 0.29)
    static let sub = Color.white.opacity(0.56)
    static let teal = Color(red: 0.20, green: 0.62, blue: 0.70)
    static let violet = Color(red: 0.45, green: 0.34, blue: 0.80)
    static let radius: CGFloat = 26

    /// خط العناوين (تجوّل العريض) — لا يقل عن ١٢ نقطة
    static func title(_ size: CGFloat) -> Font { font(size, .bold) }

    /// خط التطبيق الموحّد: تجوّل بأوزانه الثلاثة (عادي/متوسط/عريض)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let size = max(12, size)
        if Lang.isEN { return .system(size: size, weight: weight == .regular ? .regular : weight, design: .rounded) }
        return .custom(tajawal(weight), size: size, relativeTo: style)
    }

    static func tajawal(_ w: Font.Weight) -> String {
        switch w {
        case .bold, .semibold, .heavy, .black: return "Tajawal-Bold"
        case .medium: return "Tajawal-Medium"
        default: return "Tajawal-Regular"
        }
    }

    /// سلّم الأحجام الموحّد (بديل أنماط النظام): لا شيء أصغر من ١٢ نقطة
    static func f(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        let spec: (CGFloat, Font.Weight)
        switch style {
        case .largeTitle: spec = (32, .bold)
        case .title: spec = (26, .bold)
        case .title2: spec = (22, .bold)
        case .title3: spec = (19, .medium)
        case .headline: spec = (17, .bold)
        case .callout: spec = (16, .regular)
        case .subheadline: spec = (15, .regular)
        case .footnote: spec = (14, .regular)
        case .caption: spec = (13, .regular)
        case .caption2: spec = (12, .regular)
        default: spec = (17, .regular)
        }
        return font(spec.0, weight ?? spec.1, relativeTo: style)
    }
    /// حدّ زجاجي متدرّج (أفتح من الأعلى)
    static var edge: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.05), Color.white.opacity(0.10)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// خلفية التطبيق: ليل عميق بتوهّجات ملوّنة تتحرّك ببطء
struct AppBackground: View {
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Theme.bg
                glow(Theme.gold, 0.30, size: w * 1.0)
                    .offset(x: w * (drift ? 0.42 : 0.30), y: -h * (drift ? 0.46 : 0.38))
                glow(Theme.teal, 0.26, size: w * 0.95)
                    .offset(x: -w * (drift ? 0.40 : 0.30), y: -h * (drift ? 0.02 : 0.10))
                glow(Theme.violet, 0.24, size: w * 1.1)
                    .offset(x: w * (drift ? 0.20 : 0.34), y: h * (drift ? 0.46 : 0.38))
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .onAppear {
            // حركة الخلفية خفيفة؛ وتتوقف مع «تقليل الحركة» أو «نمط الطاقة المنخفضة» حفاظًا على البطارية
            guard SHOT_STATIC == false, !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    private func glow(_ c: Color, _ o: Double, size: CGFloat) -> some View {
        Circle().fill(c.opacity(o)).frame(width: size, height: size).blur(radius: size * 0.28)
    }
}

/// في وضع التصوير تبقى الخلفية ثابتة
var SHOT_STATIC: Bool { !(UserDefaults.standard.string(forKey: "shot") ?? "").isEmpty }

extension View {
    /// بطاقة زجاجية بحواف ناعمة
    func glassCard(padding: CGFloat = 16, radius: CGFloat = Theme.radius) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.card)
                }
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }

    /// مسافة أسفل الصفحة لشريط التبويب العائم
    func barSpace() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 78) }
    }

    /// قائمة بمظهر زجاجي
    func glassList() -> some View {
        self.scrollContentBackground(.hidden)
            .background(AppBackground())
            .environment(\.colorScheme, .dark)
    }
}

/// عنوان الصفحة: العنوان الكبير وتاريخ اليوم، والأزرار الدائرية على الطرف الآخر
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L(title)).font(Theme.title(30)).foregroundStyle(.white)
                // بدون تصغير تلقائي: كان يقيس السطر أضيق من رسمه فيُقص أوله (رقم اليوم / «القرآن»)
                Text(subtitle ?? DateLine.today()).font(Theme.title(14)).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) { trailing() }
        }
        .padding(.top, 6)
        // هامش صغير: خط تجوّل يرسم أول الحرف خارج حدوده قليلًا فيُقص عند حافة الصف («ال» في «القرآن»)
        .padding(.horizontal, 6)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

/// سطر التاريخين: «٣١ أكتوبر | ٢٠ جمادى الأولى ١٤٤٨»
enum DateLine {
    static func today(_ d: Date = Date()) -> String {
        let g = Cal.dmy(d, greg: true), h = Cal.dmy(d, greg: false)
        let gm = Lang.isEN ? Words.gmEN[g.m - 1] : (Settings.shamiMonths ? Words.gs[g.m - 1] : Words.gm[g.m - 1])
        let hm = Lang.isEN ? Words.hmEN[h.m - 1] : Words.hm[h.m - 1]
        return "\(ar(g.d)) \(gm)  |  \(ar(h.d)) \(hm) \(ar(h.y))"
    }
}

/// «يوم واحد / يومان / ٥ أيام / ١٢ يومًا»
func daysText(_ n: Int) -> String {
    if Lang.isEN { return n == 1 ? "1 day" : "\(n) days" }
    switch n {
    case 0: return "لا شيء"
    case 1: return "يوم واحد"
    case 2: return "يومان"
    case 3...10: return "\(ar(n)) أيام"
    default: return "\(ar(n)) يومًا"
    }
}

/// زر دائري زجاجي
struct CircleButton: View {
    let icon: String
    var tint: Color = .white
    var size: CGFloat = 44
    let action: () -> Void
    @ViewBuilder var body: some View {
        let b = Button(action: action) { CircleIcon(icon: icon, tint: tint, size: size) }.buttonStyle(PressStyle())
        if let n = Self.names[icon] { b.accessibilityLabel(L(n)) } else { b }
    }
    /// أسماء مقروءة للأزرار الدائرية (لـVoiceOver بدل اسم الرمز)
    static let names = ["xmark": "إغلاق", "chevron.backward": "رجوع", "calendar": "التقويم",
                        "location.north.line.fill": "القبلة", "arrow.left.arrow.right": "تحويل التاريخ",
                        "chevron.right": Lang.isEN ? "التالي" : "السابق", "chevron.left": Lang.isEN ? "السابق" : "التالي"]
}

struct CircleIcon: View {
    let icon: String
    var tint: Color = .white
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(.ultraThinMaterial))
            .overlay(Circle().strokeBorder(Theme.edge, lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

/// شريحة اختيار (مثل أقسام المعرض)
struct Chip: View {
    let title: String
    var icon: String? = nil
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(Theme.f(.caption)) }
                Text(L(title)).font(Theme.title(15))
            }
            .foregroundStyle(on ? Color.black : .white)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(Capsule().fill(on ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(.ultraThinMaterial)))
            .overlay(Capsule().strokeBorder(on ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.edge), lineWidth: 1))
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(.plain)
    }
}

/// شارة المقاس (٢×٢، ٤×٢، ٤×٤)
struct SizeBadge: View {
    let text: String
    var body: some View {
        Text(text).font(Theme.title(12)).foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .environment(\.layoutDirection, .leftToRight)
    }
}


/// صف شرائح للتنقّل بين أقسام الصفحة
struct ChipBar: View {
    let items: [String]
    @Binding var selection: Int
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                    Chip(title: t, on: selection == i) { withAnimation(.snappy) { selection = i } }
                }
            }
            .padding(.horizontal, 2).padding(.vertical, 2)
        }
    }
}

extension View {
    /// صف شفاف بلا هوامش داخل القوائم (للعناوين والبطاقات الكبيرة)
    func bareRow(top: CGFloat = 4, bottom: CGFloat = 4) -> some View {
        self.listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0))
            .listRowSeparator(.hidden)
    }
}

// MARK: - شريط التبويب العائم

struct TabItem: Identifiable {
    let tag: Int
    let title: String
    let icon: String
    var id: Int { tag }
}

struct FloatingTabBar: View {
    @Binding var tab: Int
    let items: [TabItem]
    @Namespace private var ns
    var body: some View {
        // كل زر بعرض نصه (لا يُقص «المسموع والمرئي» ولا «إدارة الملفات»)، والمسافات الباقية موزّعة بينها
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                if i > 0 { Spacer(minLength: 0) }
                let on = tab == it.tag
                Button {
                    withAnimation(.snappy(duration: 0.28)) { tab = it.tag }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: it.icon).font(.system(size: 18, weight: .semibold))
                        Text(L(it.title))
                            .font(Lang.isEN ? .system(size: 12, weight: .bold, design: .rounded) : .custom(Theme.tajawal(.bold), fixedSize: 12))
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(on ? Color.black : .white.opacity(0.72))
                    .padding(.horizontal, 9)
                    .frame(minWidth: 58)
                    .padding(.vertical, 8)
                    .background {
                        if on { Capsule().fill(Theme.gold).matchedGeometryEffect(id: "sel", in: ns) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 16)
    }
}

/// أيقونة الصفوف: رمز ذهبي رفيع داخل مربع زجاجي داكن — نمط واحد في كل التطبيق
/// (اللون الممرَّر يُتجاهل عمدًا: الألوان الكثيرة كانت تعطي مظهرًا طفوليًا)
struct IconTile: View {
    let name: String
    var color: Color = Theme.gold
    var size: CGFloat = 32
    var body: some View { Badge(name: name, size: size) }
}

/// شارة الرمز الموحّدة
struct Badge: View {
    let name: String
    var size: CGFloat = 34
    var active = false
    var dim = false
    var body: some View {
        Image(systemName: name)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(active ? Theme.gold : (dim ? Color.white.opacity(0.45) : Theme.gold.opacity(0.92)))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(active ? Theme.gold.opacity(0.16) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(active ? Theme.gold.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 0.8)
            )
    }
}

/// رموز الأوقات داخل التطبيق (خطية ومتناسقة)
let APP_PR_ICON: [PKey: String] = [.fajr: "moon.haze", .sunrise: "sunrise", .dhuhr: "sun.max", .jumuah: "sun.max",
                                   .asr: "sun.min", .maghrib: "sunset", .isha: "moon.stars", .midnight: "moon"]

/// صف بأيقونة ونص (للإعدادات)
struct TileRow: View {
    let title: String
    let icon: String
    var color: Color = Theme.gold
    var subtitle: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            IconTile(name: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title)).foregroundStyle(.white)
                if let subtitle { Text(L(subtitle)).font(Theme.f(.caption)).foregroundStyle(Theme.sub) }
            }
            Spacer(minLength: 0)
        }
    }
}

/// شكل القمر حسب اليوم الهجري
struct MoonView: View {
    let day: Int
    var body: some View {
        let phase = min(0.999, max(0.001, (Double(day) - 0.5) / 29.53))
        ZStack {
            Circle().fill(Color.white.opacity(0.10))
            MoonLit(phase: phase).fill(
                LinearGradient(colors: [Color(red: 1, green: 0.97, blue: 0.86), Color(red: 0.93, green: 0.86, blue: 0.66)],
                               startPoint: .top, endPoint: .bottom))
        }
        .shadow(color: Color(red: 1, green: 0.92, blue: 0.7).opacity(0.35), radius: 12)
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct MoonLit: Shape {
    let phase: Double   // ٠ محاق — ٠٫٥ بدر — ١ محاق
    func path(in r: CGRect) -> Path {
        let R = min(r.width, r.height) / 2, c = CGPoint(x: r.midX, y: r.midY)
        let s: CGFloat = phase < 0.5 ? 1 : -1               // المتزايد مضيء من اليمين
        let k = CGFloat(cos(2 * Double.pi * phase))
        var p = Path()
        let n = 48
        for i in 0...n {                                     // الحافة المضيئة من فوق لتحت
            let t = -Double.pi / 2 + Double.pi * Double(i) / Double(n)
            let pt = CGPoint(x: c.x + s * R * CGFloat(cos(t)), y: c.y + R * CGFloat(sin(t)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        for i in 0...n {                                     // خط الظل من تحت لفوق
            let t = Double.pi / 2 - Double.pi * Double(i) / Double(n)
            p.addLine(to: CGPoint(x: c.x + s * R * k * CGFloat(cos(t)), y: c.y + R * CGFloat(sin(t))))
        }
        p.closeSubpath()
        return p
    }
}



/// زر الرجوع داخل الصفحة (للصفحات ذات العنوان الكبير بدل شريط التنقّل الذي كان يتداخل مع العنوان عند التمرير)
struct BackRow: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack {
            CircleButton(icon: "chevron.backward", size: 40) { dismiss() }
            Spacer()
        }
    }
}

/// السحب من حافة الشاشة للرجوع يبقى يعمل حتى مع إخفاء شريط التنقّل
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
