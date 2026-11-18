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

// MARK: - الصلاة القادمة

struct NextPrayerHero: View {
    let date: Date
    let weather: WeatherData?
    var body: some View {
        let st = Prayer.prevNext(at: date)
        let key = st.next.key
        let h = Cal.dmy(date, greg: false)
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: Settings.isAuto ? "location.fill" : "mappin.and.ellipse").font(.system(size: 11, weight: .semibold))
                    Text(Settings.placeName.isEmpty ? L("موقعك الحالي") : Settings.placeName).font(Theme.title(13)).lineLimit(1)
                }
                .pill()
                Spacer(minLength: 0)
                if let w = weather {
                    HStack(spacing: 5) {
                        WxIcon(w: w, size: 20)
                        Digits(text: Weather.deg(w.temp), size: 15, color: .white, bold: true)
                    }
                    .pill()
                }
            }
            VStack(spacing: 0) {
                Text(key == .midnight || key == .sunrise ? "الوقت القادم" : "الصلاة القادمة").font(Theme.title(14)).foregroundStyle(.white.opacity(0.78))
                Fit("pr_\(key.rawValue)_t", key == .midnight ? 210 : 170, 66)
                HStack(spacing: 6) {
                    Digits(text: hm12(st.next.time), size: 17, color: .white.opacity(0.9), bold: true)
                    Text(ampmText(st.next.time)).font(Theme.title(12)).foregroundStyle(.white.opacity(0.7))
                }
            }
            // العدّاد دائمًا بالساعات «٠:١٤:١٠» حتى لا يُقرأ كأنه ساعة
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(verbatim: hmsText(st.next.time.timeIntervalSince(ctx.date)))
                    .contentTransition(.numericText(countsDown: true))
            }
                .font(digitFont(50, bold: true))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .leftToRight)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            ProgressTrack(progress: st.progress).padding(.horizontal, 4)
            HStack(alignment: .top) {
                PointLabel(p: st.prev)
                Spacer()
                PointLabel(p: st.next)
            }
        }
        .padding(18)
        .background {
            ZStack {
                LinearGradient(colors: key.sky, startPoint: .top, endPoint: .bottom)
                // الشمس نهارًا والقمر ليلًا
                if key.isDay {
                    Circle().fill(Color(red: 1, green: 0.86, blue: 0.55).opacity(0.55)).frame(width: 150, height: 150)
                        .blur(radius: 40).offset(x: 120, y: -90)
                } else {
                    MoonView(day: h.d).frame(width: 46, height: 46).opacity(0.85).offset(x: 130, y: -96)
                    StarField().opacity(0.5)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .center, endPoint: .bottom)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
        .shadow(color: key.sky[0].opacity(0.45), radius: 22, y: 12)
    }
}

/// نجوم ثابتة صغيرة (للّيل)
struct StarField: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 7
            for _ in 0..<40 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let x = CGFloat(seed >> 33 % 1000) / 1000 * size.width
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let y = CGFloat(seed >> 33 % 1000) / 1000 * size.height * 0.6
                let r: CGFloat = (seed >> 40) % 3 == 0 ? 1.6 : 1
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.8)))
            }
        }
    }
}

extension View {
    /// شريحة زجاجية صغيرة فوق البطاقات الملوّنة
    func pill() -> some View {
        self.foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

struct ProgressTrack: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, x = max(8, CGFloat(progress) * w)
            // يمتلئ من اليمين (السابقة) لليسار (القادمة)
            ZStack(alignment: .trailing) {
                Capsule().fill(Color.white.opacity(0.22)).frame(height: 6)
                Capsule().fill(Color.white).frame(width: x, height: 6)
            }
            .frame(width: w, height: 18)
            .overlay(
                Circle().fill(Color.white)
                    .shadow(color: .white.opacity(0.8), radius: 6)
                    .frame(width: 14, height: 14)
                    .position(x: w - x, y: 9)
            )
        }
        .frame(height: 18)
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct PointLabel: View {
    let p: PTime
    var body: some View {
        VStack(spacing: 0) {
            PrName(p.key, 58, 24, 0.95)
            Digits(text: hm12(p.time), size: 14, color: .white.opacity(0.8))
        }
    }
}

// MARK: - مواقيت اليوم

struct PrayerTimesCard: View {
    let date: Date
    var month: () -> Void = {}
    var body: some View {
        let times = Prayer.dayTimes(date)
        let next = Prayer.prevNext(at: date).next
        VStack(spacing: 6) {
            HStack {
                Text("مواقيت اليوم").font(Theme.title(18)).foregroundStyle(.white)
                Spacer()
                Button(action: month) {
                    Label("جدول الشهر", systemImage: "tablecells").font(Theme.f(.caption, .bold)).foregroundStyle(Theme.gold)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Theme.cardHi))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4).padding(.bottom, 4)
            ForEach(Array(times.enumerated()), id: \.offset) { _, p in
                let on = p.time == next.time
                let passed = p.time < date && !on
                HStack(spacing: 12) {
                    Badge(name: APP_PR_ICON[p.key] ?? "sun.max", size: 34, active: on, dim: passed)
                    Fit("pr_\(p.key.rawValue)_t", 74, 28, 1)
                    Spacer(minLength: 4)
                    if on {
                        // العدّاد في البطاقة الكبيرة أعلاه؛ هنا علامة «القادمة» فقط
                        Text("القادمة").font(Theme.title(12)).foregroundStyle(.black)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Theme.gold))
                    }
                    Digits(text: hm12(p.time), size: 18, color: on ? Theme.gold : .white, bold: on)
                        .frame(minWidth: 58, alignment: .trailing)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? Theme.gold.opacity(0.13) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? Theme.gold.opacity(0.5) : .clear, lineWidth: 1))
                .opacity(passed ? 0.6 : 1)
            }
        }
        .glassCard(padding: 14)
    }
}

// MARK: - التاريخ اليوم

struct TodayCard: View {
    let date: Date
    var body: some View {
        let h = Cal.dmy(date, greg: false), g = Cal.dmy(date, greg: true)
        let mi = Cal.monthInfo(date, greg: false)
        VStack(spacing: 14) {
            // اسم اليوم (الموقع ظاهر في البطاقة الكبيرة أعلى الصفحة)
            Fit("wd\(Cal.weekday(date))_t", 190, 78)
                .frame(maxWidth: .infinity)
            Rectangle().fill(Theme.stroke).frame(height: 1)
            HStack(alignment: .top, spacing: 10) {
                DateBlock(names: ["pn\(h.d)", "hm\(h.m)"], year: "hyl\(clampY(h.y, 1440, 1470))_t", label: "هجري")
                Spacer(minLength: 0)
                DateBlock(names: ["pn\(g.d)", "gm\(g.m)"], year: "gyl\(clampY(g.y, 2020, 2050))_t", label: "ميلادي")
            }
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(LinearGradient(colors: [Theme.goldDeep, Theme.gold], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, geo.size.width * CGFloat(mi.day) / CGFloat(max(1, mi.len))))
                    }
                }
                .frame(height: 6)
                .environment(\.layoutDirection, Lang.dir)
                HStack {
                    Text(LF("اليوم %@ من %@", ar(mi.day), ar(mi.len))).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                    Spacer()
                    Text(mi.len - mi.day <= 0 ? L("آخر يوم في الشهر") : LF("المتبقي: %@", daysText(mi.len - mi.day)))
                        .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                }
            }
        }
        .glassCard(padding: 16)
    }
}

struct DateBlock: View {
    let names: [String]
    let year: String
    let label: String
    var body: some View {
        let s = min(0.40, 150 / lineWidth(names, GAP_PX, 1))
        VStack(alignment: .leading, spacing: -4) {
            CLine(names: names, s: s)
            HStack(spacing: 6) {
                Fit(year, 64, 15, 0.9)
                Text(L(label)).font(Theme.f(.caption2)).foregroundStyle(Theme.sub)
            }
        }
    }
}

// MARK: - منتصف الليل والثلث الأخير

struct NightCard: View {
    let date: Date
    var body: some View {
        let t = Prayer.times(for: date)
        let base = date < t[0] ? (Cal.gregCal.date(byAdding: .day, value: -1, to: date) ?? date) : date
        let next = Cal.gregCal.date(byAdding: .day, value: 1, to: base) ?? base
        let mg = Prayer.times(for: base)[4], fj = Prayer.times(for: next)[0]
        let span = fj.timeIntervalSince(mg)
        let mid = mg.addingTimeInterval(span / 2), third = mg.addingTimeInterval(span * 2 / 3)
        HStack(spacing: 0) {
            item(icon: "moon.zzz.fill", title: "منتصف الليل", time: mid)
            Rectangle().fill(Theme.stroke).frame(width: 1, height: 40)
            item(icon: "moon.stars.fill", title: "الثلث الأخير", time: third)
        }
        .glassCard(padding: 14)
    }

    func item(icon: String, title: String, time: Date) -> some View {
        HStack(spacing: 10) {
            Badge(name: icon, size: 36)
            VStack(alignment: .leading, spacing: 0) {
                Text(L(title)).font(Theme.title(13)).foregroundStyle(Theme.sub)
                Digits(text: hm12(time), size: 20, color: .white, bold: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }
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
