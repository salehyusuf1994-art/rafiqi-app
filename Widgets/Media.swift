import Foundation
import SwiftUI
import WidgetKit
import AppIntents

// MARK: - الصوتيات: القرآن، الإذاعات، Apple Music
// النموذج مشترك بين التطبيق والويدجت، والتشغيل نفسه داخل التطبيق فقط (App/AudioPlayer.swift)

enum MediaSource: String, Codable { case quran, radio, music, files }

/// حالة التشغيل الحالية (يكتبها التطبيق، وتقرؤها الويدجت)
struct NowPlaying: Codable, Equatable {
    var source: MediaSource = .quran
    var title = "الفاتحة"
    var subtitle = "مشاري العفاسي"
    var playing = false
    var position: Double = 0
    var duration: Double = 0
    var at: Double = 0
    var surah = 1
    var shuffle = false
    var repeatOne = false
    /// تكرار القائمة كلها (لملفاتي)
    var repeatAll = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? c.decode(MediaSource.self, forKey: .source)) ?? .quran
        title = (try? c.decode(String.self, forKey: .title)) ?? "الفاتحة"
        subtitle = (try? c.decode(String.self, forKey: .subtitle)) ?? ""
        playing = (try? c.decode(Bool.self, forKey: .playing)) ?? false
        position = (try? c.decode(Double.self, forKey: .position)) ?? 0
        duration = (try? c.decode(Double.self, forKey: .duration)) ?? 0
        at = (try? c.decode(Double.self, forKey: .at)) ?? 0
        surah = (try? c.decode(Int.self, forKey: .surah)) ?? 1
        shuffle = (try? c.decode(Bool.self, forKey: .shuffle)) ?? false
        repeatOne = (try? c.decode(Bool.self, forKey: .repeatOne)) ?? false
        repeatAll = (try? c.decode(Bool.self, forKey: .repeatAll)) ?? false
    }

    /// بث مباشر: الإذاعة فقط (التلاوة قبل معرفة مدتها ليست «مباشر»)
    var live: Bool { source == .radio }
    /// مقطع معروف المدة (يُعرض له عدّاد وتقدّم)
    var timed: Bool { !live && duration > 0 }

    /// الموضع الآن (يتقدّم مع الوقت أثناء التشغيل)
    func elapsed(at now: Date = Date()) -> Double {
        let p = playing ? position + max(0, now.timeIntervalSince1970 - at) : position
        return duration > 0 ? min(duration, p) : p
    }
    /// بداية المقطع (لعدّاد الويدجت الحي)
    var startDate: Date { Date(timeIntervalSince1970: at - position) }

    static var current: NowPlaying {
        get { AppGroup.defaults.data(forKey: "nowplaying").flatMap { try? JSONDecoder().decode(NowPlaying.self, from: $0) } ?? NowPlaying() }
        set { AppGroup.defaults.set(try? JSONEncoder().encode(newValue), forKey: "nowplaying") }
    }

    /// آخر حالة لكل مصدر (القرآن / الإذاعة / Apple Music)
    static func last(_ src: MediaSource) -> NowPlaying {
        if let d = AppGroup.defaults.data(forKey: "nowplaying." + src.rawValue),
           let n = try? JSONDecoder().decode(NowPlaying.self, from: d) { return n }
        var n = NowPlaying()
        n.source = src
        switch src {
        case .quran: n.title = Surahs.name(1); n.subtitle = Reciters.selected.name
        case .radio:
            n.title = AppGroup.defaults.string(forKey: "last_station_name") ?? Stations.builtin[0].name
            n.subtitle = Lang.isEN ? "Live" : "بث مباشر"
        case .music: n.title = "Apple Music"; n.subtitle = ""
        case .files: n.title = Lang.isEN ? "My files" : "ملفاتي"; n.subtitle = ""
        }
        return n
    }
    static func saveLast(_ n: NowPlaying) {
        AppGroup.defaults.set(try? JSONEncoder().encode(n), forKey: "nowplaying." + n.source.rawValue)
    }

    /// آخر نبضة من التطبيق أثناء التشغيل (كل دقيقة)
    static var alive: Date {
        get { Date(timeIntervalSince1970: AppGroup.defaults.double(forKey: "np_alive")) }
        set { AppGroup.defaults.set(newValue.timeIntervalSince1970, forKey: "np_alive") }
    }

    /// ما تعرضه ويدجت مخصّصة لمصدر معيّن: الحالة الحية إن كان هو الشغّال، وإلا آخر حالة له (متوقفة)
    static func display(for src: String) -> NowPlaying {
        var cur = current
        // أُغلق التطبيق أثناء التشغيل (لا نبضة منذ دقائق): التشغيل توقف فعليًا
        if cur.playing && cur.source != .music {
            let a = alive
            if Date().timeIntervalSince(a) > 150 {
                cur.position = cur.elapsed(at: a)
                cur.at = a.timeIntervalSince1970
                cur.playing = false
            }
        }
        guard let s = MediaSource(rawValue: src), s != cur.source else { return cur }
        var n = last(s)
        n.playing = false
        return n
    }
}

// MARK: - السور

enum Surahs {
    static let ar = ["الفاتحة", "البقرة", "آل عمران", "النساء", "المائدة", "الأنعام", "الأعراف", "الأنفال", "التوبة", "يونس", "هود", "يوسف", "الرعد", "إبراهيم", "الحجر", "النحل", "الإسراء", "الكهف", "مريم", "طه", "الأنبياء", "الحج", "المؤمنون", "النور", "الفرقان", "الشعراء", "النمل", "القصص", "العنكبوت", "الروم", "لقمان", "السجدة", "الأحزاب", "سبأ", "فاطر", "يس", "الصافات", "ص", "الزمر", "غافر", "فصلت", "الشورى", "الزخرف", "الدخان", "الجاثية", "الأحقاف", "محمد", "الفتح", "الحجرات", "ق", "الذاريات", "الطور", "النجم", "القمر", "الرحمن", "الواقعة", "الحديد", "المجادلة", "الحشر", "الممتحنة", "الصف", "الجمعة", "المنافقون", "التغابن", "الطلاق", "التحريم", "الملك", "القلم", "الحاقة", "المعارج", "نوح", "الجن", "المزمل", "المدثر", "القيامة", "الإنسان", "المرسلات", "النبأ", "النازعات", "عبس", "التكوير", "الانفطار", "المطففين", "الانشقاق", "البروج", "الطارق", "الأعلى", "الغاشية", "الفجر", "البلد", "الشمس", "الليل", "الضحى", "الشرح", "التين", "العلق", "القدر", "البينة", "الزلزلة", "العاديات", "القارعة", "التكاثر", "العصر", "الهمزة", "الفيل", "قريش", "الماعون", "الكوثر", "الكافرون", "النصر", "المسد", "الإخلاص", "الفلق", "الناس"]
    static let en = ["Al-Fatihah", "Al-Baqarah", "Aal-Imran", "An-Nisa", "Al-Maidah", "Al-Anam", "Al-Araf", "Al-Anfal", "At-Tawbah", "Yunus", "Hud", "Yusuf", "Ar-Rad", "Ibrahim", "Al-Hijr", "An-Nahl", "Al-Isra", "Al-Kahf", "Maryam", "Taha", "Al-Anbiya", "Al-Hajj", "Al-Muminun", "An-Nur", "Al-Furqan", "Ash-Shuara", "An-Naml", "Al-Qasas", "Al-Ankabut", "Ar-Rum", "Luqman", "As-Sajdah", "Al-Ahzab", "Saba", "Fatir", "Ya-Sin", "As-Saffat", "Sad", "Az-Zumar", "Ghafir", "Fussilat", "Ash-Shura", "Az-Zukhruf", "Ad-Dukhan", "Al-Jathiyah", "Al-Ahqaf", "Muhammad", "Al-Fath", "Al-Hujurat", "Qaf", "Adh-Dhariyat", "At-Tur", "An-Najm", "Al-Qamar", "Ar-Rahman", "Al-Waqiah", "Al-Hadid", "Al-Mujadilah", "Al-Hashr", "Al-Mumtahanah", "As-Saff", "Al-Jumuah", "Al-Munafiqun", "At-Taghabun", "At-Talaq", "At-Tahrim", "Al-Mulk", "Al-Qalam", "Al-Haqqah", "Al-Maarij", "Nuh", "Al-Jinn", "Al-Muzzammil", "Al-Muddaththir", "Al-Qiyamah", "Al-Insan", "Al-Mursalat", "An-Naba", "An-Naziat", "Abasa", "At-Takwir", "Al-Infitar", "Al-Mutaffifin", "Al-Inshiqaq", "Al-Buruj", "At-Tariq", "Al-Ala", "Al-Ghashiyah", "Al-Fajr", "Al-Balad", "Ash-Shams", "Al-Layl", "Ad-Duha", "Ash-Sharh", "At-Tin", "Al-Alaq", "Al-Qadr", "Al-Bayyinah", "Az-Zalzalah", "Al-Adiyat", "Al-Qariah", "At-Takathur", "Al-Asr", "Al-Humazah", "Al-Fil", "Quraysh", "Al-Maun", "Al-Kawthar", "Al-Kafirun", "An-Nasr", "Al-Masad", "Al-Ikhlas", "Al-Falaq", "An-Nas"]

    static func name(_ n: Int) -> String {
        let i = max(1, min(114, n)) - 1
        return Lang.isEN ? en[i] : ar[i]
    }
}

// MARK: - القرّاء (من mp3quran.net — مكتبة مجانية مفتوحة)

struct Reciter: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let server: String
    var surahs: [Int]? = nil

    func url(_ surah: Int) -> URL? {
        URL(string: server + String(format: "%03d.mp3", surah))
    }
    func has(_ surah: Int) -> Bool { surahs?.contains(surah) ?? true }
}

enum Reciters {
    static let builtin: [Reciter] = [
        Reciter(id: 123, name: "مشاري العفاسي", server: "https://cdn.mp3quran.net/audio/mishary-alafasy/r1/"),
        Reciter(id: 102, name: "ماهر المعيقلي", server: "https://cdn.mp3quran.net/audio/maher-muaiqly/r1/"),
        Reciter(id: 112, name: "محمد صديق المنشاوي", server: "https://cdn.mp3quran.net/audio/muhammad-minshawi/r1/"),
        Reciter(id: 217, name: "بندر بليلة", server: "https://cdn.mp3quran.net/audio/bandar-baleela/r1/"),
        Reciter(id: 118, name: "محمود خليل الحصري", server: "https://cdn.mp3quran.net/audio/mahmoud-husary/r1/"),
        Reciter(id: 20, name: "إدريس أبكر", server: "https://cdn.mp3quran.net/audio/idrees-abkar/r1/"),
        Reciter(id: 300, name: "خالد الجليل", server: "https://cdn.mp3quran.net/audio/khalid-jalil/r1/"),
    ]

    static var selected: Reciter {
        get { AppGroup.defaults.data(forKey: "reciter").flatMap { try? JSONDecoder().decode(Reciter.self, from: $0) } ?? builtin[0] }
        set { AppGroup.defaults.set(try? JSONEncoder().encode(newValue), forKey: "reciter") }
    }

    /// القائمة المحفوظة (دون اتصال) — أو المضمّنة
    static var cached: [Reciter] {
        AppGroup.defaults.data(forKey: "reciters").flatMap { try? JSONDecoder().decode([Reciter].self, from: $0) } ?? builtin
    }

    /// القائمة الكاملة من الإنترنت (تُحفظ للمرة القادمة)
    static func load() async -> [Reciter] {
        if let d = AppGroup.defaults.data(forKey: "reciters"), let list = try? JSONDecoder().decode([Reciter].self, from: d),
           Date().timeIntervalSince1970 - AppGroup.defaults.double(forKey: "reciters_at") < 7 * 86400, !list.isEmpty {
            return list
        }
        let lang = Lang.isEN ? "eng" : "ar"
        guard let url = URL(string: "https://mp3quran.net/api/v3/reciters?language=\(lang)") else { return builtin }
        do {
            var req = URLRequest(url: url); req.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = j["reciters"] as? [[String: Any]] else { return builtin }
            var out: [Reciter] = []
            for r in arr {
                guard let id = r["id"] as? Int, let name = r["name"] as? String,
                      let moshaf = r["moshaf"] as? [[String: Any]] else { continue }
                // نفضّل المصحف الكامل (١١٤ سورة)
                let m = moshaf.first { ($0["surah_total"] as? Int) == 114 } ?? moshaf.first
                guard let m, let server = m["server"] as? String else { continue }
                let list = (m["surah_list"] as? String)?.split(separator: ",").compactMap { Int($0) }
                out.append(Reciter(id: id, name: name, server: server.hasSuffix("/") ? server : server + "/", surahs: list))
            }
            if out.isEmpty { return builtin }
            out.sort { $0.name < $1.name }
            AppGroup.defaults.set(try? JSONEncoder().encode(out), forKey: "reciters")
            AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: "reciters_at")
            return out
        } catch {
            return builtin
        }
    }
}

// MARK: - الإذاعات

struct Station: Codable, Identifiable, Hashable {
    var id: String { url }
    let name: String
    let url: String
    var country: String? = nil
    /// شعار الإذاعة وجودة البث (من دليل الإذاعات)
    var favicon: String? = nil
    var bitrate: Int? = nil
    var codec: String? = nil
    var tags: String? = nil
    /// روابط احتياطية للبث نفسه (تُجرَّب تلقائيًا إن تعطّل الرابط الأساسي)
    var alts: [String]? = nil

    /// علم الدولة من رمزها
    var flag: String {
        guard let c = country?.uppercased(), c.count == 2 else { return "" }
        return c.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
    }
    /// «128 kbps · MP3»
    var quality: String {
        var parts: [String] = []
        if let b = bitrate, b > 0 { parts.append("\(b) kbps") }
        if let c = codec, !c.isEmpty, c.uppercased() != "UNKNOWN" { parts.append(c.uppercased()) }
        return parts.joined(separator: " · ")
    }
}

/// الإذاعات الرسمية لكل دولة (تظهر أعلى صفحة الدولة دائمًا، حتى لو غابت عن دليل الإذاعات)
enum OfficialRadio {
    private static let kwik = "https://live.kwikmotion.com/"
    private static let rtt = "http://rtstream.tanitweb.com/"
    private static let rtn = "https://radio.radiotunisienne.tn/"

    private static func s(_ name: String, _ cc: String, _ url: String, _ alts: [String] = []) -> Station {
        Station(name: name, url: url, country: cc, alts: alts.isEmpty ? nil : alts)
    }

    // كل الروابط هنا مُختبرة من خادم البناء (تصل إلى مقاطع البث فعلًا) — ١٤ نوفمبر ٢٠٢٦
    static let byCountry: [String: [Station]] = [
        // هيئة الإذاعة والتلفزيون السعودية
        "SA": [
            // البث الرسمي لهيئة الإذاعة والتلفزيون (منصة «الأولى» aloula.sa)، وradiojar احتياطي فقط
            s("إذاعة القرآن الكريم", "SA", kwik + "sbrksaquranradiolive/srpksaquranradio/playlist.m3u8",
              [kwik + "sbrksaquranradiolive/ksaquranradio/chunks.m3u8", "https://stream.radiojar.com/0tpy1h0kxtzuv", "http://n01.radiojar.com/0tpy1h0kxtzuv"]),
            s("إذاعة الرياض", "SA", kwik + "sbrksariyadhradiolive/ksariyadhradio/chunks.m3u8",
              [kwik + "sbrksariyadhradiolive/srpksariyadhradio/playlist.m3u8"]),
            s("إذاعة جدة", "SA", kwik + "sbrksajeddahradiolive/ksajeddahradio/chunks.m3u8",
              [kwik + "sbrksajeddahradiolive/srpksajeddahradio/chunks.m3u8"]),
            s("إذاعة نداء الإسلام", "SA", kwik + "sbrksanedaradiolive/ksanedaradio/chunks.m3u8",
              [kwik + "sbrksanedaradiolive/srpksanedaradio/playlist.m3u8"]),
            s("إذاعة السعودية", "SA", kwik + "sbrksasaudiaradiolive/ksasaudiaradio/chunks.m3u8",
              [kwik + "sbrksasaudiaradiolive/srpksasaudiaradio/playlist.m3u8"]),
            s("إذاعة خزامى", "SA", kwik + "sbrksakhuzamaradiolive/khuzama/chunks.m3u8",
              [kwik + "sbrksakhuzamaradiolive/srpkhuzama/playlist.m3u8"]),
        ],
        // الإذاعة التونسية
        "TN": [
            s("الإذاعة الوطنية", "TN", rtn + "nationale", [rtt + "nationale"]),
            s("إذاعة RTCI", "TN", rtn + "rtci", [rtt + "rtci"]),
            s("إذاعة الشباب", "TN", rtn + "jeunes", [rtt + "jeunes"]),
            s("إذاعة تونس الثقافية", "TN", rtn + "culturelle", [rtt + "culturelle"]),
            s("إذاعة الزيتونة", "TN", rtn + "radiozaitouna"),
            s("إذاعة صفاقس", "TN", rtn + "sfax", [rtt + "sfax"]),
            s("إذاعة المنستير", "TN", rtn + "monastir", [rtt + "monastir"]),
            s("إذاعة الكاف", "TN", rtn + "kef", [rtt + "kef"]),
            s("إذاعة قفصة", "TN", rtn + "gafsa", [rtt + "gafsa"]),
            s("إذاعة تطاوين", "TN", rtn + "tataouine", [rtt + "tataouine"]),
        ],
    ]

    static func list(_ country: String) -> [Station] { byCountry[country.uppercased()] ?? [] }

    /// للبحث عن الروابط الاحتياطية لإذاعة محفوظة بالرابط فقط
    static func find(_ url: String) -> Station? {
        byCountry.values.lazy.flatMap { $0 }.first { $0.url == url || ($0.alts ?? []).contains(url) }
    }

    /// إذاعة محفوظة برابط قديم (مثل radiojar لإذاعة القرآن): تُشغَّل بالرابط الرسمي الحالي وروابطه الاحتياطية
    static func current(_ s: Station) -> Station {
        guard let o = find(s.url), o.url != s.url else { return s }
        return Station(name: s.name, url: o.url, country: s.country ?? o.country, favicon: s.favicon,
                       bitrate: s.bitrate, codec: s.codec, tags: s.tags, alts: o.alts)
    }
}

enum Stations {
    /// إذاعات مختارة (روابط عامة من mp3quran.net)
    static let builtin: [Station] = [
        Station(name: "إذاعة القرآن الكريم — السعودية", url: "https://live.kwikmotion.com/sbrksaquranradiolive/srpksaquranradio/playlist.m3u8", country: "SA"),
        Station(name: "أذكار الصباح", url: "https://backup.qurango.net/radio/athkar_sabah"),
        Station(name: "أذكار المساء", url: "https://backup.qurango.net/radio/athkar_masa"),
        Station(name: "تلاوات متنوعة لمختلف القرّاء", url: "https://backup.qurango.net/radio/mix"),
        Station(name: "المختصر في تفسير القرآن الكريم", url: "https://backup.qurango.net/radio/mukhtasartafsir"),
        Station(name: "سعود الشريم", url: "https://backup.qurango.net/radio/saud_alshuraim"),
        Station(name: "سعد الغامدي", url: "https://backup.qurango.net/radio/saad_alghamdi"),
        Station(name: "أحمد العجمي", url: "https://backup.qurango.net/radio/ahmad_alajmy"),
    ]

    /// الإذاعات المحفوظة (من البحث)
    static var saved: [Station] {
        get { AppGroup.defaults.data(forKey: "stations").flatMap { try? JSONDecoder().decode([Station].self, from: $0) } ?? [] }
        set { AppGroup.defaults.set(try? JSONEncoder().encode(newValue), forKey: "stations") }
    }
    static func isSaved(_ s: Station) -> Bool { saved.contains { $0.url == s.url } }
    static func toggle(_ s: Station) {
        var l = saved
        if let i = l.firstIndex(where: { $0.url == s.url }) { l.remove(at: i) } else { l.insert(s, at: 0) }
        saved = l
    }

    /// قائمة البكرة في الويدجت والتنقّل بالأمام والخلف: المفضلة ثم قوائم التشغيل (بلا تكرار)
    static var reel: [Station] {
        var seen = Set<String>()
        return (saved + Playlists.all.flatMap(\.stations)).filter { seen.insert($0.url).inserted }
    }

    /// آخر الإذاعات المشغّلة
    static var recent: [Station] {
        get { AppGroup.defaults.data(forKey: "stations_recent").flatMap { try? JSONDecoder().decode([Station].self, from: $0) } ?? [] }
        set { AppGroup.defaults.set(try? JSONEncoder().encode(Array(newValue.prefix(12))), forKey: "stations_recent") }
    }
    static func played(_ s: Station) {
        var l = recent
        l.removeAll { $0.url == s.url }
        l.insert(s, at: 0)
        recent = l
    }
    /// تحديث بيانات إذاعة محفوظة (مثل الاسم بعد التعديل)
    static func rename(_ s: Station, to name: String) {
        var l = saved
        guard let i = l.firstIndex(where: { $0.url == s.url }) else { return }
        var n = l[i]; n = Station(name: name, url: n.url, country: n.country, favicon: n.favicon, bitrate: n.bitrate, codec: n.codec, tags: n.tags)
        l[i] = n; saved = l
    }

    /// البحث في دليل الإذاعات المفتوح (radio-browser.info)
    static func search(_ q: String, country: String?, tag: String? = nil, language: String? = nil, limit: Int = 60, order: String = "clickcount") async -> [Station] {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.path = "/json/stations/search"
        var items = [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "hidebroken", value: "true"),
                     URLQueryItem(name: "order", value: order), URLQueryItem(name: "reverse", value: order == "name" ? "false" : "true")]
        if !q.isEmpty { items.append(URLQueryItem(name: "name", value: q)) }
        if let country, !country.isEmpty { items.append(URLQueryItem(name: "countrycode", value: country)) }
        if let tag, !tag.isEmpty { items.append(URLQueryItem(name: "tag", value: tag)) }
        if let language, !language.isEmpty { items.append(URLQueryItem(name: "language", value: language)) }
        comps.queryItems = items
        for host in ["de1.api.radio-browser.info", "de2.api.radio-browser.info", "fi1.api.radio-browser.info", "nl1.api.radio-browser.info"] {
            comps.host = host
            guard let url = comps.url else { continue }
            var req = URLRequest(url: url); req.timeoutInterval = 10
            req.setValue("Rafiqi/1.2", forHTTPHeaderField: "User-Agent")
            guard let res = try? await URLSession.shared.data(for: req),
                  let arr = (try? JSONSerialization.jsonObject(with: res.0)) as? [[String: Any]] else { continue }
            var seen = Set<String>()
            return arr.compactMap { s in
                guard let name = (s["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                      let u = (s["url_resolved"] as? String) ?? (s["url"] as? String), !u.isEmpty, !seen.contains(u) else { return nil }
                seen.insert(u)
                let fav = (s["favicon"] as? String).flatMap { $0.hasPrefix("https://") ? $0 : nil }
                return Station(name: name, url: u, country: s["countrycode"] as? String, favicon: fav,
                               bitrate: s["bitrate"] as? Int, codec: s["codec"] as? String, tags: s["tags"] as? String)
            }
        }
        return []
    }
}

// MARK: - أوامر التشغيل من الويدجت (تُنفَّذ داخل التطبيق)

enum MediaBridge {
    /// يضبطه التطبيق عند تشغيله؛ وفي امتداد الويدجت يبقى فارغًا
    /// (الأمر، المصدر — فارغ = الشغّال حاليًا)
    static var handler: ((String, String) async -> Void)? = nil
}

struct MediaControlIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "التحكم في التشغيل"
    static let isDiscoverable = false
    @Parameter(title: "الأمر") var action: String
    @Parameter(title: "المصدر") var source: String
    init() {}
    init(_ action: String, source: String = "") {
        self.action = action
        self.source = source
    }
    func perform() async throws -> some IntentResult {
        if let h = MediaBridge.handler { await h(action, source) }
        return .result()
    }
}

/// مصدر ويدجت الوسائط (من «تعديل الأداة»)
enum MediaSourceOpt: String, AppEnum {
    case current, quran, radio, music
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "المصدر"
    static let caseDisplayRepresentations: [MediaSourceOpt: DisplayRepresentation] = [
        .current: "قيد التشغيل حاليًا", .quran: "القرآن الكريم", .radio: "الإذاعة", .music: "Apple Music",
    ]
}


private struct MediaSrcKey: EnvironmentKey { static let defaultValue = "" }
extension EnvironmentValues {
    /// مصدر ويدجت الوسائط (فارغ = الشغّال حاليًا) — تستخدمه الأزرار
    var mediaSource: String {
        get { self[MediaSrcKey.self] }
        set { self[MediaSrcKey.self] = newValue }
    }
}

/// أنواع ويدجت الوسائط (لتحديثها عند تغيّر التشغيل)
enum MediaKinds {
    /// ويدجت الوسائط صارت داخل ويدجت رفيقي بالمقاس
    static func reload() { RafiqiKinds.reload() }
}

// MARK: - قوائم تشغيل الإذاعات (يصنعها المستخدم، وأكثر من قائمة)

struct RadioPlaylist: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var stations: [Station]
}

enum Playlists {
    private static var d: UserDefaults { AppGroup.defaults }

    /// أول مرة: قائمة «إذاعات مختارة» فيها الإذاعات المدمجة (لا يضيع شيء مما كان)
    static var all: [RadioPlaylist] {
        get {
            if let data = d.data(forKey: "radio_playlists"),
               let l = try? JSONDecoder().decode([RadioPlaylist].self, from: data) { return l }
            return [RadioPlaylist(id: "default", name: Lang.isEN ? "Selected stations" : "إذاعات مختارة", stations: Stations.builtin)]
        }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "radio_playlists") }
    }

    static func get(_ id: String) -> RadioPlaylist? { all.first { $0.id == id } }

    @discardableResult
    static func create(_ name: String) -> String {
        let id = UUID().uuidString
        all = all + [RadioPlaylist(id: id, name: name, stations: [])]
        return id
    }
    static func rename(_ id: String, _ name: String) { update(id) { $0.name = name } }
    static func delete(_ id: String) { all = all.filter { $0.id != id } }
    static func contains(_ id: String, _ s: Station) -> Bool { get(id)?.stations.contains { $0.url == s.url } ?? false }
    static func add(_ s: Station, to id: String) {
        update(id) { p in if !p.stations.contains(where: { $0.url == s.url }) { p.stations.append(s) } }
    }
    static func remove(_ url: String, from id: String) { update(id) { $0.stations.removeAll { $0.url == url } } }
    static func setStations(_ id: String, _ l: [Station]) { update(id) { $0.stations = l } }

    private static func update(_ id: String, _ f: (inout RadioPlaylist) -> Void) {
        var l = all
        guard let i = l.firstIndex(where: { $0.id == id }) else { return }
        f(&l[i]); all = l
    }
}
