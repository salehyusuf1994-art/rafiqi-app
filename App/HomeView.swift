import SwiftUI
import WidgetKit

// MARK: - الرئيسية: الصلاة القادمة، الاختصارات، مواقيت اليوم، التاريخ، الليل

enum HomeRoute: Hashable { case qibla, calendar }

struct HomeView: View {
    var openGallery: () -> Void = {}
    var openTab: (Int) -> Void = { _ in }
    @State private var weather: WeatherData? = Weather.cached()
    @State private var path: [HomeRoute] = SHOT == "qibla" ? [.qibla] : (SHOT.hasPrefix("calendar") ? [.calendar] : [])

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                TimelineView(.periodic(from: .now, by: 15)) { tl in
                    VStack(spacing: 18) {
                        brandHeader
                        NextPrayerHero(date: tl.date, weather: weather)
                        QuickActions(qibla: { path.append(.qibla) }, calendar: { path.append(.calendar) },
                                     audio: { openTab(4) }, matches: { openTab(5) })
                        PrayerTimesCard(date: tl.date)
                        TodayCard(date: tl.date)
                        NightCard(date: tl.date)
                        WidgetsPromo(home: { GalleryNav.shared.lock = false; openGallery() },
                                     lock: { GalleryNav.shared.lock = true; openGallery() })
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
            }
            .scrollIndicators(.hidden)
            .barSpace()
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { r in
                switch r {
                case .qibla: QiblaView()
                case .calendar: UmmAlQuraView()
                }
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
                    Text(STime.ampm(st.next.time)).font(Theme.title(12)).foregroundStyle(.white.opacity(0.7))
                }
            }
            Text(timerInterval: Date()...max(Date(), st.next.time), countsDown: true)
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
            Fit("pr_\(p.key.rawValue)_t", p.key == .midnight ? 78 : 58, 24, 0.95)
            Digits(text: hm12(p.time), size: 14, color: .white.opacity(0.8))
        }
    }
}

// MARK: - الاختصارات

struct QuickActions: View {
    let qibla: () -> Void
    let calendar: () -> Void
    let audio: () -> Void
    let matches: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            tile("القبلة", "location.north.line.fill", Color(red: 0.20, green: 0.70, blue: 0.55), qibla)
            tile("التقويم", "calendar", Color(red: 0.95, green: 0.55, blue: 0.30), calendar)
            tile("المسموع والمرئي", "play.rectangle.fill", Theme.violet, audio)
            tile("المباريات", "soccerball", Color(red: 0.25, green: 0.55, blue: 0.95), matches)
        }
    }

    func tile(_ title: String, _ icon: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(color.gradient))
                    .shadow(color: color.opacity(0.5), radius: 8, y: 4)
                Text(L(title)).font(Theme.title(13)).foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassCard(padding: 0, radius: 22)
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - مواقيت اليوم

struct PrayerTimesCard: View {
    let date: Date
    var body: some View {
        let times = Prayer.dayTimes(date)
        let next = Prayer.prevNext(at: date).next
        VStack(spacing: 6) {
            HStack {
                Text("مواقيت اليوم").font(Theme.title(18)).foregroundStyle(.white)
                Spacer()
                Text(verbatim: Settings.method.short).font(.caption).foregroundStyle(Theme.sub)
            }
            .padding(.horizontal, 4).padding(.bottom, 4)
            ForEach(Array(times.enumerated()), id: \.offset) { _, p in
                let on = p.time == next.time
                let passed = p.time < date && !on
                HStack(spacing: 12) {
                    Image(systemName: PR_ICON[p.key] ?? "sun.max").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 34, height: 34)
                        .background(Circle().fill(p.key.tint.gradient))
                    Fit("pr_\(p.key.rawValue)_t", 74, 28, 1)
                    Spacer(minLength: 4)
                    if on {
                        Text(timerInterval: Date()...max(Date(), p.time), countsDown: true)
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.gold)
                            .multilineTextAlignment(.center)
                            .frame(width: 70)
                            .environment(\.layoutDirection, .leftToRight)
                    } else if passed {
                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(Theme.sub)
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
            // اسم اليوم، وتحته اسم الموقع
            VStack(spacing: 4) {
                Fit("wd\(Cal.weekday(date))_t", 190, 78)
                HStack(spacing: 5) {
                    Image(systemName: Settings.isAuto ? "location.fill" : "mappin.and.ellipse").font(.system(size: 12, weight: .semibold))
                    Text(verbatim: Settings.placeName.isEmpty ? L("موقعك الحالي") : Settings.placeName)
                        .font(Theme.title(15)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(Theme.sub)
            }
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
                    Text(LF("اليوم %@ من %@", ar(mi.day), ar(mi.len))).font(.caption).foregroundStyle(Theme.sub)
                    Spacer()
                    Text(mi.len - mi.day <= 0 ? L("آخر يوم في الشهر") : LF("المتبقي: %@", daysText(mi.len - mi.day)))
                        .font(.caption).foregroundStyle(Theme.sub)
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
                Text(L(label)).font(.caption2).foregroundStyle(Theme.sub)
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
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(red: 0.30, green: 0.34, blue: 0.66).gradient))
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
                        .font(.caption).foregroundStyle(Theme.sub)
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
                Image(systemName: icon).font(.footnote.weight(.semibold))
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
