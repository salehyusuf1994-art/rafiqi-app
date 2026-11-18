import SwiftUI
import AVKit
import QuickLook
import MediaPlayer

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
        let vc = VideoController(playlist: playlist, start: playlist.firstIndex(of: url) ?? 0)
        // فيديو جديد: يوقف الصوت والقنوات، ويغلق أي فيديو سابق ولو كان في النافذة العائمة
        PlaybackGate.claim(.video, video: vc)
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

final class VideoController: AVPlayerViewController, AVPlayerViewControllerDelegate {
    /// كل مشغّلات الفيديو المفتوحة (ومنها ما في النافذة العائمة)، والذي يعمل الآن
    private static let players = NSHashTable<VideoController>.weakObjects()
    static weak var active: VideoController?
    /// مشغّل في النافذة العائمة يبقى حيًّا حتى تُغلق
    private static var floating: VideoController?
    private var inPiP = false
    private var statusObs: NSKeyValueObservation?

    /// يوقف بقية الفيديوهات؛ «close» يغلقها نهائيًا (ومعها نافذتها العائمة) عند بدء فيديو أو قناة أخرى
    static func stopOthers(except keep: VideoController?, close: Bool) {
        for vc in players.allObjects where vc !== keep {
            vc.player?.pause()
            if close { vc.shutDown() }
        }
    }

    private func shutDown() {
        statusObs = nil
        if let timeObs, let p = player { p.removeTimeObserver(timeObs); self.timeObs = nil }
        if let endObs { NotificationCenter.default.removeObserver(endObs); self.endObs = nil }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil   // يُغلق النافذة العائمة إن كانت مفتوحة
        if Self.active === self { Self.active = nil }
        if Self.floating === self { Self.floating = nil }
        Self.players.remove(self)
        clearNowPlaying()
        if presentingViewController != nil && !isBeingDismissed { dismiss(animated: false) }
    }

    // ── أزرار شاشة القفل والسماعات أثناء الفيديو ──
    func remotePlay() { player?.play() }
    func remotePause() { player?.pause() }
    func remoteToggle() { if let p = player { p.rate > 0 ? p.pause() : p.play() } }
    func remoteSeek(by s: Double) { remoteSeek(to: max(0, (player?.currentTime().seconds ?? 0) + s)) }
    func remoteSeek(to t: Double) {
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600)) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateNowPlaying() } }
        }
    }
    func remoteStep(_ d: Int) { step(d, manual: true) }

    // ── النافذة العائمة ──
    private var playingAtPiP = false
    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        inPiP = true
        Self.floating = self
        playingAtPiP = (player?.rate ?? 0) > 0 || player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
    }
    /// بعد الانتقال للنافذة العائمة يكمل الفيديو (إغلاق شاشة المشغّل كان يوقفه)
    func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        guard playingAtPiP else { return }
        player?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated { if let self, self.inPiP, (self.player?.rate ?? 0) == 0 { self.player?.play() } }
        }
    }
    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        inPiP = false
        // أُغلقت النافذة العائمة دون الرجوع للمشغّل: ينتهي الفيديو
        if view.window == nil && presentingViewController == nil {
            player?.pause()
            if Self.active === self { Self.active = nil }
            clearNowPlaying()
        }
        if Self.floating === self { Self.floating = nil }
    }
    /// «الرجوع إلى ملء الشاشة» من النافذة العائمة
    func playerViewController(_ playerViewController: AVPlayerViewController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        if view.window != nil || presentingViewController != nil { completionHandler(true); return }
        guard let top = FileOpener.top() else { completionHandler(false); return }
        modalPresentationStyle = .fullScreen
        top.present(self, animated: true) { completionHandler(true) }
    }

    private let playlist: [URL]
    private var index: Int
    private let label = UILabel()
    private var cues: [(Double, Double, String)] = []
    private var timeObs: Any?
    private var endObs: NSObjectProtocol?
    private let flash = UILabel()

    /// ترتيب التشغيل (عشوائي أو بالترتيب) ومكان الفيديو الحالي فيه
    private var order: [Int] = []
    private var shuffle = FilePrefs.videoShuffle
    private var repeatMode = FilePrefs.videoRepeat

    init(playlist: [URL], start: Int) {
        self.playlist = playlist
        index = start
        super.init(nibName: nil, bundle: nil)
        rebuildOrder()
    }

    private func rebuildOrder() {
        let all = Array(playlist.indices)
        if shuffle {
            order = [index] + all.filter { $0 != index }.shuffled()
        } else {
            order = all
        }
    }

    /// التالي/السابق بحسب الترتيب؛ «manual» من الأزرار (يلف للبداية دائمًا)، وإلا عند انتهاء الفيديو
    private func step(_ d: Int, manual: Bool) {
        guard !playlist.isEmpty else { return }
        // السابق بعد أكثر من ٣ ثوانٍ يرجع لبداية الفيديو نفسه
        if d < 0, manual, (player?.currentTime().seconds ?? 0) > 3 {
            player?.seek(to: .zero); player?.play(); return
        }
        let pos = order.firstIndex(of: index) ?? 0
        var next = pos + d
        if next >= order.count || next < 0 {
            guard manual || repeatMode == 1 else { return }
            if shuffle && next >= order.count {
                order = Array(playlist.indices).shuffled()
                if order.count > 1 && order.first == index { order.swapAt(0, 1) }
            }
            next = (next + order.count) % order.count
        }
        load(order[next])
    }

    private var hasNeighbours: Bool { playlist.count > 1 }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        allowsPictureInPicturePlayback = true
        canStartPictureInPictureAutomaticallyFromInline = true
        delegate = self
        Self.players.add(self)
        // شاشة القفل نديرها بأنفسنا: العنوان والصورة وأزرار التالي/السابق
        updatesNowPlayingInfoCenter = false

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
        setupSleepButton()
        setupBar()
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
        // بدأ التشغيل (أول مرة أو بعد إيقاف مؤقت): يتوقف أي صوت أو قناة أو فيديو آخر
        statusObs = p.observe(\.timeControlStatus, options: [.new]) { [weak self] pl, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self, self.player === pl else { return }
                // متوقف: الأزرار تبقى ظاهرة، وشاشة القفل تعرف أنه متوقف
                guard pl.timeControlStatus == .playing else {
                    if pl.timeControlStatus == .paused { self.showBar(); self.updateNowPlaying() }
                    return
                }
                VideoController.active = self
                if PlaybackGate.owner != .video || AudioPlayer.shared.state.playing || TVPlayback.current?.isPlaying == true {
                    PlaybackGate.claim(.video, video: self)
                } else {
                    VideoController.stopOthers(except: self, close: false)
                }
                self.updateNowPlaying()
            } }
        }
        cues = Self.subtitles(for: url)
        label.text = nil
        timeObs = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self else { return }
            let s = t.seconds
            self.label.text = self.cues.first { s >= $0.0 && s <= $0.1 }?.2
        }
        if let endObs { NotificationCenter.default.removeObserver(endObs) }
        endObs = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.repeatMode == 2 { self.player?.seek(to: .zero); self.player?.play(); return }
            guard FilePrefs.autoNext else { self.showBar(); return }
            self.step(1, manual: false)
        }
        p.play()
        refreshBar()
        nowPlayingArt = nil
        updateNowPlaying()
        loadArtwork(url)
    }

    // ── شاشة القفل: العنوان والصورة والتالي/السابق (بدل ±١٠ ثوانٍ) ──
    private var nowPlayingArt: MPMediaItemArtwork?

    func updateNowPlaying() {
        guard PlaybackGate.owner == .video, VideoController.active === self || VideoController.active == nil, let p = player else { return }
        let url = playlist[index]
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: url.deletingPathExtension().lastPathComponent,
            MPMediaItemPropertyArtist: hasNeighbours ? LF("%@ من %@", ar((order.firstIndex(of: index) ?? 0) + 1), ar(playlist.count)) : L("رفيقي"),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, p.currentTime().seconds.isFinite ? p.currentTime().seconds : 0),
            MPNowPlayingInfoPropertyPlaybackRate: Double(p.rate),
        ]
        if let d = p.currentItem?.duration.seconds, d.isFinite, d > 0 { info[MPMediaItemPropertyPlaybackDuration] = d }
        if let nowPlayingArt { info[MPMediaItemPropertyArtwork] = nowPlayingArt }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        let rc = MPRemoteCommandCenter.shared()
        rc.skipForwardCommand.isEnabled = false
        rc.skipBackwardCommand.isEnabled = false
        rc.nextTrackCommand.isEnabled = true
        rc.previousTrackCommand.isEnabled = true
        rc.changePlaybackPositionCommand.isEnabled = true
    }

    /// أُغلق الفيديو: نمسح بطاقته من شاشة القفل (إن لم يبدأ شيء آخر بعده)
    private func clearNowPlaying() {
        guard PlaybackGate.owner == .video, VideoController.active == nil || VideoController.active === self else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func loadArtwork(_ url: URL) {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 600, height: 600)
        gen.generateCGImageAsynchronously(for: CMTime(seconds: 3, preferredTimescale: 600)) { [weak self] cg, _, _ in
            guard let cg else { return }
            let img = UIImage(cgImage: cg)
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self, self.playlist.indices.contains(self.index), self.playlist[self.index] == url else { return }
                self.nowPlayingArt = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                self.updateNowPlaying()
            } }
        }
    }

    // ── أزرار التالي والسابق والعشوائي والتكرار والتشغيل التلقائي ──
    private let bar = UIVisualEffectView()
    private let barStack = UIStackView()
    private let prevB = UIButton(type: .system), nextB = UIButton(type: .system)
    private let shuffleB = UIButton(type: .system), repeatB = UIButton(type: .system), autoB = UIButton(type: .system)
    private var hideWork: DispatchWorkItem?
    /// الضغطة الواحدة تعمل مع ضغطات المشغّل نفسه (لا تمنعها)
    private let tapDelegate = SimultaneousTaps()

    private func setupBar() {
        if #available(iOS 26.0, *) {
            bar.effect = UIGlassEffect()
        } else {
            bar.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        }
        bar.layer.cornerRadius = 24
        bar.clipsToBounds = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        barStack.axis = .horizontal
        barStack.spacing = 2
        barStack.translatesAutoresizingMaskIntoConstraints = false
        barStack.semanticContentAttribute = .forceLeftToRight
        let items: [(UIButton, String, Selector)] = [
            (shuffleB, "تشغيل عشوائي", #selector(tapShuffle)),
            (prevB, "الفيديو السابق", #selector(tapPrev)),
            (nextB, "الفيديو التالي", #selector(tapNext)),
            (repeatB, "التكرار", #selector(tapRepeat)),
            (autoB, "تشغيل التالي تلقائيًا", #selector(tapAuto)),
        ]
        for (b, title, sel) in items {
            b.accessibilityLabel = L(title)
            b.tintColor = .white
            b.addTarget(self, action: sel, for: .touchUpInside)
            b.addTarget(self, action: #selector(keepBar), for: .touchDown)
            b.widthAnchor.constraint(equalToConstant: 44).isActive = true
            b.heightAnchor.constraint(equalToConstant: 44).isActive = true
            barStack.addArrangedSubview(b)
        }
        bar.contentView.addSubview(barStack)
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            barStack.leadingAnchor.constraint(equalTo: bar.contentView.leadingAnchor, constant: 4),
            barStack.trailingAnchor.constraint(equalTo: bar.contentView.trailingAnchor, constant: -4),
            barStack.topAnchor.constraint(equalTo: bar.contentView.topAnchor, constant: 2),
            barStack.bottomAnchor.constraint(equalTo: bar.contentView.bottomAnchor, constant: -2),
            bar.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor, constant: -16),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -56),
        ])
        // ضغطة واحدة على الفيديو تُظهر الأزرار أو تخفيها مع أزرار المشغّل
        let single = UITapGestureRecognizer(target: self, action: #selector(singleTap))
        single.cancelsTouchesInView = false
        single.delegate = tapDelegate
        view.addGestureRecognizer(single)
        refreshBar()
        showBar()
    }

    private func symbol(_ name: String, on: Bool = false) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: on ? .bold : .semibold))
    }

    private func refreshBar() {
        guard bar.superview != nil else { return }
        let gold = UIColor(Theme.gold)
        prevB.setImage(symbol("backward.end.fill"), for: .normal)
        nextB.setImage(symbol("forward.end.fill"), for: .normal)
        prevB.isEnabled = hasNeighbours; nextB.isEnabled = hasNeighbours
        prevB.alpha = hasNeighbours ? 1 : 0.35; nextB.alpha = hasNeighbours ? 1 : 0.35
        shuffleB.setImage(symbol("shuffle", on: shuffle), for: .normal)
        shuffleB.tintColor = shuffle ? gold : .white.withAlphaComponent(0.75)
        shuffleB.isEnabled = hasNeighbours; shuffleB.alpha = hasNeighbours ? 1 : 0.35
        repeatB.setImage(symbol(repeatMode == 2 ? "repeat.1" : "repeat", on: repeatMode > 0), for: .normal)
        repeatB.tintColor = repeatMode > 0 ? gold : .white.withAlphaComponent(0.75)
        let auto = FilePrefs.autoNext
        autoB.setImage(symbol("text.line.first.and.arrowtriangle.forward", on: auto), for: .normal)
        autoB.tintColor = auto ? gold : .white.withAlphaComponent(0.75)
    }

    @objc private func tapPrev() { step(-1, manual: true); keepBar() }
    @objc private func tapNext() { step(1, manual: true); keepBar() }
    @objc private func tapShuffle() {
        shuffle.toggle(); FilePrefs.videoShuffle = shuffle
        rebuildOrder(); refreshBar(); updateNowPlaying()
        toast(shuffle ? "التشغيل العشوائي: يعمل" : "التشغيل العشوائي: متوقف")
    }
    @objc private func tapRepeat() {
        repeatMode = (repeatMode + 1) % 3; FilePrefs.videoRepeat = repeatMode
        refreshBar()
        toast(["بلا تكرار", "تكرار القائمة", "تكرار الفيديو"][repeatMode])
    }
    @objc private func tapAuto() {
        FilePrefs.autoNext.toggle(); refreshBar()
        toast(FilePrefs.autoNext ? "تشغيل التالي تلقائيًا: يعمل" : "تشغيل التالي تلقائيًا: متوقف")
    }

    private func toast(_ s: String) {
        flash.text = L(s)
        flash.frame.size.width = min(view.bounds.width - 40, 290)
        flash.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY - 90)
        UIView.animate(withDuration: 0.15, animations: { self.flash.alpha = 1 }) { _ in UIView.animate(withDuration: 0.4, delay: 1.1) { self.flash.alpha = 0 } }
        keepBar()
    }

    @objc private func singleTap() {
        guard !locked else { return }
        bar.alpha > 0.5 ? hideBar() : showBar()
    }
    @objc private func keepBar() { showBar() }

    private func showBar() {
        guard !locked else { return }
        UIView.animate(withDuration: 0.2) { self.bar.alpha = 1 }
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                // يبقى ظاهرًا ما دام الفيديو متوقفًا
                guard let self, (self.player?.rate ?? 0) > 0 else { return }
                self.hideBar()
            }
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: w)
    }
    private func hideBar() {
        hideWork?.cancel()
        UIView.animate(withDuration: 0.25) { self.bar.alpha = 0 }
    }

    private let blocker = UIView()
    private let lockButton = UIButton(type: .system)
    private let sleepButton = UIButton(type: .system)

    /// مؤقّت النوم: يوقف الفيديو بعد مدة
    private func setupSleepButton() {
        sleepButton.tintColor = .white
        sleepButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        sleepButton.layer.cornerRadius = 22
        sleepButton.translatesAutoresizingMaskIntoConstraints = false
        sleepButton.accessibilityLabel = L("مؤقّت النوم")
        sleepButton.showsMenuAsPrimaryAction = true
        sleepButton.menu = UIMenu(title: L("مؤقّت النوم"), children: [UIDeferredMenuElement.uncached { [weak self] done in MainActor.assumeIsolated {
            let a = AudioPlayer.shared
            var items: [UIMenuElement] = []
            if a.sleepAt != nil {
                items.append(UIAction(title: L("إلغاء المؤقّت"), image: UIImage(systemName: "xmark"), attributes: .destructive) { _ in
                    MainActor.assumeIsolated { a.cancelSleep(); self?.refreshSleepIcon() } })
            }
            for m in [15, 30, 45, 60, 90] {
                items.append(UIAction(title: LF("بعد %@ دقيقة", ar(m))) { _ in MainActor.assumeIsolated { a.sleep(minutes: m); self?.refreshSleepIcon() } })
            }
            done(items)
        } }])
        view.addSubview(sleepButton)
        NSLayoutConstraint.activate([
            sleepButton.widthAnchor.constraint(equalToConstant: 44), sleepButton.heightAnchor.constraint(equalToConstant: 44),
            sleepButton.centerXAnchor.constraint(equalTo: lockButton.centerXAnchor),
            sleepButton.bottomAnchor.constraint(equalTo: lockButton.topAnchor, constant: -14),
        ])
        refreshSleepIcon()
    }

    private func refreshSleepIcon() {
        let on = AudioPlayer.shared.sleepAt != nil
        sleepButton.setImage(UIImage(systemName: on ? "moon.zzz.fill" : "moon.zzz", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        sleepButton.tintColor = on ? UIColor(Theme.gold) : .white
    }
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
        sleepButton.isHidden = on
        bar.isHidden = on
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
        p.seek(to: CMTime(seconds: t, preferredTimescale: 600)) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateNowPlaying() } }
        }
        flash.frame.size.width = 110
        flash.text = (forward ? "+" : "−") + "\(FilePrefs.skip)"
        flash.center = CGPoint(x: forward ? view.bounds.width * 0.78 : view.bounds.width * 0.22, y: view.bounds.midY)
        UIView.animate(withDuration: 0.15, animations: { self.flash.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.4, delay: 0.4) { self.flash.alpha = 0 }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // الإغلاق يوقف الفيديو، إلا إذا انتقل إلى النافذة العائمة
        if !inPiP && Self.floating !== self && (isBeingDismissed || presentingViewController == nil) {
            player?.pause()
            if Self.active === self { Self.active = nil }
            clearNowPlaying()
        }
    }

    /// ترجمة بنفس اسم الفيديو (.srt أو .vtt) في المجلد نفسه
    static func subtitles(for url: URL) -> [(Double, Double, String)] {
        let base = url.deletingPathExtension()
        for ext in ["srt", "vtt", "ar.srt", "en.srt"] {
            let u = base.appendingPathExtension(ext)
            if let d = try? Data(contentsOf: u) {
                let text = String(data: d, encoding: .utf8) ?? String(data: d, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsArabic.rawValue)))) ?? ""
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
                })
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

/// يسمح لضغطتنا بالعمل مع إيماءات المشغّل الأصلية
final class SimultaneousTaps: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
