import SwiftUI
import WidgetKit

// MARK: - الرئيسية: الصلاة القادمة، الاختصارات، مواقيت اليوم، التاريخ، الليل

enum HomeRoute: Hashable { case qibla, calendar, timetable }

/// فتح صفحة في الرئيسية من خارجها (مركز التحكم)
@MainActor
final class HomeRouter: ObservableObject {
    static let shared = HomeRouter()
    @Published var open: HomeRoute?
}

struct HomeView: View {
    var openGallery: () -> Void = {}
    var openTab: (Int) -> Void = { _ in }
    @State private var weather: WeatherData? = Weather.cached()
    @State private var path: [HomeRoute] = SHOT == "qibla" ? [.qibla] : (SHOT.hasPrefix("calendar") ? [.calendar] : [])
    @AppStorage("home.widgetsSeen") private var widgetsSeen = false
    @ObservedObject private var router = HomeRouter.shared

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                TimelineView(.periodic(from: .now, by: 15)) { tl in
                    // الرئيسية مبنية من الويدجت نفسها بحجم أكبر (التصميم المعتمد): نفس الخط والخامة في كل مكان
                    let W = min(UIScreen.main.bounds.width - 32, 520)
                    VStack(spacing: 14) {
                        brandHeader
                        HomeWidget(id: "r2.today", family: .systemMedium, width: W, date: tl.date, weather: weather) { path.append(.timetable) }
                        HStack(spacing: 12) {
                            HomeWidget(id: "r2.occ", family: .systemSmall, width: (W - 12) / 2, date: tl.date, weather: weather) { path.append(.calendar) }
                            HomeWidget(id: "r2.next", family: .systemSmall, width: (W - 12) / 2, date: tl.date, weather: weather) { path.append(.timetable) }
                        }
                        HomeWidget(id: "r2.dhikr", family: .systemMedium, width: W, date: tl.date, weather: weather) {}
                        HomeWidget(id: "r2.playerm", family: .systemMedium, width: W, date: tl.date, weather: weather) { openTab(4) }
                        // تعريف بالويدجت يظهر حتى تزور المعرض أول مرة (تبويب الويدجت موجود دائمًا)
                        if !widgetsSeen {
                            WidgetsPromo(home: { widgetsSeen = true; GalleryNav.shared.lock = false; openGallery() },
                                         lock: { widgetsSeen = true; GalleryNav.shared.lock = true; openGallery() })
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
            }
            .scrollIndicators(.hidden)
            .barSpace()
            .background(AppBackground())
            .hiddenNavBar()
            .navigationDestination(for: HomeRoute.self) { r in
                switch r {
                case .qibla: QiblaView()
                case .calendar: UmmAlQuraView()
                case .timetable: MonthlyTimetableView()
                }
            }
            .onChange(of: router.open, initial: true) { _, r in
                guard let r else { return }
                router.open = nil
                path = [r]
            }
            .task {
                if await LocationSync.refreshIfNeeded() { reloadWidgets() }
                weather = await Weather.load()
            }
        }
    }

    var brandHeader: some View {
        HStack(spacing: 10) {
            CircleButton(icon: "calendar") { path.append(.calendar) }
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Fit("app_title_t", 120, 52)
                Text(DateLine.today()).font(Theme.title(13)).foregroundStyle(Theme.sub)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            CircleButton(icon: "location.north.line.fill") { path.append(.qibla) }
        }
        .padding(.top, 4)
    }
}

/// ويدجت معروضة داخل التطبيق بعرض الشاشة، والضغط عليها يفتح صفحتها (أزرارها الداخلية تعمل كما في الشاشة الرئيسية)
private struct HomeWidget: View {
    let id: String
    let family: WidgetFamily
    let width: CGFloat
    let date: Date
    let weather: WeatherData?
    var open: () -> Void
    var body: some View {
        let s = WidgetPreview.size(family)
        let k = width / s.width
        WidgetPreview(info: Catalog.info(id), family: family, date: date, weather: weather, tint: Tint.appColor)
            .scaleEffect(k)
            .frame(width: width, height: s.height * k)
            .contentShape(RoundedRectangle(cornerRadius: 24 * k, style: .continuous))
            .onTapGesture { open() }
    }
}

// MARK: - ألوان السماء حسب الوقت

extension PKey {
    /// لون الوقت (للأيقونات والبطاقات)
    var tint: Color {
        switch self {
        case .fajr: return Color(red: 0.36, green: 0.78, blue: 0.45)
        case .sunrise: return Color(red: 0.98, green: 0.80, blue: 0.25)
        case .dhuhr, .jumuah: return Color(red: 0.98, green: 0.60, blue: 0.25)
        case .asr: return Color(red: 0.35, green: 0.75, blue: 0.92)
        case .maghrib: return Color(red: 0.78, green: 0.40, blue: 0.90)
        case .isha: return Color(red: 0.42, green: 0.40, blue: 0.95)
        case .midnight: return Color(red: 0.40, green: 0.46, blue: 0.72)
        }
    }
    /// سماء الفترة التي تسبق هذا الوقت
    var sky: [Color] {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch self {
        case .fajr, .midnight: return [c(0.05, 0.07, 0.20), c(0.15, 0.17, 0.42)]
        case .sunrise: return [c(0.13, 0.17, 0.40), c(0.72, 0.40, 0.46)]
        case .dhuhr, .jumuah: return [c(0.10, 0.40, 0.68), c(0.40, 0.72, 0.88)]
        case .asr: return [c(0.16, 0.46, 0.70), c(0.90, 0.68, 0.40)]
        case .maghrib: return [c(0.80, 0.42, 0.24), c(0.50, 0.22, 0.42)]
        case .isha: return [c(0.24, 0.17, 0.44), c(0.07, 0.10, 0.24)]
        }
    }
    var isDay: Bool { self == .sunrise || self == .dhuhr || self == .jumuah || self == .asr || self == .maghrib }
}

// MARK: - الويدجت

struct WidgetsPromo: View {
    let home: () -> Void
    let lock: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.gold.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ويدجت رفيقي").font(Theme.title(18)).foregroundStyle(.white)
                    Text(LF("%@ ويدجت للشاشة الرئيسية و%@ لشاشة القفل", ar(Catalog.all.count), ar(Catalog.lock.count)))
                        .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                button("الشاشة الرئيسية", "iphone", home)
                button("شاشة القفل", "lock.fill", lock)
            }
        }
        .glassCard(padding: 16)
    }

    func button(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(Theme.f(.footnote, .semibold))
                Text(L(title)).font(Theme.title(14))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(Capsule().fill(Theme.cardHi))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }
}
