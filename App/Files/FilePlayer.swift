import SwiftUI
import AVKit
import QuickLook

// MARK: - فتح الملفات: الصوت في مشغّل رفيقي، والفيديو بملء الشاشة، والباقي بالمعاينة

@MainActor
enum FileOpener {
    static func top() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var vc = (scene?.keyWindow ?? scene?.windows.first)?.rootViewController
        while let p = vc?.presentedViewController, !p.isBeingDismissed { vc = p }
        return vc
    }

    /// يفتح الملف بحسب نوعه؛ «siblings» لتشغيل الملفات المجاورة بالتتابع
    static func open(_ url: URL, siblings: [URL] = []) {
        switch FileKind.of(url, isDir: false) {
        case .audio:
            let list = siblings.filter { FileKind.of($0, isDir: false) == .audio }
            let queue = list.isEmpty ? [url] : list
            AudioPlayer.shared.playFiles(queue, start: queue.firstIndex(of: url) ?? 0)
        case .video:
            let list = siblings.filter { FileKind.of($0, isDir: false) == .video }
            presentVideo(url, playlist: list.isEmpty ? [url] : list)
        default:
            preview(url, siblings: siblings.filter { [.image, .document, .other, .archive].contains(FileKind.of($0, isDir: false)) })
        }
    }

    static func presentVideo(_ url: URL, playlist: [URL]) {
        AudioPlayer.shared.pause()
        let vc = VideoController(playlist: playlist, start: playlist.firstIndex(of: url) ?? 0)
        vc.modalPresentationStyle = .fullScreen
        top()?.present(vc, animated: true)
    }

    static func preview(_ url: URL, siblings: [URL]) {
        let items = siblings.isEmpty ? [url] : siblings
        let ql = QLPreviewController()
        let ds = PreviewSource(items: items)
        ql.dataSource = ds
        ql.delegate = ds
        ql.currentPreviewItemIndex = items.firstIndex(of: url) ?? 0
        objc_setAssociatedObject(ql, &PreviewSource.key, ds, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        top()?.present(ql, animated: true)
    }

    /// «فتح باستخدام» تطبيق آخر
    static func openIn(_ url: URL) {
        guard let top = top() else { return }
        let dic = UIDocumentInteractionController(url: url)
        objc_setAssociatedObject(top, &PreviewSource.dicKey, dic, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if !dic.presentOpenInMenu(from: CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 40, width: 1, height: 1), in: top.view, animated: true) {
            share([url])
        }
    }

    static func share(_ urls: [URL]) {
        guard let top = top(), !urls.isEmpty else { return }
        let vc = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
    }
}

final class PreviewSource: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    static var key = 0
    static var dicKey = 0
    let items: [URL]
    init(items: [URL]) { self.items = items }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { items.count }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { items[index] as NSURL }
    /// التعليق والكتابة والتوقيع والقص على الصور وملفات PDF يُحفظ في الملف نفسه
    func previewController(_ controller: QLPreviewController, editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode { .updateContents }
    func previewController(_ controller: QLPreviewController, didUpdateContentsOf previewItem: QLPreviewItem) {
        Task { @MainActor in FileStore.shared.touch() }
    }
}

// MARK: - مشغّل الفيديو: ضغطتان للتقديم/الترجيع، وترجمة SRT، والصورة داخل الصورة، والتالي تلقائيًا

final class VideoController: AVPlayerViewController {
    private let playlist: [URL]
    private var index: Int
    private let label = UILabel()
    private var cues: [(Double, Double, String)] = []
    private var timeObs: Any?
    private var endObs: NSObjectProtocol?
    private let flash = UILabel()

    init(playlist: [URL], start: Int) {
        self.playlist = playlist
        index = start
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        allowsPictureInPicturePlayback = true
        canStartPictureInPictureAutomaticallyFromInline = true
        updatesNowPlayingInfoCenter = true

        // الترجمة
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white
        label.font = UIFont(name: "Tajawal-Bold", size: 19) ?? .boldSystemFont(ofSize: 19)
        label.shadowColor = .black
        label.shadowOffset = CGSize(width: 0, height: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        if let o = contentOverlayView {
            o.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: o.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(equalTo: o.trailingAnchor, constant: -24),
                label.bottomAnchor.constraint(equalTo: o.safeAreaLayoutGuide.bottomAnchor, constant: -48),
            ])
            flash.font = .systemFont(ofSize: 20, weight: .bold)
            flash.textColor = .white
            flash.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            flash.layer.cornerRadius = 30
            flash.clipsToBounds = true
            flash.textAlignment = .center
            flash.alpha = 0
            flash.frame = CGRect(x: 0, y: 0, width: 110, height: 60)
            o.addSubview(flash)
        }
        // قفل الشاشة (للأطفال): يمنع اللمس أثناء المشاهدة، ويُفتح بضغطة مطوّلة على القفل
        blocker.backgroundColor = UIColor.black.withAlphaComponent(0.001)
        blocker.isHidden = true
        blocker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blocker)
        lockButton.setImage(UIImage(systemName: "lock.open", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        lockButton.tintColor = .white
        lockButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        lockButton.layer.cornerRadius = 22
        lockButton.translatesAutoresizingMaskIntoConstraints = false
        lockButton.addTarget(self, action: #selector(lockTap), for: .touchUpInside)
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(unlockHold(_:)))
        lp.minimumPressDuration = 1.2
        lockButton.addGestureRecognizer(lp)
        view.addSubview(lockButton)
        NSLayoutConstraint.activate([
            blocker.topAnchor.constraint(equalTo: view.topAnchor), blocker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            blocker.leadingAnchor.constraint(equalTo: view.leadingAnchor), blocker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lockButton.widthAnchor.constraint(equalToConstant: 44), lockButton.heightAnchor.constraint(equalToConstant: 44),
            lockButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            lockButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        // ضغطتان: يمين/يسار الشاشة
        let dbl = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        dbl.cancelsTouchesInView = false
        view.addGestureRecognizer(dbl)
        load(index)
    }

    private func load(_ i: Int) {
        guard playlist.indices.contains(i) else { return }
        index = i
        let url = playlist[i]
        if let timeObs, let old = player { old.removeTimeObserver(timeObs); self.timeObs = nil }
        let p = AVPlayer(url: url)
        player = p
        cues = Self.subtitles(for: url)
        label.text = nil
        timeObs = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self else { return }
            let s = t.seconds
            self.label.text = self.cues.first { s >= $0.0 && s <= $0.1 }?.2
        }
        if let endObs { NotificationCenter.default.removeObserver(endObs) }
        endObs = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in
            guard let self, FilePrefs.autoNext, self.index + 1 < self.playlist.count else { return }
            self.load(self.index + 1)
        }
        p.play()
    }

    private let blocker = UIView()
    private let lockButton = UIButton(type: .system)
    private var locked = false

    @objc private func lockTap() {
        guard !locked else {
            flash.text = L("اضغط مطوّلًا لفتح القفل")
            flash.frame.size.width = 230
            flash.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            UIView.animate(withDuration: 0.15, animations: { self.flash.alpha = 1 }) { _ in UIView.animate(withDuration: 0.4, delay: 1.2) { self.flash.alpha = 0 } }
            return
        }
        setLocked(true)
    }

    @objc private func unlockHold(_ g: UILongPressGestureRecognizer) {
        if g.state == .began, locked { setLocked(false) }
    }

    private func setLocked(_ on: Bool) {
        locked = on
        showsPlaybackControls = !on
        blocker.isHidden = !on
        view.bringSubviewToFront(blocker)
        view.bringSubviewToFront(lockButton)
        lockButton.setImage(UIImage(systemName: on ? "lock.fill" : "lock.open", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        lockButton.tintColor = on ? UIColor(Theme.gold) : .white
    }

    @objc private func doubleTap(_ g: UITapGestureRecognizer) {
        guard !locked, let p = player else { return }
        let x = g.location(in: view).x
        let forward = x > view.bounds.midX
        let step = Double(FilePrefs.skip) * (forward ? 1 : -1)
        let t = max(0, p.currentTime().seconds + step)
        p.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        flash.frame.size.width = 110
        flash.text = (forward ? "+" : "−") + "\(FilePrefs.skip)"
        flash.center = CGPoint(x: forward ? view.bounds.width * 0.78 : view.bounds.width * 0.22, y: view.bounds.midY)
        UIView.animate(withDuration: 0.15, animations: { self.flash.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.4, delay: 0.4) { self.flash.alpha = 0 }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { player?.pause() }
    }

    /// ترجمة بنفس اسم الفيديو (.srt أو .vtt) في المجلد نفسه
    static func subtitles(for url: URL) -> [(Double, Double, String)] {
        let base = url.deletingPathExtension()
        for ext in ["srt", "vtt", "ar.srt", "en.srt"] {
            let u = base.appendingPathExtension(ext)
            if let d = try? Data(contentsOf: u) {
                let text = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .windowsCP1256) ?? ""
                return parseSRT(text)
            }
        }
        return []
    }

    static func parseSRT(_ text: String) -> [(Double, Double, String)] {
        func t(_ s: Substring) -> Double {
            let p = s.replacingOccurrences(of: ",", with: ".").split(separator: ":")
            guard p.count >= 2 else { return 0 }
            let nums = p.map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            return nums.count == 3 ? nums[0] * 3600 + nums[1] * 60 + nums[2] : nums[0] * 60 + nums[1]
        }
        var out: [(Double, Double, String)] = []
        let blocks = text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n\n")
        for b in blocks {
            let lines = b.split(separator: "\n", omittingEmptySubsequences: true)
            guard let i = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[i].components(separatedBy: "-->")
            guard parts.count == 2 else { continue }
            let a = t(Substring(parts[0])), z = t(Substring(parts[1].split(separator: " ").first ?? ""))
            let body = lines[(i + 1)...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            out.append((a, z, body))
        }
        return out
    }
}

// MARK: - المشغّل المصغّر لملفاتي

struct FilesMiniPlayer: View {
    @ObservedObject private var p = AudioPlayer.shared
    @State private var showFull = false
    @State private var pos: Double = 0
    @State private var scrubbing = false
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        if p.currentFile != nil {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Button { showFull = true } label: {
                        Image(systemName: "chevron.up").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 30, height: 30).background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    Text(verbatim: p.state.title).font(Theme.f(.subheadline, .bold)).foregroundStyle(.white).lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .onTapGesture { showFull = true }
                    Button { p.stopFiles() } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                            .frame(width: 30, height: 30).background(Circle().fill(Color.white))
                    }
                }
                HStack(spacing: 8) {
                    Text(verbatim: durationText(pos)).font(Theme.font(12, .medium).monospacedDigit()).foregroundStyle(Theme.sub)
                    Slider(value: Binding(get: { pos }, set: { pos = $0 }), in: 0...max(1, p.state.duration), onEditingChanged: { e in
                        scrubbing = e
                        if !e { p.seek(to: pos) }
                    })
                    .tint(Theme.gold)
                    Text(verbatim: durationText(p.state.duration)).font(Theme.font(12, .medium).monospacedDigit()).foregroundStyle(Theme.sub)
                }
                .environment(\.layoutDirection, .leftToRight)
                PlayerControls(compact: true)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
            .environment(\.colorScheme, .dark)
            .onReceive(tick) { _ in if !scrubbing { pos = p.position() } }
            .sheet(isPresented: $showFull) { FilesFullPlayer() }
        }
    }
}

/// أزرار التحكم المشتركة
struct PlayerControls: View {
    @ObservedObject private var p = AudioPlayer.shared
    var compact = false
    var body: some View {
        let s = Double(FilePrefs.skip)
        HStack {
            Button { cycleRepeat() } label: {
                Image(systemName: p.state.repeatOne ? "repeat.1" : "repeat")
                    .foregroundStyle(p.state.repeatOne || p.state.repeatAll ? Theme.gold : .white.opacity(0.6))
            }
            Spacer()
            Button { p.seek(by: -s) } label: { Image(systemName: "gobackward.\(FilePrefs.skip)") }
            Spacer()
            Button { p.previous() } label: { Image(systemName: "backward.fill") }
            Spacer()
            Button { p.toggle() } label: {
                Image(systemName: p.state.playing ? "pause.fill" : "play.fill").font(.system(size: compact ? 26 : 34))
            }
            Spacer()
            Button { p.next() } label: { Image(systemName: "forward.fill") }
            Spacer()
            Button { p.seek(by: s) } label: { Image(systemName: "goforward.\(FilePrefs.skip)") }
            Spacer()
            Button { Task { await p.handle("shuffle") } } label: {
                Image(systemName: "shuffle").foregroundStyle(p.state.shuffle ? Theme.gold : .white.opacity(0.6))
            }
        }
        .font(.system(size: compact ? 18 : 24, weight: .semibold))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func cycleRepeat() {
        // بلا تكرار ← تكرار القائمة ← تكرار المقطع
        var st = p.state
        if st.repeatOne { st.repeatOne = false; st.repeatAll = false }
        else if st.repeatAll { st.repeatAll = false; st.repeatOne = true }
        else { st.repeatAll = true }
        p.setRepeat(one: st.repeatOne, all: st.repeatAll)
    }
}

struct FilesFullPlayer: View {
    @ObservedObject private var p = AudioPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var pos: Double = 0
    @State private var scrubbing = false
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(Color.white.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 10)
            Spacer(minLength: 0)
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.gold.opacity(0.35), Theme.teal.opacity(0.25), Theme.bg], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "waveform").font(.system(size: 90, weight: .light)).foregroundStyle(Theme.gold)
            }
            .frame(width: 260, height: 260)
            VStack(spacing: 6) {
                Text(verbatim: p.state.title).font(Theme.f(.title3, .bold)).foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(2)
                Text(verbatim: p.state.subtitle).font(Theme.f(.subheadline)).foregroundStyle(Theme.sub)
                if p.fileQueue.count > 1 {
                    Text(LF("%@ من %@", ar(p.fileIndex + 1), ar(p.fileQueue.count))).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                }
            }
            .padding(.horizontal, 24)
            VStack(spacing: 4) {
                Slider(value: Binding(get: { pos }, set: { pos = $0 }), in: 0...max(1, p.state.duration), onEditingChanged: { e in
                    scrubbing = e
                    if !e { p.seek(to: pos) }
                }
                .tint(Theme.gold)
                HStack {
                    Text(verbatim: durationText(pos))
                    Spacer()
                    Text(verbatim: "-" + durationText(max(0, p.state.duration - pos)))
                }
                .font(Theme.font(12, .medium).monospacedDigit()).foregroundStyle(Theme.sub)
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, 24)
            PlayerControls().padding(.horizontal, 20)
            HStack(spacing: 14) {
                Menu {
                    ForEach(rates, id: \.self) { r in
                        Button { p.rate = r } label: {
                            if p.rate == r { Label(rateText(r), systemImage: "checkmark") } else { Text(verbatim: rateText(r)) }
                        }
                    }
                } label: {
                    Label(rateText(p.rate), systemImage: "speedometer").font(Theme.f(.subheadline, .medium))
                        .padding(.horizontal, 14).padding(.vertical, 9).background(Capsule().fill(Theme.card))
                }
                Menu {
                    ForEach([15, 30, 45, 60], id: \.self) { m in
                        Button(minutesText(m)) { p.sleep(minutes: m) }
                    }
                    Button(L("عند نهاية المقطع")) { p.sleepAtEndOfSurah() }
                    if p.sleepAt != nil || p.sleepAtEnd { Button(L("إلغاء المؤقّت"), role: .destructive) { p.cancelSleep() } }
                } label: {
                    Label(L("مؤقّت النوم"), systemImage: p.sleepAt != nil || p.sleepAtEnd ? "moon.zzz.fill" : "moon.zzz")
                        .font(Theme.f(.subheadline, .medium))
                        .padding(.horizontal, 14).padding(.vertical, 9).background(Capsule().fill(Theme.card))
                }
                AirPlayButton().frame(width: 40, height: 40)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .background(AppBackground())
        .onReceive(tick) { _ in if !scrubbing { pos = p.position() } }
        .presentationDragIndicator(.hidden)
    }

    private func rateText(_ r: Float) -> String {
        let s = r == Float(Int(r)) ? String(Int(r)) : String(format: "%g", r)
        return ar(s) + "×"
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Theme.gold)
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
