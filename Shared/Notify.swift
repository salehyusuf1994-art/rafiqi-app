import Foundation
import UserNotifications

// MARK: - مركز الإشعارات: تنبيه عند دخول كل وقت + تنبيه قبله بخمس دقائق (محلي على الجهاز — بلا خوادم)

enum Notify {
    struct Item: Identifiable {
        let id: String          // fajr, sunrise, dhuhr, asr, maghrib, isha, midnight
        let name: String
        let icon: String
        let isPrayer: Bool
    }

    static let items: [Item] = [
        Item(id: "fajr", name: "الفجر", icon: "sunrise.fill", isPrayer: true),
        Item(id: "sunrise", name: "الشروق", icon: "sun.horizon.fill", isPrayer: false),
        Item(id: "dhuhr", name: "الظهر", icon: "sun.max.fill", isPrayer: true),
        Item(id: "asr", name: "العصر", icon: "cloud.sun.fill", isPrayer: true),
        Item(id: "maghrib", name: "المغرب", icon: "sunset.fill", isPrayer: true),
        Item(id: "isha", name: "العشاء", icon: "moon.stars.fill", isPrayer: true),
        Item(id: "midnight", name: "منتصف الليل", icon: "moon.fill", isPrayer: false),
    ]
    static let preMinutes = 5

    private static var d: UserDefaults { AppGroup.defaults }

    // ── الإعدادات ──
    /// تنبيه دخول الوقت (الافتراضي: الصلوات الخمس)
    static var atKeys: Set<String> {
        get { Set((d.array(forKey: "notif_at") as? [String]) ?? ["fajr", "dhuhr", "asr", "maghrib", "isha"]) }
        set { d.set(Array(newValue), forKey: "notif_at") }
    }
    /// التنبيه قبل الوقت بخمس دقائق
    static var preKeys: Set<String> {
        get { Set((d.array(forKey: "notif_pre") as? [String]) ?? []) }
        set { d.set(Array(newValue), forKey: "notif_pre") }
    }
    /// صوت ناطق بدل النغمة
    static var voice: Bool {
        get { d.object(forKey: "notif_voice") as? Bool ?? true }
        set { d.set(newValue, forKey: "notif_voice") }
    }
    /// تنبيهات صوتية إضافية لا تظهر في المواقيت ولا الويدجت:
    /// duha = صلاة الضحى (قبل أذان الظهر بـ٣٠ دقيقة يوميًا) — jhour = ساعة الجمعة (قبل أذان المغرب بـ٤٥ دقيقة كل جمعة)
    static let extraIDs = ["duha", "jhour"]
    static let duhaBeforeDhuhr = 30
    static let jhourBeforeMaghrib = 45
    static var extraOn: Set<String> {
        get { Set((d.array(forKey: "notif_extra") as? [String]) ?? extraIDs) }
        set { d.set(Array(newValue), forKey: "notif_extra") }
    }
    static func isExtra(_ key: String) -> Bool { extraIDs.contains(key) }

    // ── صوت تنبيه دخول الوقت لكل صلاة ──
    enum SoundMode: String, CaseIterable, Identifiable {
        case voice, tone, part, full
        var id: String { rawValue }
        var title: String {
            switch self {
            case .voice: return L("التنبيه الناطق")
            case .tone: return L("نغمة")
            case .part: return L("جزء من الأذان")
            case .full: return L("الأذان كاملًا")
            }
        }
        var subtitle: String {
            switch self {
            case .voice: return L("«حان وقت صلاة…» بصوت رفيقي")
            case .tone: return L("نغمة الإشعارات العادية")
            case .part: return L("أول ٢٨ ثانية من الأذان مع الإشعار")
            case .full: return L("كمنبّه يعمل حتى والجوال صامت، ويتكرر حتى تضغط «إيقاف»")
            }
        }
    }
    /// الصلوات التي يمكن أن يكون تنبيهها أذانًا
    static func adhanCapable(_ key: String) -> Bool { ["fajr", "dhuhr", "jumuah", "asr", "maghrib", "isha"].contains(key) }
    static func setting(of key: String) -> String { key == "jumuah" ? "dhuhr" : key }

    static func mode(_ key: String) -> SoundMode {
        let k = setting(of: key)
        if adhanCapable(k), let raw = (d.dictionary(forKey: "notif_mode") as? [String: String])?[k], let m = SoundMode(rawValue: raw) { return m }
        return voice ? .voice : .tone
    }
    static func setMode(_ key: String, _ m: SoundMode) {
        var all = (d.dictionary(forKey: "notif_mode") as? [String: String]) ?? [:]
        all[setting(of: key)] = m.rawValue
        d.set(all, forKey: "notif_mode")
    }

    // ── المؤذنون ──
    struct Muezzin: Identifiable, Hashable {
        let id: String
        let arName: String
        let enName: String
        var name: String { Lang.isEN ? enName : arName }
        var full: String { "adhan_\(id).caf" }
        var part: String { "adhan_\(id)_part.caf" }
    }
    static let muezzins: [Muezzin] = [
        Muezzin(id: "afasy", arName: "مشاري العفاسي", enName: "Mishary Alafasy"),
        Muezzin(id: "qatami", arName: "ناصر القطامي", enName: "Nasser Al-Qatami"),
        Muezzin(id: "zahrani", arName: "منصور الزهراني", enName: "Mansour Al-Zahrani"),
        Muezzin(id: "deghreri", arName: "حمد الدغريري", enName: "Hamad Al-Deghreri"),
        Muezzin(id: "arkani", arName: "إبراهيم الأركاني", enName: "Ibrahim Al-Arkani"),
        Muezzin(id: "malki", arName: "حمدان المالكي", enName: "Hamdan Al-Malki"),
    ]
    /// أذان الفجر الخاص («الصلاة خير من النوم»)
    static let fajrAdhan = Muezzin(id: "fajr", arName: "أذان الفجر (الصلاة خير من النوم)", enName: "Fajr adhan (as-salatu khayrun min an-nawm)")
    static var muezzinID: String {
        get { d.string(forKey: "muezzin") ?? "afasy" }
        set { d.set(newValue, forKey: "muezzin") }
    }
    /// مؤذن الفجر: أذان الفجر الخاص افتراضيًا، أو أحد المؤذنين
    static var fajrMuezzinID: String {
        get { d.string(forKey: "muezzin_fajr") ?? "fajr" }
        set { d.set(newValue, forKey: "muezzin_fajr") }
    }
    static func muezzin(for key: String) -> Muezzin {
        let id = key == "fajr" ? fajrMuezzinID : muezzinID
        if id == fajrAdhan.id { return fajrAdhan }
        return muezzins.first { $0.id == id } ?? muezzins[0]
    }

    // ── الأذان كاملًا (منبّه — يضبطه التطبيق على iOS 26.1 وما بعده) ──
    struct AlarmItem {
        let date: Date
        let title: String
        let sound: String
    }
    /// يضبطه التطبيق: يجدول المنبّهات ويرجّع نجاحها — وفي الويدجت يبقى فارغًا
    static var alarmBridge: (([AlarmItem]) async -> Bool)? = nil
    /// آخر منبّه أذان مجدول (الويدجت لا تكرّر تنبيه تلك الأوقات)
    static var alarmsUntil: Date {
        get { Date(timeIntervalSince1970: d.double(forKey: "alarm_until")) }
        set { d.set(newValue.timeIntervalSince1970, forKey: "alarm_until") }
    }

    /// هل فيه أي تنبيه مفعّل
    static var enabled: Bool { !atKeys.isEmpty || !preKeys.isEmpty || !extraOn.isEmpty }

    private static var lastRun: Date {
        get { Date(timeIntervalSince1970: d.double(forKey: "notif_last")) }
        set { d.set(newValue.timeIntervalSince1970, forKey: "notif_last") }
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// يطلب إذن الإشعارات أول مرة فقط (لو ما سبق سؤال المستخدم) — بدونه ما يظهر «الإشعارات» في إعدادات الآيفون أصلًا
    @discardableResult
    static func askIfNeeded() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        if s.authorizationStatus == .notDetermined { return await requestPermission() }
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    static func authorized() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    static func item(_ id: String) -> Item? { items.first { $0.id == id } }

    // ── نصوص التنبيهات ──
    /// عنوان التنبيه — key قد يكون jumuah
    static func title(_ key: String, pre: Bool) -> String {
        switch key {
        case "duha": return L("صلاة الضحى")
        case "jhour": return L("ساعة الإجابة يوم الجمعة")
        case "sunrise": return L(pre ? "اقترب وقت شروق الشمس" : "حان وقت شروق الشمس")
        case "midnight": return L(pre ? "اقترب وقت منتصف الليل" : "حان وقت منتصف الليل")
        case "jumuah": return L(pre ? "اقترب وقت صلاة الجمعة" : "حان وقت صلاة الجمعة")
        default:
            let n = L(item(key)?.name ?? "")
            return pre ? LF("اقترب وقت صلاة %@", n) : LF("حان وقت صلاة %@", n)
        }
    }

    private static func body(_ key: String, time: Date, pre: Bool, extra: Date?) -> String {
        // اسم المدينة صار في العنوان الفرعي للإشعار
        let place = ""
        // مع «ص/م» (أو AM/PM) في نظام ١٢ ساعة: «٥:١٢» وحدها قد تكون فجرًا أو عصرًا
        let at = clock(time)
        // العدد مع التمييز الصحيح: «١٥ دقيقة» لا «١٥ دقائق»
        if key == "duha" { return LF("بقي على أذان الظهر %@، فاغتنم صلاة الضحى.", minutesText(duhaBeforeDhuhr)) }
        if key == "jhour" { return LF("بقي على أذان المغرب %@، فأكثر من الدعاء في آخر ساعة من الجمعة.", minutesText(jhourBeforeMaghrib)) }
        if pre {
            switch key {
            case "sunrise": return LF("تشرق الشمس بعد %@، الساعة %@", minutesText(preMinutes), at) + place + "."
            case "midnight": return LF("يحين منتصف الليل بعد %@، الساعة %@", minutesText(preMinutes), at) + "."
            default: return LF("يُرفع الأذان بعد %@، الساعة %@", minutesText(preMinutes), at) + place + "."
            }
        }
        switch key {
        case "sunrise": return LF("خرج وقت صلاة الفجر، الساعة %@", at) + place + "." + nextLine(after: time)
        case "midnight": return LF("الساعة %@", at) + "."
        default: return LF("الساعة %@", at) + place + "." + nextLine(after: time)
        }
    }

    /// سطر «التالي»: الوقت الذي بعد هذا التنبيه (مثل: التالي العصر ٣:١٦ م)
    private static func nextLine(after time: Date) -> String {
        let nx = Prayer.prevNext(at: time.addingTimeInterval(60)).next
        let name = nx.key == .jumuah ? L("الجمعة") : L(item(nx.key.rawValue)?.name ?? "")
        guard !name.isEmpty, nx.key != .midnight else { return "" }
        return "\n" + LF("التالي: %@ الساعة %@", name, clock(nx.time))
    }

    private static func clock(_ d: Date) -> String {
        let a = ampmText(d)
        return hm12(d) + (a.isEmpty ? "" : " " + a)
    }

    private static func sound(_ key: String, pre: Bool) -> UNNotificationSound {
        if !pre && adhanCapable(key) {
            switch mode(key) {
            case .tone: return .default
            case .part, .full: return UNNotificationSound(named: UNNotificationSoundName(muezzin(for: key).part))
            case .voice: return UNNotificationSound(named: UNNotificationSoundName("miqat_\(key).caf"))
            }
        }
        guard voice else { return .default }
        // لو الملف غير موجود يرجع iOS للنغمة الافتراضية تلقائيًا
        return UNNotificationSound(named: UNNotificationSoundName("miqat_\(pre ? "pre_" : "")\(key).caf"))
    }

    // ── الجدولة ──
    /// يمسح التنبيهات السابقة ويجدول القادمة (حتى ٦٠ تنبيهًا) — بالدور: طلبان متتاليان لا يتداخلان
    /// (كان الأول يكمل إضافة تنبيه أطفأه المستخدم بعده بلحظة)
    static func reschedule() async {
        await serial.run { await rescheduleNow() }
    }

    private actor Serial {
        private var last: Task<Void, Never>?
        func run(_ work: @escaping @Sendable () async -> Void) async {
            let previous = last
            let task = Task { _ = await previous?.value; await work() }
            last = task
            await task.value
        }
    }
    private static let serial = Serial()

    private static func rescheduleNow() async {
        let c = UNUserNotificationCenter.current()
        let old = await c.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("miqat.") }
        c.removePendingNotificationRequests(withIdentifiers: old)
        lastRun = Date()
        // كل التنبيهات متوقفة: نلغي منبّهات الأذان أيضًا
        guard enabled else {
            if let bridge = alarmBridge { _ = await bridge([]); alarmsUntil = .distantPast }
            return
        }
        // منبّهات الأذان لها إذنها الخاص، فتُجدول حتى لو مُنعت الإشعارات
        let canNotify = await authorized()

        let now = Date(), cal = Cal.gregCal, at = atKeys, pre = preKeys, extra = extraOn
        // (المفتاح الأصلي، مفتاح الإعداد، الوقت، وقت إضافي للنص)
        var events: [(key: String, setting: String, time: Date, extra: Date?)] = []
        for off in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: off, to: now),
                  let next = cal.date(byAdding: .day, value: 1, to: day) else { continue }
            for p in Prayer.dayTimes(day) {
                let k = p.key.rawValue
                events.append((k, k == "jumuah" ? "dhuhr" : k, p.time, nil))
            }
            let mg = Prayer.times(for: day)[4], fj = Prayer.times(for: next)[0]
            let span = fj.timeIntervalSince(mg)
            events.append(("midnight", "midnight", mg.addingTimeInterval(span / 2), nil))
            // الضحى: قبل الظهر (أو الجمعة) بنصف ساعة — وساعة الجمعة: قبل المغرب بـ٤٥ دقيقة
            if let dh = Prayer.dayTimes(day).first(where: { $0.key == .dhuhr || $0.key == .jumuah }) {
                events.append(("duha", "duha", dh.time.addingTimeInterval(-Double(duhaBeforeDhuhr * 60)), nil))
            }
            if Cal.weekday(day) == 5 {
                events.append(("jhour", "jhour", mg.addingTimeInterval(-Double(jhourBeforeMaghrib * 60)), nil))
            }
        }

        // الأقرب أولًا، وبحد ٦٠ (النظام يحتفظ بـ٦٤ تنبيهًا فقط، ونترك هامشًا للتذكيرات الأخرى)
        var plan: [(fire: Date, key: String, time: Date, pre: Bool)] = []
        for e in events {
            for isPre in [false, true] {
                if isExtra(e.key) {
                    guard !isPre, extra.contains(e.key) else { continue }
                } else {
                    guard (isPre ? pre : at).contains(e.setting) else { continue }
                }
                let fire = isPre ? e.time.addingTimeInterval(-Double(preMinutes * 60)) : e.time
                guard fire > now.addingTimeInterval(5) else { continue }
                plan.append((fire, e.key, e.time, isPre))
            }
        }
        plan.sort { $0.fire < $1.fire }

        // الأذان كاملًا: منبّهات للأيام الثلاثة القادمة (من التطبيق)، ولا يتكرر تنبيه الوقت نفسه
        let fulls = plan.filter { !$0.pre && adhanCapable($0.key) && mode($0.key) == .full }
        var covered = Set<Date>()
        if let bridge = alarmBridge {
            let soon = fulls.filter { $0.fire < now.addingTimeInterval(3 * 86400) }
            let items = soon.map { AlarmItem(date: $0.fire, title: title($0.key, pre: false), sound: muezzin(for: $0.key).full) }
            if await bridge(items) {
                covered = Set(soon.map { $0.fire })
                alarmsUntil = soon.last?.fire ?? now
            } else {
                alarmsUntil = .distantPast
            }
        } else {
            let until = alarmsUntil
            covered = Set(fulls.filter { $0.fire <= until }.map { $0.fire })
        }
        plan.removeAll { !$0.pre && covered.contains($0.fire) && adhanCapable($0.key) }
        guard canNotify else { return }
        // صورة الإشعار تُرسم مرة لكل وقت، وتُرفق فقط بالتنبيهات اللي فعلًا تُجدول
        var art: [String: Data] = [:]
        var ids = Set<String>()
        // الخطة أطول من حد النظام: آخر خانة تذكير بفتح التطبيق، حتى لا تتوقف التنبيهات بصمت
        let limit = plan.count > 60 ? 59 : 60
        for p in plan.prefix(limit) {
            let content = UNMutableNotificationContent()
            content.title = title(p.key, pre: p.pre)
            content.body = body(p.key, time: p.time, pre: p.pre, extra: nil)
            content.sound = sound(p.key, pre: p.pre)
            if !Settings.placeName.isEmpty { content.subtitle = Settings.placeName }
            content.threadIdentifier = "miqat.prayer"
            content.categoryIdentifier = p.pre ? NotifyKinds.pre : NotifyKinds.prayer
            content.relevanceScore = p.pre ? 0.6 : 1
            if !isExtra(p.key) {
                if art[p.key] == nil { art[p.key] = NotifyArt.prayer(p.key) }
                if let a = NotifyArt.attachment(art[p.key], id: p.key) { content.attachments = [a] }
            }
            // التقويم والمنطقة داخل المكوّنات: لو كان تقويم الجوال هجريًا، لا تُقرأ سنة ٢٠٢٦ كأنها هجرية فلا يصل التنبيه
            let comps = cal.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: p.fire)
            let id = "miqat.\(p.pre ? "pre." : "")\(p.key).\(Int(p.time.timeIntervalSince1970))"
            let r = UNNotificationRequest(identifier: id, content: content,
                                          trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            ids.insert(id)
            try? await c.add(r)
        }
        if limit == 59, let last = plan.prefix(limit).last {
            let content = UNMutableNotificationContent()
            content.title = L("رفيقي")
            content.body = L("افتح رفيقي لتجديد تنبيهات الصلاة للأيام القادمة.")
            content.sound = .default
            content.threadIdentifier = "miqat.prayer"
            let fire = last.fire.addingTimeInterval(60)
            let comps = cal.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: fire)
            let id = "miqat.renew"
            ids.insert(id)
            try? await c.add(UNNotificationRequest(identifier: id, content: content,
                                                   trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
        // تقارب: أي تنبيه «miqat.» ليس في هذه الخطة (من تشغيل سابق في التطبيق أو الويدجت) يُحذف
        let stray = await c.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("miqat.") && !ids.contains($0) }
        if !stray.isEmpty { c.removePendingNotificationRequests(withIdentifiers: stray) }
    }

    /// للويدجت: يجدّد الجدولة مرة كل ١٢ ساعة على الأكثر (حتى لو ما انفتح التطبيق)
    static func refreshIfStale() async {
        guard enabled, Date().timeIntervalSince(lastRun) > 12 * 3600 else { return }
        // نسجّل الوقت فورًا حتى لا تكرّر الويدجت الأخرى نفس العمل في اللحظة نفسها
        lastRun = Date()
        await reschedule()
    }
}
