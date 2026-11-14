import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer

// MARK: - القنوات التلفزيونية: الأقسام، والمشغّل، وتقليب القنوات

/// يفتح قناة من أي مكان (التبويب، الويدجت، الرابط)
@MainActor
final class TVRouter: ObservableObject {
    static let shared = TVRouter()
    @Published var open: TVChannel?

    func show(id: String) {
        guard let c = TVChannels.channel(id) else { return }
        open = c
    }

    /// قناة طُلبت من الويدجت قبل فتح التطبيق
    func checkPending() {
        let d = AppGroup.defaults
        guard let id = d.string(forKey: "tv_open"),
              Date().timeIntervalSince1970 - d.double(forKey: "tv_open_at") < 60 else { return }
        d.removeObject(forKey: "tv_open")
        show(id: id)
    }
}

// ── اتجاه الشاشة: التطبيق عمودي، والبث يسمح بالأفقي ──
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait
    @MainActor
    static func allowLandscape(_ on: Bool) {
        mask = on ? .allButUpsideDown : .portrait
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        for w in scene.windows { w.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        if !on { scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in } }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

// MARK: - تشغيل القناة: يجرّب روابطها بالترتيب حتى يعمل أحدها

@MainActor
final class TVPlayback: ObservableObject {
    @Published private(set) var channel: TVChannel
    @Published private(set) var loading = true
    @Published private(set) var failed = false
    let player = AVPlayer()
    private var index = 0
    private var statusObs: NSKeyValueObservation?
    private var timeout: Task<Void, Never>?

    /// البث الحالي (للتحكم من شاشة القفل وسماعات البلوتوث، ولإيقافه إذا شغّلت القرآن أو الإذاعة)
    static weak var current: TVPlayback?

    init(_ c: TVChannel) { channel = c }

    func start() {
        TVPlayback.current = self
        // نوقف القرآن أو الإذاعة قبل البث
        let a = AudioPlayer.shared
        if a.state.playing && a.state.source != .music { a.pause() }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        TVChannels.last = channel.id
        index = 0
        failed = false
        tryCurrent()
    }

    func switchTo(_ c: TVChannel) {
        guard c.id != channel.id else { return }
        channel = c
        start()
    }

    func retry() { start() }

    // ── التحكم (من الشاشة أو شاشة القفل) ──
    var isPlaying: Bool { player.rate > 0 }
    func play() {
        try? AVAudioSession.sharedInstance().setActive(true)
        if player.currentItem == nil { start() } else { player.play() }
        updateNowPlaying()
    }
    func pause() { player.pause(); updateNowPlaying() }
    func toggle() { isPlaying ? pause() : play() }
    /// القناة التالية/السابقة في القسم نفسه
    func zap(_ d: Int) {
        let list = TVChannels.list(channel.cat)
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == channel.id } ?? 0
        switchTo(list[((i + d) % list.count + list.count) % list.count])
    }

    /// اسم القناة وشعارها في شاشة القفل ومركز التحكم
    func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: channel.name,
            MPMediaItemPropertyArtist: channel.cat.title + " · " + L("بث مباشر"),
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let img = LogoCache.image(channel.logo) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func stop() {
        if TVPlayback.current === self {
            TVPlayback.current = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        timeout?.cancel()
        statusObs = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func tryCurrent() {
        timeout?.cancel()
        guard index < channel.urls.count, let u = URL(string: channel.urls[index]) else {
            loading = false
            failed = true
            player.replaceCurrentItem(with: nil)
            return
        }
        loading = true
        // قنوات تشترط ترويسة «المُحيل» من موقعها (مثل سبيستون)
        let asset = StreamAsset.make(u, headers: channel.httpHeaders)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 4
        statusObs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            let st = it.status
            Task { @MainActor in
                guard let self, self.player.currentItem === it else { return }
                if st == .failed { self.advance() }
                else if st == .readyToPlay { self.loading = false; self.timeout?.cancel(); self.updateNowPlaying() }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        // رابط لا يستجيب خلال ١٥ ثانية: ننتقل للرابط التالي
        let expected = index
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, !Task.isCancelled, self.loading, self.index == expected else { return }
            self.advance()
        }
    }

    private func advance() {
        index += 1
        tryCurrent()
    }
}

/// المشغّل بأزرار النظام (تشغيل، AirPlay، ملء الشاشة)
struct TVVideo: UIViewControllerRepresentable {
    let player: AVPlayer

    /// الصوت يكمل في الخلفية: النظام يوقف أي فيديو مربوط بالشاشة عند الخروج من التطبيق،
    /// فنفكّ المشغّل عن الشاشة عند الخروج (يكمل الصوت) ونعيده عند الرجوع
    @MainActor
    final class Coordinator {
        weak var vc: AVPlayerViewController?
        let player: AVPlayer
        private var wasPlaying = false
        private nonisolated(unsafe) var observers: [Any] = []
        init(player: AVPlayer) {
            self.player = player
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.wasPlaying = self.player.rate > 0
                }
            })
            observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.vc?.player = nil
                    if self.wasPlaying { self.player.play() }
                }
            })
            observers.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.vc?.player = self.player
                }
            })
        }
        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }

    func makeCoordinator() -> Coordinator { Coordinator(player: player) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        context.coordinator.vc = vc
        vc.player = player
        vc.videoGravity = .resizeAspect
        vc.allowsPictureInPicturePlayback = false
        vc.updatesNowPlayingInfoCenter = false
        return vc
    }
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        // في الخلفية يبقى المشغّل مفكوكًا عن الشاشة حتى يكمل الصوت
        if vc.player !== player && UIApplication.shared.applicationState != .background { vc.player = player }
    }
}

// MARK: - شاشة البث

struct TVPlayerScreen: View {
    @StateObject private var tv: TVPlayback
    @Environment(\.dismiss) private var dismiss
    @State private var favs = TVChannels.favorites

    @MainActor init(channel: TVChannel) { _tv = StateObject(wrappedValue: TVPlayback(channel)) }

    var body: some View {
        GeometryReader { g in
            let landscape = g.size.width > g.size.height
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                if landscape {
                    video.ignoresSafeArea()
                    closeButton.padding(16)
                } else {
                    VStack(spacing: 0) {
                        header
                        video
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                        zapper
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            tv.start()
            OrientationLock.allowLandscape(true)
        }
        .onDisappear {
            tv.stop()
            OrientationLock.allowLandscape(false)
        }
    }

    private var video: some View {
        ZStack {
            TVVideo(player: tv.player)
            if tv.loading && !tv.failed {
                ProgressView().controlSize(.large).tint(.white)
            }
            if tv.failed {
                VStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.system(size: 30)).foregroundStyle(.white.opacity(0.7))
                    Text("القناة غير متاحة الآن").font(Theme.title(16)).foregroundStyle(.white)
                    Text("قد يكون البث متوقفًا مؤقتًا أو غير متاح في منطقتك.").font(.caption).foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                    Button { tv.retry() } label: {
                        Label("إعادة المحاولة", systemImage: "arrow.clockwise").font(.subheadline.bold())
                            .foregroundStyle(.black).padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(Theme.gold))
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
        }
        .background(Color.black)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 38, height: 38).background(Circle().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        let c = tv.channel
        let fav = favs.contains(c.id)
        return HStack(spacing: 12) {
            closeButton
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: c.name).font(Theme.title(18)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 6) {
                    LiveBadge(on: !tv.loading && !tv.failed)
                    Text(verbatim: c.cat.title).font(.caption).foregroundStyle(c.cat.color)
                }
            }
            TVLogo(channel: c, width: 52, height: 40)
            Button {
                TVChannels.toggle(c.id); favs = TVChannels.favorites
            } label: {
                Image(systemName: fav ? "star.fill" : "star").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.gold).frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    /// تقليب القنوات: السابقة/التالية، وشريط قنوات القسم نفسه
    private var zapper: some View {
        let list = TVChannels.list(tv.channel.cat)
        let i = list.firstIndex { $0.id == tv.channel.id } ?? 0
        return VStack(spacing: 14) {
            HStack(spacing: 12) {
                zapButton("القناة السابقة", "chevron.right") { if !list.isEmpty { tv.switchTo(list[(i - 1 + list.count) % list.count]) } }
                zapButton("القناة التالية", "chevron.left") { if !list.isEmpty { tv.switchTo(list[(i + 1) % list.count]) } }
            }
            .padding(.horizontal, 16)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(list) { c in
                            Button { tv.switchTo(c) } label: {
                                VStack(spacing: 5) {
                                    TVLogo(channel: c, width: 92, height: 56)
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(c.id == tv.channel.id ? Theme.gold : .clear, lineWidth: 2))
                                    Text(verbatim: c.name).font(.caption2.weight(.semibold))
                                        .foregroundStyle(c.id == tv.channel.id ? Theme.gold : .white.opacity(0.85))
                                        .lineLimit(1).frame(width: 92)
                                }
                            }
                            .buttonStyle(.plain)
                            .id(c.id)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onAppear { proxy.scrollTo(tv.channel.id, anchor: .center) }
                .onChange(of: tv.channel.id) { _, id in withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) } }
            }
            Text(verbatim: L("قنوات ") + tv.channel.cat.title)
                .font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.top, 16)
    }

    private func zapButton(_ title: String, _ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Label(L(title), systemImage: icon)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(Capsule().fill(Color.white.opacity(0.10)))
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - شعار القناة

struct TVLogo: View {
    let channel: TVChannel
    var width: CGFloat = 120
    var height: CGFloat = 72
    var body: some View {
        let r: CGFloat = min(width, height) * 0.22
        let cached = LogoCache.image(channel.logo)
        ZStack {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(cached.map { LogoCache.tile(for: channel.logo, image: $0) } ?? Color.white)
            if let img = cached {
                Image(uiImage: img).resizable().scaledToFit().padding(height * 0.14)
            } else if let u = URL(string: channel.logo), !channel.logo.isEmpty {
                AsyncImage(url: u) { ph in
                    if let img = ph.image {
                        img.resizable().scaledToFit().padding(height * 0.14)
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [channel.cat.color.opacity(0.85), channel.cat.color.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(verbatim: channel.name).font(Theme.title(height * 0.2)).foregroundStyle(.white)
                .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center).padding(6)
        }
    }
}

// MARK: - أقسام تبويب القنوات

struct TVSections: View {
    @State private var favs = TVChannels.favorites
    @State private var filter: TVCat? = nil
    @State private var adding = false
    @State private var editing: TVChannel?
    @State private var managing = false
    /// يتغيّر عند إضافة أو حذف قناة (لإعادة رسم الأقسام)
    @State private var rev = 0

    var body: some View {
        let _ = rev
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(title: "الكل", on: filter == nil) { withAnimation(.snappy) { filter = nil } }
                    ForEach(TVCat.allCases, id: \.self) { c in
                        Chip(title: c.title, icon: c.icon, on: filter == c) { withAnimation(.snappy) { filter = c } }
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 2)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

        if filter == nil && !favs.isEmpty {
            Section {
                carousel(TVChannels.favChannels)
            } header: {
                Label("قنواتي", systemImage: "star.fill")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }

        if let f = filter {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 14) {
                    ForEach(TVChannels.list(f)) { c in card(c, width: 104, height: 64) }
                }
                .padding(.vertical, 6)
            } header: {
                Label(f.title, systemImage: f.icon)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        } else {
            ForEach(TVCat.allCases, id: \.self) { c in
                Section {
                    carousel(TVChannels.list(c))
                } header: {
                    HStack {
                        Label(c.title, systemImage: c.icon).foregroundStyle(c.color)
                        Spacer()
                        Button { withAnimation(.snappy) { filter = c } } label: {
                            Text("عرض الكل").font(.caption.weight(.semibold)).foregroundStyle(Theme.gold)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
        }

        Section {
            Button { adding = true } label: {
                TileRow(title: "إضافة قناة برابط", icon: "link.badge.plus", color: .teal,
                        subtitle: "رابط m3u8 مباشر، أو قائمة M3U كاملة")
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $adding, onDismiss: { rev += 1 }) { AddTVSheet() }
            .sheet(item: $editing, onDismiss: { rev += 1 }) { c in AddTVSheet(editing: c) }
            let n = TVChannels.custom.count
            if n > 0 {
                Button { managing = true } label: {
                    TileRow(title: "القنوات المضافة", icon: "slider.horizontal.3", color: .orange,
                            subtitle: LF("%@ قناة — حذف قناة أو قائمة كاملة", ar(n)))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $managing, onDismiss: { favs = TVChannels.favorites; rev += 1 }) { CustomChannelsView() }
            }
        } footer: {
            Text("القنوات من دليل iptv-org المفتوح، وتُبث من مواقعها الرسمية. قد تتوقف بعض القنوات مؤقتًا، وتتحدّث روابطها تلقائيًا كل يوم. اضغط مطوّلًا على القناة لإضافتها إلى «قنواتي».")
        }
    }

    private func carousel(_ list: [TVChannel]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(list) { c in card(c, width: 128, height: 76) }
            }
            .padding(.horizontal, 4).padding(.vertical, 4)
        }
    }

    private func card(_ c: TVChannel, width: CGFloat, height: CGFloat) -> some View {
        let fav = favs.contains(c.id)
        return Button { TVRouter.shared.open = c } label: {
            VStack(spacing: 6) {
                TVLogo(channel: c, width: width, height: height)
                    .overlay(alignment: .topTrailing) {
                        if fav {
                            Image(systemName: "star.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.gold)
                                .padding(5).background(Circle().fill(Color.black.opacity(0.55))).padding(4)
                        }
                    }
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                Text(verbatim: c.name).font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: width)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { TVRouter.shared.open = c } label: { Label("مشاهدة", systemImage: "play.fill") }
            Button {
                TVChannels.toggle(c.id); favs = TVChannels.favorites
            } label: {
                Label(fav ? "إزالة من قنواتي" : "إضافة إلى قنواتي", systemImage: fav ? "star.slash" : "star")
            }
            if TVChannels.isCustom(c.id) {
                Button { editing = c } label: { Label("تعديل القناة", systemImage: "pencil") }
                Button(role: .destructive) {
                    TVChannels.removeCustom(c.id); favs = TVChannels.favorites; rev += 1
                } label: { Label("حذف القناة", systemImage: "trash") }
            }
        }
    }
}

