import Foundation
import AVFoundation
import ActivityKit
import UserNotifications
import WidgetKit

// MARK: - المتابعة المباشرة الصامتة
// صوت صامت تمامًا (يُمزج مع أي صوت آخر) يُبقي التطبيق صاحيًا في الخلفية،
// فيسحب النتيجة كل ٢٠ ثانية ويحدّث الويدجت والنشاط المباشر ويرسل الإشعارات.
// الصوت الوحيد المسموع: صوت الإشعارات.

@MainActor
final class SportsLive: ObservableObject {
    static let shared = SportsLive()

    @Published private(set) var match: SMatch?
    @Published private(set) var active = false
    @Published private(set) var lastError = ""

    private var loop: Task<Void, Never>?
    private var silent: AVAudioPlayer?
    private var activity: Activity<MatchAttributes>?
    private var seen = Set<String>()
    private var lastStatus = ""
    private var lastState = ""
    private var configured = false
    private var interruptionObserver: Any?

    private init() {}

    func configure() {
        guard !configured else { return }
        configured = true
        SportsBridge.follow = { league, id in await SportsLive.shared.follow(league: league, id: id) }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                                                      object: nil, queue: .main) { n in
            let ended = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.ended.rawValue
            Task { @MainActor in if ended { SportsLive.shared.resumeSilent() } }
        }
        // نشاط قديم من تشغيل سابق
        if SportsPrefs.following.isEmpty {
            for a in Activity<MatchAttributes>.activities {
                Task { await a.end(nil, dismissalPolicy: .immediate) }
            }
        } else {
            activity = Activity<MatchAttributes>.activities.first { $0.attributes.matchId == SportsPrefs.following }
        }
    }

    // ── البدء والإيقاف ──
    func follow(league: String, id: String) async {
        configure()
        if id.isEmpty { stop(); return }
        if active && match?.id == id { return }
        stop(keepActivity: false)
        var m = locate(id)
        let fresh: SMatch?
        if let known = m { fresh = await Sports.poll(known) } else { fresh = await ESPN.summary(league, event: id) }
        if let fresh { m = fresh }
        guard let start = m else { lastError = Lang.isEN ? "Match not found" : "تعذّر العثور على المباراة"; return }
        // مباراة منتهية أو مؤجلة: نحدّث بياناتها فقط بدون متابعة
        if start.done || start.postponed {
            match = start
            Sports.merge(start)
            Sports.reloadWidgets()
            return
        }
        match = start
        seen = Set(start.keys.map { keyID($0) })
        lastStatus = start.status
        lastState = start.state
        active = true
        SportsPrefs.following = id
        SportsPrefs.followHeartbeat = Date()
        startSilent()
        startActivity(start)
        Sports.merge(start)
        Sports.reloadWidgets()
        loop = Task { @MainActor in
            while !Task.isCancelled {
                let wait = await SportsLive.shared.tick()
                if wait < 0 { break }
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    func stop(keepActivity: Bool = false) {
        loop?.cancel()
        loop = nil
        if active {
            active = false
            SportsPrefs.following = ""
            stopSilent()
            if !keepActivity, let a = activity {
                let st = match.map { MatchAttributes.ContentState($0) }
                Task { await a.end(st.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: .immediate) }
                activity = nil
            }
            Sports.reloadWidgets()
        }
    }

    /// عند فتح التطبيق: نبدأ النشاط المباشر إذا ما بدأ من الخلفية
    func appBecameActive() {
        if active, activity == nil, let m = match { startActivity(m) }
    }

    private func locate(_ id: String) -> SMatch? {
        guard let d = SportsStore.load() else { return nil }
        return (d.next + d.day + d.last).first { $0.id == id }
    }

    private func keyID(_ k: SKey) -> String { "\(k.kind)|\(k.minute)|\(k.player)|\(k.team)" }

    // ── الدورة: كل ٢٠ ثانية أثناء المباراة ──
    /// يرجّع ثواني الانتظار للدورة التالية، أو -١ للتوقف
    private func tick() async -> Double {
        guard active, let cur = match else { return -1 }
        let now = Date()
        SportsPrefs.followHeartbeat = now
        ensureSilent()
        // قبل المباراة بوقت طويل: نتحقق كل دقيقتين
        if cur.state == "pre" && cur.date.timeIntervalSince(now) > 10 * 60 { return min(120, cur.date.timeIntervalSince(now) - 9 * 60) }
        guard let m = await Sports.poll(cur) else { return 20 }
        let changed = m.hs != cur.hs || m.aws != cur.aws || m.status != cur.status || m.keys.count != cur.keys.count
        notifyChanges(old: cur, new: m)
        match = m
        let merged = Sports.merge(m)
        if m.keys.count != cur.keys.count { await SportsImages.ensure(merged) }
        if changed { Sports.reloadWidgets() }
        updateActivity(m)
        if m.done || m.postponed {
            finish(m)
            return -1
        }
        return m.halftime ? 30 : 20
    }

    private func finish(_ m: SMatch) {
        loop = nil
        active = false
        SportsPrefs.following = ""
        stopSilent()
        if let a = activity {
            let st = MatchAttributes.ContentState(m)
            Task { await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(20 * 60))) }
            activity = nil
        }
        Sports.reloadWidgets()
        Task { await Sports.refresh(); Sports.reloadWidgets() }
    }

    // ── الإشعارات ──
    private func scoreLine(_ m: SMatch) -> String {
        "\(m.home.display) \(sScoreInline(m, sep: " - ")) \(m.away.display)"
    }

    private func notifyChanges(old: SMatch, new m: SMatch) {
        // بداية المباراة
        if old.state == "pre" && m.state == "in" && SportsPrefs.notifyPhases {
            SportsNotify.now(Lang.isEN ? "Kick-off" : "بدأت المباراة", "\(m.home.display) - \(m.away.display)", id: "sp_ko_\(m.id)", match: m)
        }
        for k in m.keys where !seen.contains(keyID(k)) {
            seen.insert(keyID(k))
            let team = k.team == m.home.id ? m.home.display : m.away.display
            if k.isGoal && SportsPrefs.notifyGoals {
                let t = (Lang.isEN ? "⚽︎ GOAL! " : "⚽︎ هدف! ") + scoreLine(m)
                let extra = k.kind == "pen" ? (Lang.isEN ? " (pen)" : " (ركلة جزاء)") : k.kind == "og" ? (Lang.isEN ? " (own goal)" : " (هدف عكسي)") : ""
                SportsNotify.now(t, "\(k.player)\(extra) \(k.minute) · \(team)", id: "sp_g_\(m.id)_\(seen.count)", match: m)
            } else if k.kind == "red" && SportsPrefs.notifyCards {
                SportsNotify.now((Lang.isEN ? "🟥 Red card · " : "🟥 بطاقة حمراء · ") + team, "\(k.player) \(k.minute)", id: "sp_r_\(m.id)_\(seen.count)", match: m)
            }
        }
        if SportsPrefs.notifyPhases && m.status != lastStatus {
            if m.halftime {
                SportsNotify.now(Lang.isEN ? "Half-time" : "نهاية الشوط الأول", scoreLine(m), id: "sp_ht_\(m.id)", match: m)
            } else if lastStatus == "STATUS_HALFTIME" && m.live {
                SportsNotify.now(Lang.isEN ? "Second half" : "بدأ الشوط الثاني", scoreLine(m), id: "sp_2h_\(m.id)", match: m)
            }
        }
        if m.done && lastState != "post" && SportsPrefs.notifyPhases {
            SportsNotify.now(Lang.isEN ? "Full time" : "انتهت المباراة", scoreLine(m), id: "sp_ft_\(m.id)", match: m)
        }
        lastStatus = m.status
        lastState = m.state
    }

    // ── النشاط المباشر ──
    private func startActivity(_ m: SMatch) {
        guard SportsPrefs.liveActivity, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let a = activity, a.attributes.matchId == m.id { return }
        let attr = MatchAttributes(matchId: m.id, league: m.league, leagueName: Leagues.get(m.league).name,
                                   kickoff: m.date, home: m.home, away: m.away)
        do {
            activity = try Activity.request(attributes: attr,
                                            content: ActivityContent(state: MatchAttributes.ContentState(m), staleDate: nil),
                                            pushType: nil)
        } catch {
            activity = nil   // من الخلفية قد يرفض النظام؛ يبدأ عند فتح التطبيق
        }
    }

    private func updateActivity(_ m: SMatch) {
        guard let a = activity else { startActivity(m); return }
        let st = MatchAttributes.ContentState(m)
        Task { await a.update(ActivityContent(state: st, staleDate: Date().addingTimeInterval(5 * 60))) }
    }

    // ── الصوت الصامت ──
    private func startSilent() {
        let s = AVAudioSession.sharedInstance()
        // إذا القرآن أو الإذاعة شغّالة نخلي إعدادها؛ وإلا نمزج مع أي صوت ثاني بدون ما نوقفه
        if !AudioPlayer.shared.state.playing {
            try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try? s.setActive(true)
        if silent == nil {
            silent = try? AVAudioPlayer(data: Self.silentWAV())
            silent?.numberOfLoops = -1
            silent?.volume = 0
        }
        silent?.prepareToPlay()
        silent?.play()
    }

    /// لو وقف القرآن أو الإذاعة نرجع للمزج حتى ما نقاطع أي تطبيق ثاني
    private func ensureSilent() {
        let s = AVAudioSession.sharedInstance()
        if !AudioPlayer.shared.state.playing && !s.categoryOptions.contains(.mixWithOthers) {
            try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        if silent?.isPlaying == false {
            try? s.setActive(true)
            silent?.play()
        }
    }

    fileprivate func resumeSilent() {
        guard active else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        silent?.play()
    }

    private func stopSilent() {
        silent?.stop()
        silent = nil
        if !AudioPlayer.shared.state.playing {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// ثانية صامتة (PCM ١٦ بت، ٨ كيلوهرتز)
    private static func silentWAV() -> Data {
        let rate: UInt32 = 8000, samples: UInt32 = 8000
        let dataSize = samples * 2
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(36 + dataSize)
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(dataSize)
        d.append(Data(count: Int(dataSize)))
        return d
    }
}

// MARK: - الإشعارات داخل التطبيق والضغط عليها

final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    static func registerCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(NotifyKinds.categories)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // «ذكّرني بعد ١٠ دقائق»: نفس الإشعار بعد عشر دقائق
        if response.actionIdentifier == NotifyKinds.snooze,
           let c = response.notification.request.content.mutableCopy() as? UNMutableNotificationContent {
            c.categoryIdentifier = NotifyKinds.prayer
            c.attachments = []
            // تأجيل التنبيه المسبق: بعد ١٠ دقائق يكون الوقت قد دخل، فلا يصح نص «اقترب…» ولا صوته
            // (المعرّف: miqat.pre.<الوقت>.<يونكس>)
            let parts = response.notification.request.identifier.split(separator: ".")
            if parts.count == 4, parts[1] == "pre", let t = Double(parts[3]) {
                c.title = Notify.title(String(parts[2]), pre: false)
                c.body = LF("الساعة %@", hm12(Date(timeIntervalSince1970: t))) + "."
                c.sound = .default
            }
            let req = UNNotificationRequest(identifier: "snooze." + UUID().uuidString, content: c,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false))
            center.add(req)
            completionHandler()
            return
        }
        let url = response.notification.request.content.userInfo["url"] as? String
        if let url, let u = URL(string: url) {
            Task { @MainActor in SportsRouter.shared.open(u) }
        }
        completionHandler()
    }
}

/// روابط رفيقي الخاصة بالمباريات: miqat://follow/<league>/<id>
@MainActor
final class SportsRouter: ObservableObject {
    static let shared = SportsRouter()
    @Published var showSports = 0

    func open(_ url: URL) {
        guard url.scheme == "miqat" else { return }
        if url.host == "follow" {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2 {
                Task { await SportsLive.shared.follow(league: parts[0], id: parts[1]) }
            }
            showSports += 1
        } else if url.host == "sports" {
            showSports += 1
        }
    }
}
