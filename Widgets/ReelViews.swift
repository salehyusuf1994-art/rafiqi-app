import SwiftUI
import WidgetKit
import AppIntents

// MARK: - بكرة الإذاعات والقنوات في الويدجت: تقلّب القائمة بالأسهم وتختار مباشرة

/// يفتح قناة في التطبيق (من ويدجت القنوات)
struct OpenTVIntent: AppIntent {
    static let title: LocalizedStringResource = "فتح قناة"
    static let isDiscoverable = false
    static let openAppWhenRun = true
    @Parameter(title: "القناة") var channel: String
    init() {}
    init(_ id: String) { channel = id }
    @MainActor
    func perform() async throws -> some IntentResult {
        // يُقرأ في التطبيق عند فتحه (وإن كان التطبيق يعمل يفتحها فورًا)
        if let open = TVBridge.open {
            open(channel)
        } else {
            AppGroup.defaults.set(channel, forKey: "tv_open")
            AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: "tv_open_at")
        }
        return .result()
    }
}

enum TVBridge {
    /// يضبطه التطبيق عند تشغيله؛ وفي امتداد الويدجت يبقى فارغًا
    @MainActor static var open: (@MainActor (String) -> Void)?
}

/// شعار إذاعة أو قناة: المحفوظ في المجلد المشترك، وإلا رمز بلون
struct ReelLogo: View {
    let url: String?
    let icon: String
    var color: Color = .white
    var size: CGFloat = 30
    var corner: CGFloat? = nil
    var body: some View {
        let r = corner ?? size * 0.28
        ZStack {
            if let img = LogoCache.image(url) {
                RoundedRectangle(cornerRadius: r, style: .continuous).fill(Color.white)
                SImage(img: img).padding(size * 0.1)
            } else {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.55), color.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: icon).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
    }
}

/// سهم تقليب البكرة
private struct ReelArrow: View {
    let kind: String
    let delta: Int
    let icon: String
    var size: CGFloat = 26
    var body: some View {
        Button(intent: ReelIntent(kind, delta)) {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

private let RADIO_TINT = Color(red: 0.20, green: 0.62, blue: 0.70)

/// «بكرة الإذاعات» (متوسط): الإذاعة الحالية وأزرارها، وبجانبها قائمة تقلّبها وتختار منها
struct RadioTunerView: View {
    let entry: HEntry
    var body: some View {
        let np = NowPlaying.display(for: "radio")
        let list = Reel.window(Stations.reel, kind: "radio", count: 3)
        let cur = AppGroup.defaults.string(forKey: "last_station")
        Root(entry: entry) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Circle().fill(np.playing ? Color.red : TXT.opacity(0.5)).frame(width: 6, height: 6)
                        Text(Lang.isEN ? "LIVE" : "مباشر").font(.system(size: 10, weight: .bold)).foregroundStyle(TXT.opacity(0.8))
                    }
                    MTitle(text: np.title, size: 18)
                    MSub(text: np.subtitle, size: 11)
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        MBtn(action: "prev", icon: "backward.fill", size: 32)
                        MBtn(action: "toggle", icon: np.playing ? "stop.fill" : "play.fill", size: 42, fill: 0.2)
                        MBtn(action: "next", icon: "forward.fill", size: 32)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // ارتفاع المتوسط ~١٤٠ نقطة بعد الهوامش: ٣ إذاعات + سهمان تتسع بلا قص
                VStack(spacing: 3) {
                    ReelArrow(kind: "radio", delta: -1, icon: "chevron.up", size: 20)
                    ForEach(list, id: \.url) { s in
                        Button(intent: MediaControlIntent("station", source: s.url)) {
                            HStack(spacing: 7) {
                                ReelLogo(url: s.favicon, icon: "dot.radiowaves.left.and.right", color: RADIO_TINT, size: 22)
                                Text(s.name).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
                                    .lineLimit(1).minimumScaleFactor(0.75)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(s.url == cur ? 0.18 : 0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(s.url == cur ? TXT.opacity(0.6) : Color.white.opacity(0.10), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    ReelArrow(kind: "radio", delta: 1, icon: "chevron.down", size: 20)
                }
                .frame(width: 150)
            }
            .padding(12)
            .environment(\.mediaSource, "radio")
        }
    }
}

/// «بكرة الإذاعات» الصغيرة: الإذاعة الحالية، وإذاعتان من قائمتك تقلّبهما بالأسهم، وأزرار التحكم
struct RadioTunerSmallView: View {
    let entry: HEntry
    var body: some View {
        let np = NowPlaying.display(for: "radio")
        let list = Reel.window(Stations.reel, kind: "radio2", count: 2)
        let cur = AppGroup.defaults.string(forKey: "last_station")
        Root(entry: entry) {
            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    Circle().fill(np.playing ? Color.red : TXT.opacity(0.5)).frame(width: 6, height: 6)
                    MTitle(text: np.title, size: 13)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    VStack(spacing: 4) {
                        ForEach(list, id: \.url) { st in
                            Button(intent: MediaControlIntent("station", source: st.url)) {
                                HStack(spacing: 6) {
                                    ReelLogo(url: st.favicon, icon: "dot.radiowaves.left.and.right", color: RADIO_TINT, size: 22)
                                    Text(st.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 5).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(st.url == cur ? 0.18 : 0.07)))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(st.url == cur ? TXT.opacity(0.6) : Color.white.opacity(0.10), lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    VStack(spacing: 8) {
                        ReelArrow(kind: "radio2", delta: -1, icon: "chevron.up", size: 22)
                        ReelArrow(kind: "radio2", delta: 1, icon: "chevron.down", size: 22)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    MBtn(action: "prev", icon: "backward.fill", size: 30)
                    MBtn(action: "toggle", icon: np.playing ? "stop.fill" : "play.fill", size: 38, fill: 0.2)
                    MBtn(action: "next", icon: "forward.fill", size: 30)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(11)
            .environment(\.mediaSource, "radio")
        }
    }
}

/// «قرص الإذاعات» (صغير): قرص موالفة دائري بعلامات، الإذاعة الحالية في وسطه، والسابقة والتالية على حافته
/// تضغط الإذاعة الجانبية فيدور القرص إليها، وتضغط زر الوسط فتشتغل
struct RadioDialView: View {
    let entry: HEntry
    var body: some View {
        let np = NowPlaying.display(for: "radio")
        let all = Stations.reel
        let n = max(1, all.count)
        let page = ((Reel.page("radio1") % n) + n) % n
        let cur = all.isEmpty ? nil : all[page]
        let next = all.isEmpty ? nil : all[(page + 1) % n]
        let prev = all.isEmpty ? nil : all[(page - 1 + n) % n]
        let isCur = cur?.url == AppGroup.defaults.string(forKey: "last_station")
        let playing = isCur && np.playing
        Root(entry: entry) {
            GeometryReader { g in
                let d = min(g.size.width, g.size.height) - 16
                ZStack {
                    // القرص: حلقة بعلامات موالفة تدور مع التقليب
                    DialRing(turn: Double(page) * 18)
                        .frame(width: d, height: d)
                    // مؤشر الموالفة في الأعلى
                    Capsule().fill(playing ? Color.red : TXT)
                        .frame(width: 3, height: d * 0.09)
                        .offset(y: -d / 2 + d * 0.045)
                    if let cur {
                        VStack(spacing: 3) {
                            ReelLogo(url: cur.favicon, icon: "dot.radiowaves.left.and.right", color: RADIO_TINT, size: d * 0.34, corner: d * 0.17)
                            Text(cur.name).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .frame(width: d * 0.52)
                            Button(intent: MediaControlIntent(isCur ? "toggle" : "station", source: isCur ? "radio" : cur.url)) {
                                Image(systemName: playing ? "stop.fill" : "play.fill")
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Color.white))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // السابقة والتالية على حافة القرص (يسار = التالية في القراءة العربية)
                    if all.count > 1, let next, let prev {
                        neighbor(next, delta: 1, icon: "chevron.left", d: d)
                            .offset(x: -d / 2 + d * 0.10, y: d * 0.08)
                        neighbor(prev, delta: -1, icon: "chevron.right", d: d)
                            .offset(x: d / 2 - d * 0.10, y: d * 0.08)
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
                .environment(\.layoutDirection, .leftToRight)
            }
            .environment(\.mediaSource, "radio")
        }
    }

    private func neighbor(_ s: Station, delta: Int, icon: String, d: CGFloat) -> some View {
        Button(intent: ReelIntent("radio1", delta)) {
            ZStack(alignment: delta > 0 ? .leading : .trailing) {
                ReelLogo(url: s.favicon, icon: "dot.radiowaves.left.and.right", color: RADIO_TINT, size: d * 0.2, corner: d * 0.1)
                    .opacity(0.55)
                Image(systemName: icon).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .offset(x: delta > 0 ? -6 : 6)
            }
        }
        .buttonStyle(.plain)
    }
}

/// حلقة قرص الموالفة: ٧٢ علامة (كل عاشرة أطول) وحافة رفيعة
struct DialRing: View {
    var turn: Double = 0
    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.05))
            Circle().stroke(Color.white.opacity(0.16), lineWidth: 1)
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let r: CGFloat = sz.width / 2 - 3
                for i in 0..<72 {
                    let major = i % 6 == 0
                    let a: CGFloat = CGFloat(i) * .pi / 36
                    let len: CGFloat = major ? r * 0.10 : r * 0.05
                    let sa: CGFloat = sin(a), ca: CGFloat = cos(a)
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + sa * r, y: c.y - ca * r))
                    p.addLine(to: CGPoint(x: c.x + sa * (r - len), y: c.y - ca * (r - len)))
                    ctx.stroke(p, with: .color(Color.white.opacity(major ? 0.55 : 0.25)), lineWidth: major ? 1.4 : 0.8)
                }
            }
            .rotationEffect(.degrees(turn))
        }
    }
}

/// «بكرة القنوات» (متوسط): أربع قنوات بشعاراتها، تقلّبها بالأسهم وتفتح البث بضغطة
struct TVReelView: View {
    let entry: HEntry
    var body: some View {
        let all = TVChannels.reel
        let list = Reel.window(all, kind: "tv", count: 4)
        let pages = max(1, Int((Double(all.count) / 4).rounded(.up)))
        let page = ((Reel.page("tv") % pages) + pages) % pages
        Root(entry: entry) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "tv.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(TXT.opacity(0.8))
                    Text(Lang.isEN ? "Channels" : "القنوات").font(.system(size: 13, weight: .bold)).foregroundStyle(TXT)
                    Spacer(minLength: 0)
                    Text(verbatim: "\(ar(page + 1))/\(ar(pages))").font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(TXT.opacity(0.55))
                        .environment(\.layoutDirection, .leftToRight)
                }
                HStack(spacing: 6) {
                    ReelArrow(kind: "tv", delta: -1, icon: Lang.isEN ? "chevron.left" : "chevron.right", size: 24)
                    ForEach(list) { c in
                        // في المتوسط: رابط مباشر يفتح القناة في التطبيق (أضمن من الأمر)
                        Link(destination: URL(string: "miqat://tv/" + c.id) ?? URL(string: "miqat://media")!) {
                            VStack(spacing: 4) {
                                ReelLogo(url: c.logo, icon: c.cat.icon, color: c.cat.color, size: 54, corner: 14)
                                Text(c.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                    ReelArrow(kind: "tv", delta: 1, icon: Lang.isEN ? "chevron.right" : "chevron.left", size: 24)
                }
            }
            .padding(14)
        }
    }
}

/// «قناة» (صغير): قناة واحدة بشعارها وتصنيفها، تقلّب بالأسهم وتفتح البث
struct TVOneView: View {
    let entry: HEntry
    var body: some View {
        let c = Reel.window(TVChannels.reel, kind: "tv1", count: 1).first
        Root(entry: entry) {
            VStack(spacing: 6) {
                if let c {
                    Button(intent: OpenTVIntent(c.id)) {
                        VStack(spacing: 6) {
                            ReelLogo(url: c.logo, icon: c.cat.icon, color: c.cat.color, size: 66, corner: 18)
                            Text(c.name).font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Label(c.cat.title, systemImage: c.cat.icon).font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(c.cat.color)
                        }
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    // يسار = التالي، يمين = السابق (اتجاه القراءة العربية)
                    ReelArrow(kind: "tv1", delta: 1, icon: "chevron.left", size: 26)
                    Spacer(minLength: 0)
                    ReelArrow(kind: "tv1", delta: -1, icon: "chevron.right", size: 26)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(12)
        }
    }
}
