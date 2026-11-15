import Foundation
import AVFoundation
import MediaPlayer
import WidgetKit

// MARK: - مشغّل الصوتيات (داخل التطبيق): القرآن والإذاعات، والتحكم في Apple Music

@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()

    @Published private(set) var state = NowPlaying.current
    @Published var loading = false
    /// اسم البرنامج أو المقطع الذي تبثّه الإذاعة الآن (إن أرسلته)
    @Published private(set) var streamTitle: String? = nil
    /// الإذاعة الشغّالة
    @Published private(set) var station: Station? = nil
    /// مؤقّت النوم: يتوقف التشغيل في هذا الوقت
    @Published private(set) var sleepAt: Date? = nil
    /// مؤقّت النوم: يتوقف عند نهاية السورة الحالية
    @Published private(set) var sleepAtEnd = false
    private var sleepTask: Task<Void, Never>?
    private let meta = StreamMeta()
    private let player = AVPlayer()
    private var endObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var configured = false
    /// إعادة المحاولة عند تعثّر الإذاعة أو التلاوة (خوادم الإذاعات ترجع خطأ أحيانًا ثم تعمل)
    private var retries = 0
    private var currentURL: URL?

    private init() {
        state.playing = false   // بعد إعادة تشغيل التطبيق ما في شيء شغّال فعليًا
        save(reload: false)
    }

    /// يُستدعى عند بدء التطبيق: يربط أوامر الويدجت وشاشة القفل
    func configure() {
        guard !configured else { return }
        configured = true
        MediaBridge.handler = { action, source in await AudioPlayer.shared.handle(action, source: source) }
        player.automaticallyWaitsToMinimizeStalling = true
        let rc = MPRemoteCommandCenter.shared()
        // أثناء بث قناة تلفزيونية: أزرار شاشة القفل والسماعات تتحكم في القناة
        rc.playCommand.addTarget { _ in Task { @MainActor in if let tv = TVPlayback.current { tv.play() } else { AudioPlayer.shared.play() } }; return .success }
        rc.pauseCommand.addTarget { _ in Task { @MainActor in if let tv = TVPlayback.current { tv.pause() } else { AudioPlayer.shared.pause() } }; return .success }
        rc.togglePlayPauseCommand.addTarget { _ in Task { @MainActor in if let tv = TVPlayback.current { tv.toggle() } else { AudioPlayer.shared.toggle() } }; return .success }
        rc.nextTrackCommand.addTarget { _ in Task { @MainActor in if let tv = TVPlayback.current { tv.zap(1) } else { AudioPlayer.shared.next() } }; return .success }
        rc.previousTrackCommand.addTarget { _ in Task { @MainActor in if let tv = TVPlayback.current { tv.zap(-1) } else { AudioPlayer.shared.previous() } }; return .success }
        // التقديم والترجيع والسحب في شريط شاشة القفل (للتلاوة والملفات)
        rc.skipForwardCommand.preferredIntervals = [NSNumber(value: FilePrefs.skip)]
        rc.skipBackwardCommand.preferredIntervals = [NSNumber(value: FilePrefs.skip)]
        rc.skipForwardCommand.addTarget { _ in Task { @MainActor in AudioPlayer.shared.seek(by: Double(FilePrefs.skip)) }; return .success }
        rc.skipBackwardCommand.addTarget { _ in Task { @MainActor in AudioPlayer.shared.seek(by: -Double(FilePrefs.skip)) }; return .success }
        rc.changePlaybackPositionCommand.addTarget { e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in AudioPlayer.shared.seek(to: e.positionTime) }
            return .success
        }
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { p, _ in
            let waiting = p.timeControlStatus == .waitingToPlayAtSpecifiedRate
            Task { @MainActor in AudioPlayer.shared.loading = waiting }
        }
        // مكالمة أو منبّه (ومنه الأذان) يوقف الصوت: نحدّث الحالة حتى لا تبقى الويدجت على «يعمل»، ونكمل بعدها إن سمح النظام
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let opts = AVAudioSession.InterruptionOptions(rawValue: n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            Task { @MainActor in AudioPlayer.shared.interruption(began: type == .began, resume: opts.contains(.shouldResume)) }
        }
        // فصل السماعة: المشغّل يتوقف من نفسه
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { n in
            let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            guard reason == .oldDeviceUnavailable else { return }
            Task { @MainActor in
                let a = AudioPlayer.shared
                if a.state.source != .music && a.state.playing { a.pause() }
            }
        }
        NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: nil, queue: .main) { _ in
            Task { @MainActor in AudioPlayer.shared.refreshMusic() }
        }
        NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: nil, queue: .main) { _ in
            Task { @MainActor in AudioPlayer.shared.refreshMusic() }
        }
    }

    private var pausedByInterruption = false
    private func interruption(began: Bool, resume: Bool) {
        guard state.source != .music else { return }
        if began {
            guard state.playing else { return }
            pausedByInterruption = true
            state.position = currentTime()
            state.playing = false
            loading = false
            save()
        } else {
            let was = pausedByInterruption
            pausedByInterruption = false
            if was && resume { play() }
        }
    }

    // ── أوامر الويدجت ──
    func handle(_ action: String, source: String = "") async {
        configure()
        // اختيار إذاعة من بكرة الويدجت (المصدر هنا رابط الإذاعة)
        if action == "station" {
            let s = (Stations.reel + Stations.recent).first { $0.url == source } ?? Station(name: L("إذاعة"), url: source)
            playStation(s)
            return
        }
        // ويدجت مخصّصة لمصدر غير الشغّال: نبدأ ذلك المصدر بدل التحكم في الحالي
        if let s = MediaSource(rawValue: source), s != state.source {
            switchTo(s)
            if action == "toggle" || action == "play" { return }
        }
        switch action {
        case "toggle": toggle()
        case "play": play()
        case "pause": pause()
        case "next": next()
        case "prev": previous()
        case "shuffle": state.shuffle.toggle(); save()
        case "repeat": state.repeatOne.toggle(); save()
        case "forward": seek(by: 15)
        case "back": seek(by: -15)
        default: break
        }
    }

    // ── التشغيل ──
    func playQuran(_ surah: Int, reciter: Reciter? = nil) {
        if let reciter { Reciters.selected = reciter }
        let r = Reciters.selected
        // السورة المنزّلة تعمل بدون إنترنت
        guard let url = QuranDownloads.local(r, surah) ?? r.url(surah) else { return }
        state.source = .quran
        state.surah = surah
        state.title = Surahs.name(surah)
        state.subtitle = r.name
        start(url)
    }

    func playStation(_ s: Station) {
        guard let url = URL(string: s.url) else { return }
        station = s
        Stations.played(s)
        state.source = .radio
        state.title = s.name
        state.subtitle = Lang.isEN ? "Live" : "بث مباشر"
        AppGroup.defaults.set(s.url, forKey: "last_station")
        AppGroup.defaults.set(s.name, forKey: "last_station_name")
        // الرابط الأساسي ثم الاحتياطية؛ ونبدأ بآخر رابط نجح لهذه الإذاعة
        var cands = [s.url] + (s.alts ?? OfficialRadio.find(s.url)?.alts ?? [])
        if let ok = AppGroup.defaults.string(forKey: "radio_ok_" + s.url), cands.contains(ok) {
            cands.removeAll { $0 == ok }; cands.insert(ok, at: 0)
        }
        var seen = Set<String>()
        let urls = cands.filter { seen.insert($0).inserted }.compactMap(URL.init(string:))
        altKey = s.url
        altQueue = Array(urls.dropFirst())
        start(urls.first ?? url)
    }

    /// روابط احتياطية متبقية للإذاعة الحالية
    private var altQueue: [URL] = []
    private var altKey: String?

    /// جرّب الرابط الاحتياطي التالي (إن وُجد)
    @discardableResult
    private func tryNextAlt(after url: URL) -> Bool {
        guard url == currentURL, state.source == .radio, !altQueue.isEmpty else { return false }
        let next = altQueue.removeFirst()
        start(next)
        return true
    }

    /// الانتقال إلى مصدر آخر من الويدجت
    func switchTo(_ s: MediaSource) {
        switch s {
        case .quran:
            let last = NowPlaying.last(.quran)
            playQuran(last.surah)
        case .radio:
            if let u = AppGroup.defaults.string(forKey: "last_station") {
                playStation(Station(name: AppGroup.defaults.string(forKey: "last_station_name") ?? "", url: u))
            } else {
                playStation(Stations.builtin[0])
            }
        case .music:
            useAppleMusic()
            MPMusicPlayerController.systemMusicPlayer.play()
            refreshMusic(later: true)
        case .files:
            if !fileQueue.isEmpty { playFile(at: fileIndex) }
        }
    }

    func useAppleMusic() {
        player.pause()
        MPMusicPlayerController.systemMusicPlayer.beginGeneratingPlaybackNotifications()
        state.source = .music
        refreshMusic()
    }

    private func start(_ url: URL, retry: Bool = false) {
        if !retry { retries = 0 }
        if state.source != .radio { altQueue = []; altKey = nil }
        // تشغيل القرآن أو الإذاعة يوقف بث القناة
        TVPlayback.current?.pause()
        currentURL = url
        activateSession()
        let item = AVPlayerItem(url: url)
        streamTitle = nil
        if state.source == .radio {
            // عنوان البرنامج/المقطع من البث (ICY)
            let out = AVPlayerItemMetadataOutput(identifiers: nil)
            meta.onTitle = { t in Task { @MainActor in AudioPlayer.shared.gotStreamTitle(t, for: url) } }
            out.setDelegate(meta, queue: .main)
            item.add(out)
        }
        statusObserver = item.observe(\.status, options: [.new]) { it, _ in
            if it.status == .failed {
                Task { @MainActor in AudioPlayer.shared.retryAfterFailure(url) }
                return
            }
            let d = it.duration.seconds
            let ready = it.status == .readyToPlay
            if ready {
                Task { @MainActor in AudioPlayer.shared.remember(url) }
            }
            guard ready, d.isFinite, d > 0 else { return }
            Task { @MainActor in
                AudioPlayer.shared.state.duration = d
                AudioPlayer.shared.save()
            }
        }
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        stallObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { _ in
            Task { @MainActor in AudioPlayer.shared.stalled(url) }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            Task { @MainActor in AudioPlayer.shared.finished() }
        }
        player.replaceCurrentItem(with: item)
        state.position = 0
        state.duration = 0
        player.play()
        state.playing = true
        save()
        // البث لم يبدأ خلال ١٢ ثانية: ننتقل للرابط الاحتياطي
        if state.source == .radio, !altQueue.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                let a = AudioPlayer.shared
                guard url == a.currentURL, a.state.playing, a.player.timeControlStatus != .playing else { return }
                a.tryNextAlt(after: url)
            }
        }
    }

    /// حفظ الرابط الذي نجح لهذه الإذاعة ليُجرَّب أولًا في المرة القادمة
    private func remember(_ url: URL) {
        guard url == currentURL, state.source == .radio, let key = altKey else { return }
        if url.absoluteString == key {
            AppGroup.defaults.removeObject(forKey: "radio_ok_" + key)
        } else {
            AppGroup.defaults.set(url.absoluteString, forKey: "radio_ok_" + key)
        }
    }

    private var stallObserver: Any?
    /// انقطع البث: إن لم يرجع خلال ثوانٍ نعيد الاتصال تلقائيًا
    private func stalled(_ url: URL) {
        guard state.source == .radio else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            let a = AudioPlayer.shared
            guard url == a.currentURL, a.state.playing, a.player.timeControlStatus != .playing else { return }
            a.start(url, retry: true)
        }
    }

    private func gotStreamTitle(_ t: String?, for url: URL) {
        guard url == currentURL, state.source == .radio else { return }
        let clean = t?.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = (clean?.count ?? 0) > 1 && clean != "-" ? clean : nil
        guard v != streamTitle else { return }
        streamTitle = v
        state.subtitle = v ?? (Lang.isEN ? "Live" : "بث مباشر")
        save(reload: false)
    }

    // ── مؤقّت النوم ──
    func sleep(minutes: Int) {
        cancelSleep()
        let at = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepAt = at
        sleepTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60_000_000_000)
            guard !Task.isCancelled else { return }
            await AudioPlayer.shared.fadeOutAndStop()
        }
    }

    func sleepAtEndOfSurah() { cancelSleep(); sleepAtEnd = true }

    func cancelSleep() {
        sleepTask?.cancel(); sleepTask = nil
        sleepAt = nil; sleepAtEnd = false
    }

    /// يخفض الصوت تدريجيًا ثم يوقف
    private func fadeOutAndStop() async {
        sleepAt = nil; sleepTask = nil
        guard state.playing else { return }
        let v = player.volume
        for i in stride(from: 1.0, through: 0, by: -0.1) {
            player.volume = v * Float(i)
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        pause()
        player.volume = v
    }

    /// خطأ في التشغيل: نعيد المحاولة مرتين بعد لحظة
    private func retryAfterFailure(_ url: URL) {
        // الرابط تعطّل: نجرّب الاحتياطي فورًا قبل إعادة المحاولة
        if url == currentURL, state.playing, tryNextAlt(after: url) { return }
        guard url == currentURL, state.playing, retries < 2 else {
            if url == currentURL && retries >= 2 { state.playing = false; loading = false; save() }
            return
        }
        retries += 1
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard url == AudioPlayer.shared.currentURL, AudioPlayer.shared.state.playing else { return }
            AudioPlayer.shared.start(url, retry: true)
        }
    }

    func play() {
        if state.source == .music { MPMusicPlayerController.systemMusicPlayer.play(); refreshMusic(later: true); return }
        // الإذاعة بث مباشر: الاستئناف يرجع للحظة الحالية لا لمكان الإيقاف
        if state.source == .radio, player.currentItem != nil, let u = currentURL { start(u); return }
        if player.currentItem == nil, state.source == .files {
            if !fileQueue.isEmpty { playFile(at: fileIndex) }
            return
        }
        if player.currentItem == nil {
            // بعد إعادة فتح التطبيق: نكمل آخر مقطع
            if state.source == .radio, let u = AppGroup.defaults.string(forKey: "last_station") {
                playStation(Station(name: AppGroup.defaults.string(forKey: "last_station_name") ?? state.title, url: u))
            } else {
                playQuran(state.surah)
            }
            return
        }
        activateSession()
        player.play()
        if state.source == .files, rate != 1 { player.rate = rate }
        state.position = currentTime()
        state.playing = true
        save()
    }

    func pause() {
        if state.source == .music { MPMusicPlayerController.systemMusicPlayer.pause(); refreshMusic(later: true); return }
        player.pause()
        state.position = currentTime()
        state.playing = false
        save()
    }

    func toggle() {
        if state.source == .music {
            let mp = MPMusicPlayerController.systemMusicPlayer
            if mp.playbackState == .playing { mp.pause() } else { mp.play() }
            refreshMusic(later: true)
            return
        }
        state.playing ? pause() : play()
    }

    func next() {
        switch state.source {
        case .music: MPMusicPlayerController.systemMusicPlayer.skipToNextItem(); refreshMusic(later: true)
        case .quran: playQuran(nextSurah(+1))
        case .radio: stepStation(+1)
        case .files: stepFile(+1, manual: true)
        }
    }

    func previous() {
        switch state.source {
        case .music: MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem(); refreshMusic(later: true)
        case .quran:
            if currentTime() > 5 { seek(to: 0) } else { playQuran(nextSurah(-1)) }
        case .radio: stepStation(-1)
        case .files:
            if currentTime() > 5 { seek(to: 0) } else { stepFile(-1, manual: true) }
        }
    }

    private func nextSurah(_ d: Int) -> Int {
        // بعض القرّاء ليس لهم المصحف كاملًا: نتخطّى السور غير المتوفرة لديهم
        let r = Reciters.selected
        if state.shuffle {
            let avail = (1...114).filter { r.has($0) }
            return avail.randomElement() ?? Int.random(in: 1...114)
        }
        var n = state.surah
        for _ in 0..<114 {
            n += d
            if n > 114 { n = 1 }
            if n < 1 { n = 114 }
            if r.has(n) { return n }
        }
        return n
    }

    private func stepStation(_ d: Int) {
        // المفضلة ثم قوائم التشغيل (نفس ترتيب بكرة الويدجت)
        let list = Stations.reel
        guard !list.isEmpty else { return }
        let cur = AppGroup.defaults.string(forKey: "last_station")
        let i = list.firstIndex { $0.url == cur } ?? -1
        let n = ((i + d) % list.count + list.count) % list.count
        playStation(list[n])
    }

    private func finished() {
        if state.source == .files {
            if sleepAtEnd { sleepAtEnd = false; pause(); return }
            if state.repeatOne { seek(to: 0); player.play(); return }
            if FilePrefs.autoNext { stepFile(+1, manual: false) } else { pause() }
            return
        }
        guard state.source == .quran else { return }
        if sleepAtEnd { sleepAtEnd = false; pause(); return }
        if state.repeatOne { seek(to: 0); player.play(); return }
        playQuran(nextSurah(+1))
    }

    // ── ملفاتي: قائمة تشغيل الملفات الصوتية ──
    @Published private(set) var fileQueue: [URL] = []
    @Published private(set) var fileIndex = 0
    @Published var rate: Float = 1 { didSet { if state.playing { player.rate = rate } } }
    var currentFile: URL? { state.source == .files && fileQueue.indices.contains(fileIndex) ? fileQueue[fileIndex] : nil }

    func playFiles(_ urls: [URL], start: Int) {
        guard !urls.isEmpty else { return }
        fileQueue = urls
        playFile(at: max(0, min(start, urls.count - 1)))
    }

    private func playFile(at i: Int) {
        guard fileQueue.indices.contains(i) else { return }
        fileIndex = i
        let u = fileQueue[i]
        state.source = .files
        state.title = u.deletingPathExtension().lastPathComponent
        state.subtitle = u.deletingLastPathComponent().lastPathComponent
        start(u)
        if rate != 1 { player.rate = rate }
    }

    private func stepFile(_ d: Int, manual: Bool) {
        guard !fileQueue.isEmpty else { return }
        if state.shuffle, fileQueue.count > 1 {
            var n = fileIndex
            while n == fileIndex { n = Int.random(in: 0..<fileQueue.count) }
            playFile(at: n); return
        }
        let n = fileIndex + d
        if n >= fileQueue.count { if manual || state.repeatAll { playFile(at: 0) } else { pause() }; return }
        if n < 0 { playFile(at: fileQueue.count - 1); return }
        playFile(at: n)
    }

    /// إيقاف ملفاتي وإخفاء المشغّل المصغّر
    func stopFiles() {
        guard state.source == .files else { return }
        pause()
        player.replaceCurrentItem(with: nil)
        fileQueue = []
        objectWillChange.send()
    }

    func position() -> Double { currentTime() }

    func setRepeat(one: Bool, all: Bool) {
        state.repeatOne = one
        state.repeatAll = all
        save()
    }

    func seek(by s: Double) { seek(to: max(0, currentTime() + s)) }
    func seek(to t: Double) {
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        state.position = t
        save()
    }

    private func currentTime() -> Double {
        let t = player.currentTime().seconds
        return t.isFinite ? t : 0
    }

    private func activateSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio, options: [])
        try? s.setActive(true)
    }

    // ── Apple Music ──
    func refreshMusic(later: Bool = false) {
        if later {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                AudioPlayer.shared.refreshMusic()
            }
            return
        }
        guard state.source == .music else { return }
        let mp = MPMusicPlayerController.systemMusicPlayer
        let item = mp.nowPlayingItem
        state.title = item?.title ?? (Lang.isEN ? "Apple Music" : "Apple Music")
        state.subtitle = item?.artist ?? ""
        state.playing = mp.playbackState == .playing
        let t = mp.currentPlaybackTime
        state.position = t.isFinite ? t : 0
        state.duration = item?.playbackDuration ?? 0
        save()
    }

    static func requestMusicAccess() async -> Bool {
        await withCheckedContinuation { c in
            MPMediaLibrary.requestAuthorization { st in c.resume(returning: st == .authorized) }
        }
    }

    // ── الحفظ ونشر الحالة ──
    /// نبضة كل دقيقة أثناء التشغيل: لو أُغلق التطبيق تعرف الويدجت أن التشغيل توقف (ولا تبقى على «يعمل»)
    private var beat: Timer?
    private func heartbeat() {
        let live = state.playing && state.source != .music
        if live {
            NowPlaying.alive = Date()
            if beat == nil {
                beat = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                    Task { @MainActor in NowPlaying.alive = Date() }
                }
            }
        } else {
            beat?.invalidate(); beat = nil
        }
    }

    private func save(reload: Bool = true) {
        state.at = Date().timeIntervalSince1970
        heartbeat()
        NowPlaying.current = state
        NowPlaying.saveLast(state)
        if state.source != .music { updateNowPlayingInfo() }
        if reload { MediaKinds.reload() }
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: state.title,
            MPMediaItemPropertyArtist: state.subtitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.position,
            MPNowPlayingInfoPropertyPlaybackRate: state.playing ? Double(state.source == .files ? rate : 1) : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: state.source == .radio,
        ]
        if state.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = state.duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        // أزرار ±ثوانٍ في شاشة القفل لملفاتي فقط (الإذاعة والتلاوة تبقى بالتالي والسابق)
        let rc = MPRemoteCommandCenter.shared()
        rc.skipForwardCommand.isEnabled = state.source == .files
        rc.skipBackwardCommand.isEnabled = state.source == .files
        rc.changePlaybackPositionCommand.isEnabled = state.source != .radio
    }
}

/// يقرأ عنوان البث (اسم البرنامج أو الأغنية) الذي ترسله الإذاعات
final class StreamMeta: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    var onTitle: ((String?) -> Void)?
    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        let items = groups.flatMap(\.items)
        let cb = onTitle
        Task {
            for it in items where it.identifier == .icyMetadataStreamTitle || it.commonKey == .commonKeyTitle {
                if let v = try? await it.load(.stringValue) { cb?(v); return }
            }
        }
    }
}
