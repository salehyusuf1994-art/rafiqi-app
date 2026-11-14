import Foundation
import SwiftUI
import WidgetKit
import AppIntents
import UIKit
import UserNotifications
import ImageIO

// MARK: - المباريات: البيانات من ESPN (مجاني بلا حساب ولا مفتاح)

typealias JObj = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func o(_ k: String) -> JObj? { self[k] as? JObj }
    func a(_ k: String) -> [JObj] { (self[k] as? [JObj]) ?? [] }
    func s(_ k: String) -> String? {
        if let v = self[k] as? String { return v }
        if let v = self[k] as? NSNumber { return v.stringValue }
        return nil
    }
    func d(_ k: String) -> Double? {
        if let v = self[k] as? NSNumber { return v.doubleValue }
        if let v = self[k] as? String { return Double(v) }
        return nil
    }
    func b(_ k: String) -> Bool { (self[k] as? Bool) ?? ((self[k] as? NSNumber)?.boolValue ?? false) }
}

// ── البطولات (كل الرموز متحقَّق منها في ESPN) ──
enum LKind: String { case league, cup, clubs, nations }

/// مجموعة بطولات حسب المنطقة (لقوائم الاختيار)
struct LGroup: Identifiable {
    let id: String
    let ar: String
    let en: String
    var name: String { Lang.isEN ? en : ar }
}

struct SLeague: Identifiable, Hashable {
    let id: String
    let ar: String
    let en: String
    let hasTable: Bool
    var kind: LKind = .league
    var group: String = ""
    var name: String { Lang.isEN ? en : ar }
    var isNations: Bool { kind == .nations }
}

enum Leagues {
    static let groups: [LGroup] = [
        LGroup(id: "saudi", ar: "السعودية والخليج", en: "Saudi Arabia & Gulf"),
        LGroup(id: "arab", ar: "الدول العربية", en: "Arab Countries"),
        LGroup(id: "world", ar: "العالم", en: "World"),
        LGroup(id: "asia", ar: "آسيا", en: "Asia"),
        LGroup(id: "africa", ar: "أفريقيا", en: "Africa"),
        LGroup(id: "europe", ar: "أوروبا: البطولات القارية", en: "Europe: Continental"),
        LGroup(id: "eurLeagues", ar: "أوروبا: الدوريات", en: "Europe: Leagues"),
        LGroup(id: "eurCups", ar: "أوروبا: الكؤوس المحلية", en: "Europe: Domestic Cups"),
        LGroup(id: "americas", ar: "الأمريكتان", en: "Americas"),
    ]
    static let all: [SLeague] = [
        // السعودية والخليج
        SLeague(id: "ksa.1", ar: "دوري روشن السعودي", en: "Saudi Pro League", hasTable: true, kind: .league, group: "saudi"),
        SLeague(id: "ksa.kings.cup", ar: "كأس الملك", en: "King's Cup", hasTable: false, kind: .cup, group: "saudi"),
        SLeague(id: "global.gulf_cup", ar: "كأس الخليج العربي", en: "Arabian Gulf Cup", hasTable: true, kind: .nations, group: "saudi"),
        // الدول العربية
        SLeague(id: "ls.egy.1", ar: "الدوري المصري", en: "Egyptian Premier League", hasTable: true, kind: .league, group: "arab"),
        SLeague(id: "ls.egy.cup", ar: "كأس مصر", en: "Egypt Cup", hasTable: false, kind: .cup, group: "arab"),
        SLeague(id: "ls.uae.1", ar: "الدوري الإماراتي", en: "UAE Pro League", hasTable: true, kind: .league, group: "arab"),
        SLeague(id: "ls.uae.cup", ar: "كأس رئيس الدولة الإماراتي", en: "UAE President's Cup", hasTable: false, kind: .cup, group: "arab"),
        SLeague(id: "ls.qat.1", ar: "الدوري القطري", en: "Qatar Stars League", hasTable: true, kind: .league, group: "arab"),
        SLeague(id: "ls.mar.1", ar: "الدوري المغربي", en: "Botola Pro", hasTable: true, kind: .league, group: "arab"),
        SLeague(id: "ls.tun.1", ar: "الدوري التونسي", en: "Tunisian Ligue 1", hasTable: true, kind: .league, group: "arab"),
        SLeague(id: "ls.alg.1", ar: "الدوري الجزائري", en: "Algerian Ligue 1", hasTable: true, kind: .league, group: "arab"),
        SLeague(id: "ls.kuw.1", ar: "الدوري الكويتي", en: "Kuwait Premier League", hasTable: true, kind: .league, group: "arab"),
        SLeague(id: "ls.irq.1", ar: "دوري نجوم العراق", en: "Iraq Stars League", hasTable: true, kind: .league, group: "arab"),
        SLeague(id: "ls.jor.1", ar: "الدوري الأردني", en: "Jordanian Pro League", hasTable: true, kind: .league, group: "arab"),
        SLeague(id: "ls.omn.1", ar: "الدوري العُماني", en: "Oman Professional League", hasTable: true, kind: .league, group: "arab"),
        SLeague(id: "ls.arab.cup", ar: "كأس العرب", en: "FIFA Arab Cup", hasTable: true, kind: .nations, group: "arab"),
        // العالم
        SLeague(id: "fifa.world", ar: "كأس العالم", en: "FIFA World Cup", hasTable: true, kind: .nations, group: "world"),
        SLeague(id: "fifa.cwc", ar: "كأس العالم للأندية", en: "FIFA Club World Cup", hasTable: true, kind: .clubs, group: "world"),
        SLeague(id: "fifa.friendly", ar: "مباريات دولية ودية", en: "International Friendlies", hasTable: false, kind: .nations, group: "world"),
        SLeague(id: "global.finalissima", ar: "الفيناليسيما", en: "Finalissima", hasTable: false, kind: .nations, group: "world"),
        SLeague(id: "fifa.olympics", ar: "كرة القدم الأولمبية", en: "Olympic Football", hasTable: true, kind: .nations, group: "world"),
        SLeague(id: "fifa.world.u20", ar: "كأس العالم للشباب", en: "FIFA U-20 World Cup", hasTable: true, kind: .nations, group: "world"),
        SLeague(id: "fifa.wwc", ar: "كأس العالم للسيدات", en: "FIFA Women's World Cup", hasTable: true, kind: .nations, group: "world"),
        // آسيا
        SLeague(id: "afc.champions", ar: "دوري أبطال آسيا للنخبة", en: "AFC Champions League Elite", hasTable: true, kind: .clubs, group: "asia"),
        SLeague(id: "afc.cup", ar: "دوري أبطال آسيا ٢", en: "AFC Champions League Two", hasTable: true, kind: .clubs, group: "asia"),
        SLeague(id: "afc.asian.cup", ar: "كأس آسيا", en: "AFC Asian Cup", hasTable: true, kind: .nations, group: "asia"),
        SLeague(id: "fifa.worldq.afc", ar: "تصفيات كأس العالم: آسيا", en: "World Cup Qualifying: Asia", hasTable: true, kind: .nations, group: "asia"),
        SLeague(id: "aff.championship", ar: "بطولة آسيان", en: "ASEAN Championship", hasTable: true, kind: .nations, group: "asia"),
        SLeague(id: "jpn.1", ar: "الدوري الياباني", en: "J1 League", hasTable: true, kind: .league, group: "asia"),
        SLeague(id: "chn.1", ar: "الدوري الصيني", en: "Chinese Super League", hasTable: true, kind: .league, group: "asia"),
        SLeague(id: "aus.1", ar: "الدوري الأسترالي", en: "A-League Men", hasTable: true, kind: .league, group: "asia"),
        SLeague(id: "ind.1", ar: "الدوري الهندي", en: "Indian Super League", hasTable: true, kind: .league, group: "asia"),
        // أفريقيا
        SLeague(id: "caf.champions", ar: "دوري أبطال أفريقيا", en: "CAF Champions League", hasTable: true, kind: .clubs, group: "africa"),
        SLeague(id: "caf.confed", ar: "كأس الكونفدرالية الأفريقية", en: "CAF Confederation Cup", hasTable: true, kind: .clubs, group: "africa"),
        SLeague(id: "caf.nations", ar: "كأس أمم أفريقيا", en: "Africa Cup of Nations", hasTable: true, kind: .nations, group: "africa"),
        SLeague(id: "caf.nations_qual", ar: "تصفيات كأس أمم أفريقيا", en: "AFCON Qualifying", hasTable: true, kind: .nations, group: "africa"),
        SLeague(id: "fifa.worldq.caf", ar: "تصفيات كأس العالم: أفريقيا", en: "World Cup Qualifying: Africa", hasTable: true, kind: .nations, group: "africa"),
        SLeague(id: "caf.championship", ar: "بطولة أمم أفريقيا للمحليين", en: "African Nations Championship", hasTable: true, kind: .nations, group: "africa"),
        SLeague(id: "rsa.1", ar: "الدوري الجنوب أفريقي", en: "South African Premiership", hasTable: true, kind: .league, group: "africa"),
        // أوروبا: البطولات القارية
        SLeague(id: "uefa.champions", ar: "دوري أبطال أوروبا", en: "UEFA Champions League", hasTable: true, kind: .clubs, group: "europe"),
        SLeague(id: "uefa.europa", ar: "الدوري الأوروبي", en: "UEFA Europa League", hasTable: true, kind: .clubs, group: "europe"),
        SLeague(id: "uefa.europa.conf", ar: "دوري المؤتمر الأوروبي", en: "UEFA Conference League", hasTable: true, kind: .clubs, group: "europe"),
        SLeague(id: "uefa.super_cup", ar: "كأس السوبر الأوروبي", en: "UEFA Super Cup", hasTable: false, kind: .clubs, group: "europe"),
        SLeague(id: "uefa.euro", ar: "كأس أمم أوروبا", en: "UEFA Euro", hasTable: true, kind: .nations, group: "europe"),
        SLeague(id: "uefa.euroq", ar: "تصفيات كأس أمم أوروبا", en: "Euro Qualifying", hasTable: true, kind: .nations, group: "europe"),
        SLeague(id: "uefa.nations", ar: "دوري الأمم الأوروبية", en: "UEFA Nations League", hasTable: true, kind: .nations, group: "europe"),
        SLeague(id: "fifa.worldq.uefa", ar: "تصفيات كأس العالم: أوروبا", en: "World Cup Qualifying: Europe", hasTable: true, kind: .nations, group: "europe"),
        // أوروبا: الدوريات
        SLeague(id: "eng.1", ar: "الدوري الإنجليزي", en: "Premier League", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "esp.1", ar: "الدوري الإسباني", en: "LaLiga", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "ita.1", ar: "الدوري الإيطالي", en: "Serie A", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "ger.1", ar: "الدوري الألماني", en: "Bundesliga", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "fra.1", ar: "الدوري الفرنسي", en: "Ligue 1", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "por.1", ar: "الدوري البرتغالي", en: "Liga Portugal", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "ned.1", ar: "الدوري الهولندي", en: "Eredivisie", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "tur.1", ar: "الدوري التركي", en: "Süper Lig", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "bel.1", ar: "الدوري البلجيكي", en: "Belgian Pro League", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "sco.1", ar: "الدوري الإسكتلندي", en: "Scottish Premiership", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "gre.1", ar: "الدوري اليوناني", en: "Greek Super League", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "aut.1", ar: "الدوري النمساوي", en: "Austrian Bundesliga", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "den.1", ar: "الدوري الدنماركي", en: "Danish Superliga", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "swe.1", ar: "الدوري السويدي", en: "Allsvenskan", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "nor.1", ar: "الدوري النرويجي", en: "Eliteserien", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "rus.1", ar: "الدوري الروسي", en: "Russian Premier League", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "eng.2", ar: "دوري البطولة الإنجليزية", en: "EFL Championship", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "esp.2", ar: "الدرجة الثانية الإسبانية", en: "LaLiga 2", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "ita.2", ar: "الدرجة الثانية الإيطالية", en: "Serie B", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "ger.2", ar: "الدرجة الثانية الألمانية", en: "2. Bundesliga", hasTable: true, kind: .league, group: "eurLeagues"),
        SLeague(id: "fra.2", ar: "الدرجة الثانية الفرنسية", en: "Ligue 2", hasTable: true, kind: .league, group: "eurLeagues"),
        // أوروبا: الكؤوس المحلية
        SLeague(id: "eng.fa", ar: "كأس الاتحاد الإنجليزي", en: "FA Cup", hasTable: false, kind: .cup, group: "eurCups"),
        SLeague(id: "eng.league_cup", ar: "كأس الرابطة الإنجليزية", en: "EFL Cup", hasTable: false, kind: .cup, group: "eurCups"),
        SLeague(id: "eng.charity", ar: "درع المجتمع", en: "Community Shield", hasTable: false, kind: .cup, group: "eurCups"),
        SLeague(id: "esp.copa_del_rey", ar: "كأس ملك إسبانيا", en: "Copa del Rey", hasTable: false, kind: .cup, group: "eurCups"),
        SLeague(id: "esp.super_cup", ar: "كأس السوبر الإسباني", en: "Spanish Super Cup", hasTable: false, kind: .cup, group: "eurCups"),
        SLeague(id: "ita.coppa_italia", ar: "كأس إيطاليا", en: "Coppa Italia", hasTable: false, kind: .cup, group: "eurCups"),
        SLeague(id: "ita.super_cup", ar: "كأس السوبر الإيطالي", en: "Italian Super Cup", hasTable: false, kind: .cup, group: "eurCups"),
        SLeague(id: "ger.dfb_pokal", ar: "كأس ألمانيا", en: "DFB-Pokal", hasTable: false, kind: .cup, group: "eurCups"),
        SLeague(id: "ger.super_cup", ar: "كأس السوبر الألماني", en: "German Super Cup", hasTable: false, kind: .cup, group: "eurCups"),
        SLeague(id: "fra.coupe_de_france", ar: "كأس فرنسا", en: "Coupe de France", hasTable: false, kind: .cup, group: "eurCups"),
        SLeague(id: "fra.super_cup", ar: "كأس الأبطال الفرنسي", en: "Trophée des Champions", hasTable: false, kind: .cup, group: "eurCups"),
        SLeague(id: "por.taca.portugal", ar: "كأس البرتغال", en: "Taça de Portugal", hasTable: false, kind: .cup, group: "eurCups"),
        SLeague(id: "ned.cup", ar: "كأس هولندا", en: "KNVB Cup", hasTable: false, kind: .cup, group: "eurCups"),
        SLeague(id: "sco.tennents", ar: "كأس إسكتلندا", en: "Scottish Cup", hasTable: false, kind: .cup, group: "eurCups"),
        // الأمريكتان
        SLeague(id: "conmebol.libertadores", ar: "كأس ليبرتادوريس", en: "Copa Libertadores", hasTable: true, kind: .clubs, group: "americas"),
        SLeague(id: "conmebol.sudamericana", ar: "كأس سود أمريكانا", en: "Copa Sudamericana", hasTable: true, kind: .clubs, group: "americas"),
        SLeague(id: "conmebol.america", ar: "كوبا أمريكا", en: "Copa América", hasTable: true, kind: .nations, group: "americas"),
        SLeague(id: "fifa.worldq.conmebol", ar: "تصفيات كأس العالم: أمريكا الجنوبية", en: "World Cup Qualifying: South America", hasTable: true, kind: .nations, group: "americas"),
        SLeague(id: "concacaf.champions", ar: "كأس أبطال الكونكاكاف", en: "Concacaf Champions Cup", hasTable: false, kind: .clubs, group: "americas"),
        SLeague(id: "concacaf.gold", ar: "الكأس الذهبية", en: "Concacaf Gold Cup", hasTable: true, kind: .nations, group: "americas"),
        SLeague(id: "fifa.worldq.concacaf", ar: "تصفيات كأس العالم: الكونكاكاف", en: "World Cup Qualifying: Concacaf", hasTable: true, kind: .nations, group: "americas"),
        SLeague(id: "concacaf.leagues.cup", ar: "كأس الدوريات", en: "Leagues Cup", hasTable: false, kind: .clubs, group: "americas"),
        SLeague(id: "bra.1", ar: "الدوري البرازيلي", en: "Brasileirão", hasTable: true, kind: .league, group: "americas"),
        SLeague(id: "arg.1", ar: "الدوري الأرجنتيني", en: "Argentine Primera División", hasTable: true, kind: .league, group: "americas"),
        SLeague(id: "usa.1", ar: "الدوري الأمريكي", en: "MLS", hasTable: true, kind: .league, group: "americas"),
        SLeague(id: "mex.1", ar: "الدوري المكسيكي", en: "Liga MX", hasTable: true, kind: .league, group: "americas"),
    ]

    /// رمز «المنتخبات الوطنية» عند اختيار منتخب فريقًا لك
    static let nationsKey = "fifa.friendly"

    static func get(_ id: String) -> SLeague {
        if let l = all.first(where: { $0.id == id }) { return l }
        let n = learned[id] ?? id
        return SLeague(id: id, ar: n, en: n, hasTable: false, kind: .cup, group: "")
    }
    static func inGroup(_ g: String) -> [SLeague] { all.filter { $0.group == g } }

    /// أسماء بطولات غير موجودة في القائمة (من ESPN نفسها)
    private static let learnedKey = "sp_league_names"
    static var learned: [String: String] { (AppGroup.defaults.dictionary(forKey: learnedKey) as? [String: String]) ?? [:] }
    static func learn(_ id: String, _ name: String?) {
        guard let name, !name.isEmpty, !id.isEmpty, !all.contains(where: { $0.id == id }) else { return }
        var d = learned
        guard d[id] != name else { return }
        d[id] = name
        AppGroup.defaults.set(d, forKey: learnedKey)
    }

    /// القارة من رمز البطولة (لاختيار بطولات المنتخب)
    static func confed(_ id: String) -> String? {
        if id.hasPrefix("afc.") || id.hasPrefix("aff.") || id == "fifa.worldq.afc" || id == "global.gulf_cup" { return "afc" }
        if id.hasPrefix("caf.") || id == "fifa.worldq.caf" { return "caf" }
        if id.hasPrefix("uefa.") || id == "fifa.worldq.uefa" { return "uefa" }
        if id.hasPrefix("conmebol.") || id == "fifa.worldq.conmebol" { return "conmebol" }
        if id.hasPrefix("concacaf.") || id == "fifa.worldq.concacaf" { return "concacaf" }
        return nil
    }

    /// البطولات الإضافية اللي تُبحث فيها مباريات الفريق القادمة (الكؤوس والقارية)
    /// `seen`: بطولات لعب فيها الفريق هذا الموسم (من جدوله الشامل)
    static func extras(for league: String, seen: Set<String> = []) -> [String] {
        let uefa = ["uefa.champions", "uefa.europa", "uefa.europa.conf", "uefa.super_cup"]
        var x: [String]
        switch league {
        case "ksa.1": x = ["ksa.kings.cup", "afc.champions", "afc.cup", "fifa.cwc"]
        case "eng.1": x = ["eng.fa", "eng.league_cup", "eng.charity", "fifa.cwc"] + uefa
        case "esp.1": x = ["esp.copa_del_rey", "esp.super_cup", "fifa.cwc"] + uefa
        case "ita.1": x = ["ita.coppa_italia", "ita.super_cup", "fifa.cwc"] + uefa
        case "ger.1": x = ["ger.dfb_pokal", "ger.super_cup", "fifa.cwc"] + uefa
        case "fra.1": x = ["fra.coupe_de_france", "fra.super_cup", "fifa.cwc"] + uefa
        case "por.1": x = ["por.taca.portugal", "fifa.cwc"] + uefa
        case "ned.1": x = ["ned.cup"] + uefa
        case "sco.1": x = ["sco.tennents"] + uefa
        case "tur.1", "bel.1", "gre.1", "aut.1", "den.1", "swe.1", "nor.1", "rus.1": x = uefa
        case "eng.2": x = ["eng.fa", "eng.league_cup"]
        case "esp.2": x = ["esp.copa_del_rey"]
        case "ita.2": x = ["ita.coppa_italia"]
        case "ger.2": x = ["ger.dfb_pokal"]
        case "fra.2": x = ["fra.coupe_de_france"]
        case "jpn.1", "chn.1", "aus.1", "ind.1": x = ["afc.champions", "afc.cup"]
        case "rsa.1": x = ["caf.champions", "caf.confed"]
        case "bra.1", "arg.1": x = ["conmebol.libertadores", "conmebol.sudamericana", "fifa.cwc"]
        case "usa.1", "mex.1": x = ["concacaf.champions", "concacaf.leagues.cup", "fifa.cwc"]
        case "ls.egy.1": x = ["ls.egy.cup"]
        case "ls.uae.1": x = ["ls.uae.cup"]
        case nationsKey:
            // بطولات المنتخبات: العالمية دائمًا، والقارية حسب قارة المنتخب (إن عُرفت)
            let confs = Set(seen.compactMap { confed($0) })
            x = all.filter { $0.isNations && $0.id != nationsKey && !LS.owns($0.id) && (confed($0.id) == nil || confs.isEmpty || confs.contains(confed($0.id)!)) }.map { $0.id }
        default: x = []
        }
        for s in seen where s != league && !x.contains(s) { x.append(s) }
        return x.filter { $0 != league }
    }
}

/// اسم المجموعة بالعربي (Group A → المجموعة A)
func sGroupName(_ g: String) -> String {
    if Lang.isEN { return g }
    if g.hasPrefix("Group ") { return LF("المجموعة %@", String(g.dropFirst(6))) }
    switch g {
    case "East Region", "East": return L("منطقة الشرق")
    case "West Region", "West": return L("منطقة الغرب")
    case "League Phase", "League Stage": return L("مرحلة الدوري")
    default: return g
    }
}

// ── أسماء الفرق بالعربي ──
enum SNames {
    static let map: [String: String] = [
        // السعودية
        "Al Hilal": "الهلال", "Al Nassr": "النصر", "Al Ittihad": "الاتحاد", "Al Ahli": "الأهلي",
        "Al Shabab": "الشباب", "Al Ettifaq": "الاتفاق", "Al Fateh": "الفتح", "Al Taawoun": "التعاون",
        "Al Qadsiah": "القادسية", "Al Khaleej": "الخليج", "Al Fayha": "الفيحاء", "Al Hazem": "الحزم",
        "Al Riyadh": "الرياض", "Al Kholood": "الخلود", "Abha": "أبها", "Al Diriyah": "الدرعية",
        "Al Faisaly": "الفيصلي", "Neom SC": "نيوم", "NEOM SC": "نيوم", "Al Okhdood": "الأخدود", "Al Raed": "الرائد",
        "Al Wehda": "الوحدة", "Damac": "ضمك", "Al Orobah": "العروبة", "Al Najma": "النجمة", "Al Ohod": "أحد",
        "Al Akhdoud": "الأخدود", "Al Tai": "الطائي", "Al Batin": "الباطن", "Al Adalah": "العدالة",
        "Al Jabalain": "الجبلين", "Al Ula": "العلا", "Al Zulfi": "الزلفي", "Al Arabi": "العربي",
        // آسيا
        "Al Sadd": "السد", "Al Duhail": "الدحيل", "Al Gharafa": "الغرافة", "Al Rayyan": "الريان",
        "Al Wahda": "الوحدة الإماراتي", "Al Ain": "العين", "Shabab Al Ahli": "شباب الأهلي", "Sharjah": "الشارقة",
        "Al Wasl": "الوصل", "Persepolis": "بيرسبوليس", "Esteghlal": "استقلال", "Tractor": "تراكتور",
        "Ulsan HD": "أولسان", "Pohang Steelers": "بوهانغ", "Vissel Kobe": "فيسيل كوبي",
        "Yokohama F. Marinos": "يوكوهاما", "Kawasaki Frontale": "كاواساكي", "Shanghai Port": "شنغهاي بورت",
        "Buriram United": "بوريرام", "Al Shorta": "الشرطة", "Pakhtakor": "باختاكور", "Nasaf": "نسف",
        // إنجلترا
        "Manchester City": "م. سيتي", "Manchester United": "م. يونايتد", "Liverpool": "ليفربول", "Arsenal": "أرسنال",
        "Chelsea": "تشيلسي", "Tottenham Hotspur": "توتنهام", "Newcastle United": "نيوكاسل", "Aston Villa": "أستون فيلا",
        "Brighton & Hove Albion": "برايتون", "West Ham United": "وست هام", "Crystal Palace": "كريستال بالاس",
        "Brentford": "برينتفورد", "AFC Bournemouth": "بورنموث", "Fulham": "فولهام", "Everton": "إيفرتون",
        "Wolverhampton Wanderers": "وولفرهامبتون", "Nottingham Forest": "نوتنغهام", "Leeds United": "ليدز",
        "Sunderland": "سندرلاند", "Burnley": "بيرنلي", "Hull City": "هال سيتي", "Leicester City": "ليستر",
        "Southampton": "ساوثهامبتون", "Ipswich Town": "إبسويتش",
        // إسبانيا
        "Barcelona": "برشلونة", "Real Madrid": "ر. مدريد", "Atlético Madrid": "أتلتيكو", "Atletico Madrid": "أتلتيكو",
        "Sevilla": "إشبيلية", "Real Betis": "بيتيس", "Villarreal": "فياريال", "Real Sociedad": "ريال سوسيداد",
        "Athletic Club": "أتلتيك بلباو", "Valencia": "فالنسيا", "Girona": "جيرونا", "Celta Vigo": "سيلتا فيغو",
        "Osasuna": "أوساسونا", "Getafe": "خيتافي", "Mallorca": "مايوركا", "Rayo Vallecano": "رايو فاليكانو",
        "Espanyol": "إسبانيول", "Alavés": "ألافيس", "Levante": "ليفانتي", "Elche": "إلتشي", "Real Oviedo": "أوفييدو",
        // ألمانيا
        "Bayern Munich": "ب. ميونخ", "Borussia Dortmund": "دورتموند", "Bayer Leverkusen": "ليفركوزن",
        "RB Leipzig": "لايبزيغ", "Eintracht Frankfurt": "فرانكفورت", "VfB Stuttgart": "شتوتغارت",
        "Borussia Mönchengladbach": "مونشنغلادباخ", "VfL Wolfsburg": "فولفسبورغ", "SC Freiburg": "فرايبورغ",
        "Werder Bremen": "فيردر بريمن", "Union Berlin": "يونيون برلين", "Hoffenheim": "هوفنهايم",
        "TSG Hoffenheim": "هوفنهايم", "Mainz": "ماينتس", "FC Augsburg": "أوغسبورغ", "Hamburg SV": "هامبورغ", "FC Cologne": "كولن",
        // إيطاليا
        "Juventus": "يوفنتوس", "Internazionale": "إنتر", "Inter Milan": "إنتر", "AC Milan": "ميلان", "Napoli": "نابولي",
        "AS Roma": "روما", "Lazio": "لاتسيو", "Atalanta": "أتالانتا", "Fiorentina": "فيورنتينا", "Bologna": "بولونيا",
        "Torino": "تورينو", "Como": "كومو",
        // فرنسا
        "Paris Saint-Germain": "باريس", "Marseille": "مارسيليا", "Monaco": "موناكو", "AS Monaco": "موناكو",
        "Lyon": "ليون", "Lille": "ليل", "Nice": "نيس", "Lens": "لانس", "Rennes": "رين",
        // أوروبا
        "Ajax": "أياكس", "PSV Eindhoven": "آيندهوفن", "Feyenoord": "فينورد", "Benfica": "بنفيكا", "Porto": "بورتو",
        "Sporting CP": "سبورتنغ", "Galatasaray": "غ. سراي", "Fenerbahce": "فنربخشة", "Besiktas": "بشكتاش",
        "Celtic": "سلتيك", "Rangers": "رينجرز", "Club Brugge": "كلوب بروج", "Shakhtar Donetsk": "شاختار",
        "Red Bull Salzburg": "سالزبورغ", "Copenhagen": "كوبنهاغن", "Olympiacos": "أولمبياكوس",
        "Slavia Prague": "سلافيا براغ", "Bodo/Glimt": "بودو غليمت", "Qarabag": "قره باغ", "Pafos": "بافوس",
        "Kairat Almaty": "كايرات", "Union St.-Gilloise": "يونيون سان جيلواز", "Athletic Bilbao": "أتلتيك بلباو",
        "Coventry City": "كوفنتري", "Middlesbrough": "ميدلزبره", "Norwich City": "نوريتش", "West Bromwich Albion": "وست بروميتش",
        "Sheffield United": "شيفيلد يونايتد", "Watford": "واتفورد", "Stoke City": "ستوك سيتي",
        "Pisa": "بيزا", "Cagliari": "كالياري", "Genoa": "جنوى", "Udinese": "أودينيزي", "Lecce": "ليتشي",
        "Parma": "بارما", "Hellas Verona": "فيرونا", "Sassuolo": "ساسولو", "Cremonese": "كريمونيزي",
        "Strasbourg": "ستراسبورغ", "Nantes": "نانت", "Toulouse": "تولوز", "Brest": "بريست", "Auxerre": "أوكسير",
        "Angers": "أنجيه", "Le Havre": "لوهافر", "Lorient": "لوريان", "Metz": "ميتز", "Paris FC": "باريس إف سي",
        "St. Pauli": "سانت باولي", "1. FC Heidenheim 1846": "هايدنهايم", "Heidenheim": "هايدنهايم",
        "Braga": "براغا", "AZ Alkmaar": "ألكمار", "FC Twente": "تفينتي", "Trabzonspor": "طرابزون سبور",
        "Anderlecht": "أندرلخت", "Dinamo Zagreb": "دينامو زغرب", "Red Star Belgrade": "النجم الأحمر",
        "Sparta Prague": "سبارتا براغ", "PAOK Salonika": "باوك", "PAOK": "باوك", "Panathinaikos": "باناثينايكوس",
        "AEK Athens": "أيك أثينا", "Zenit St Petersburg": "زينيت", "Ferencvaros": "فيرينتسفاروش",
        // آسيا والخليج
        "Al Wakrah": "الوكرة", "Qatar SC": "قطر", "Al Nasr": "النصر الإماراتي", "Al Jazira": "الجزيرة",
        "Al Kuwait": "الكويت", "Al Qadsia": "القادسية الكويتي", "Al Zawraa": "الزوراء",
        "Al Quwa Al Jawiya": "القوة الجوية", "Al Wehdat": "الوحدات", "Sepahan": "سباهان", "Foolad": "فولاد",
        "Johor Darul Ta'zim": "جوهور دار التعظيم", "Shandong Taishan": "شاندونغ", "Shanghai Shenhua": "شنغهاي شينهوا",
        "Beijing Guoan": "بكين غوان", "Machida Zelvia": "ماتشيدا", "Sanfrecce Hiroshima": "سانفريتشي هيروشيما",
        "Kashiwa Reysol": "كاشيوا ريسول", "Gangwon FC": "كانغوون", "Jeonbuk Hyundai Motors": "جونبوك", "Ulsan Hyundai": "أولسان",
        "Melbourne City": "ملبورن سيتي", "Central Coast Mariners": "سنترال كوست", "Al Talaba": "الطلبة",
        // أفريقيا
        "Al Ahly": "الأهلي المصري", "Zamalek": "الزمالك", "Pyramids FC": "بيراميدز", "Pyramids": "بيراميدز",
        "Wydad Casablanca": "الوداد", "Wydad AC": "الوداد", "Raja Casablanca": "الرجاء", "RS Berkane": "نهضة بركان",
        "AS FAR": "الجيش الملكي", "FAR Rabat": "الجيش الملكي", "Esperance de Tunis": "الترجي", "Espérance de Tunis": "الترجي",
        "Esperance Sportive de Tunis": "الترجي", "Etoile du Sahel": "النجم الساحلي", "CS Sfaxien": "الصفاقسي",
        "Club Africain": "الأفريقي", "MC Alger": "مولودية الجزائر", "CR Belouizdad": "شباب بلوزداد",
        "JS Kabylie": "شبيبة القبائل", "USM Alger": "اتحاد العاصمة", "Al Hilal Omdurman": "الهلال السوداني",
        "Al Merrikh": "المريخ", "Al Ahli Tripoli": "الأهلي طرابلس", "Al Ittihad Tripoli": "الاتحاد الليبي",
        "Mamelodi Sundowns": "صن داونز", "Orlando Pirates": "أورلاندو بايرتس", "Kaizer Chiefs": "كايزر تشيفز",
        "TP Mazembe": "مازيمبي", "Simba SC": "سيمبا", "Young Africans": "يانغ أفريكانز",
        // الأمريكتان
        "Flamengo": "فلامنغو", "Palmeiras": "بالميراس", "Fluminense": "فلومينينسي", "Botafogo": "بوتافوغو",
        "Corinthians": "كورينثيانز", "São Paulo": "ساو باولو", "Santos": "سانتوس", "River Plate": "ريفر بليت",
        "Boca Juniors": "بوكا جونيورز", "Inter Miami CF": "إنتر ميامي", "LA Galaxy": "لوس أنجلوس غالاكسي",
        "LAFC": "لوس أنجلوس إف سي", "Monterrey": "مونتيري", "Club América": "كلوب أمريكا", "Tigres UANL": "تيغريس",
        // المنتخبات (الأسماء التي تختلف عن أسماء الدول في النظام)
        "Saudi Arabia": "السعودية", "United Arab Emirates": "الإمارات", "UAE": "الإمارات", "Qatar": "قطر",
        "Kuwait": "الكويت", "Bahrain": "البحرين", "Oman": "عُمان", "Iraq": "العراق", "Jordan": "الأردن",
        "Syria": "سوريا", "Lebanon": "لبنان", "Palestine": "فلسطين", "Yemen": "اليمن", "Egypt": "مصر",
        "Morocco": "المغرب", "Algeria": "الجزائر", "Tunisia": "تونس", "Libya": "ليبيا", "Sudan": "السودان",
        "Mauritania": "موريتانيا", "Comoros": "جزر القمر", "Djibouti": "جيبوتي", "Somalia": "الصومال",
        "England": "إنجلترا", "Scotland": "إسكتلندا", "Wales": "ويلز", "Northern Ireland": "أيرلندا الشمالية",
        "Republic of Ireland": "أيرلندا", "United States": "الولايات المتحدة", "USA": "الولايات المتحدة",
        "South Korea": "كوريا الجنوبية", "Korea Republic": "كوريا الجنوبية", "North Korea": "كوريا الشمالية",
        "China PR": "الصين", "Iran": "إيران", "Türkiye": "تركيا", "Turkey": "تركيا", "Czechia": "التشيك",
        "Czech Republic": "التشيك", "Bosnia-Herzegovina": "البوسنة والهرسك", "Congo DR": "الكونغو الديمقراطية",
        "Ivory Coast": "كوت ديفوار", "Côte d'Ivoire": "كوت ديفوار", "Cape Verde": "الرأس الأخضر",
        "Netherlands": "هولندا", "Russia": "روسيا", "Kosovo": "كوسوفو", "Curaçao": "كوراساو",
    ]
    /// أسماء أندية المصدر الثاني (LiveScore) بتهجئتها هناك
    static let ls: [String: String] = [
        // مصر
        "El Zamalek": "الزمالك", "Zamalek SC": "الزمالك", "Al Ahly SC": "الأهلي المصري", "Al Masry": "المصري",
        "Ismaily": "الإسماعيلي", "Wadi Degla FC": "وادي دجلة", "ZED FC": "زد", "El Geish": "طلائع الجيش",
        "Talaea El Gaish": "طلائع الجيش", "Al Mokawloon Al Arab": "المقاولون العرب", "Petrojet": "بتروجت",
        "Ghazl El Mahalla": "غزل المحلة", "Al-Ittihad Alexandria": "الاتحاد السكندري", "ENPPI": "إنبي",
        "Smouha": "سموحة", "National Bank": "البنك الأهلي", "Ceramica Cleopatra": "سيراميكا كليوباترا",
        "Modern Sport FC": "مودرن سبورت", "Haras El Hodood": "حرس الحدود", "El Gouna": "الجونة", "Pharco": "فاركو",
        "Asyut Petroleum": "بترول أسيوط", "Abo Qir Semad": "أبو قير للأسمدة", "Abou Qir Fertilizers": "أبو قير للأسمدة",
        "Kahraba Ismailia": "كهرباء الإسماعيلية", "El Daklyeh": "الداخلية",
        // الإمارات
        "Al-Jazira": "الجزيرة", "Al-Ain": "العين", "Shabab Al-Ahli Dubai FC": "شباب الأهلي", "Al-Nasr SC": "النصر الإماراتي",
        "Al-Wahda": "الوحدة الإماراتي", "Al-Wasl": "الوصل", "Baniyas": "بني ياس", "Ajman": "عجمان", "Kalba": "كلباء",
        "Ittihad Kalba": "اتحاد كلباء", "Khor Fakkan": "خورفكان", "Al-Bataeh": "البطائح", "Dibba Al-Fujairah": "دبا الفجيرة",
        "Al-Dhafra": "الظفرة", "Hatta": "حتا", "Al-Orooba": "العروبة الإماراتي", "Al Urooba": "العروبة الإماراتي",
        // قطر
        "Al-Sadd": "السد", "Al-Duhail": "الدحيل", "Al-Rayyan": "الريان", "Al-Wakra": "الوكرة", "Al-Arabi": "العربي",
        "Umm Salal": "أم صلال", "Al-Shamal": "الشمال", "Al-Shahaniya": "الشحانية", "Lusail SC": "لوسيل",
        "Al-Khor": "الخور", "Al-Sailiya": "السيلية", "Al-Ahli": "الأهلي", "Al-Markhiya": "المرخية", "Muaither": "معيذر",
        // المغرب
        "FAR Rabat": "الجيش الملكي", "Ittihad Tanger": "اتحاد طنجة", "FUS Rabat": "الفتح الرباطي",
        "Maghreb Fes": "المغرب الفاسي", "MAS Fes": "المغرب الفاسي", "Hassania Agadir": "حسنية أكادير",
        "Difaa El Jadidi": "الدفاع الجديدي", "Olympic Safi": "أولمبيك آسفي", "Renaissance Zemamra": "نهضة الزمامرة",
        "US Amal Tiznit": "أمل تزنيت", "Kawkab Marrakech": "الكوكب المراكشي", "Union Touarga": "اتحاد تواركة",
        "CODM Meknes": "النادي المكناسي", "Moghreb Tetouan": "المغرب التطواني", "Wydad Casablanca": "الوداد",
        // تونس والجزائر
        "Esperance Tunis": "الترجي", "Etoile Sahel": "النجم الساحلي", "US Monastir": "الاتحاد المنستيري",
        "Stade Tunisien": "الملعب التونسي", "CA Bizertin": "النادي البنزرتي", "US Ben Guerdane": "اتحاد بن قردان",
        "MC Algiers": "مولودية الجزائر", "USM Algiers": "اتحاد العاصمة", "ES Setif": "وفاق سطيف", "CS Constantine": "شباب قسنطينة",
        // الكويت والعراق والأردن وعُمان
        "Kuwait SC": "الكويت", "Al-Qadsia": "القادسية الكويتي", "Kazma": "كاظمة", "Al-Salmiya": "السالمية",
        "Al-Tadamon": "التضامن", "Al-Fahaheel": "الفحيحيل", "Al-Jahra": "الجهراء",
        "Al-Shorta": "الشرطة", "Al-Zawraa": "الزوراء", "Al-Quwa Al-Jawiya": "القوة الجوية", "Al-Talaba": "الطلبة",
        "Erbil": "أربيل", "Duhok": "دهوك", "Zakho": "زاخو", "Al-Naft": "النفط", "Naft Al-Wasat": "نفط الوسط",
        "Al-Karkh": "الكرخ", "Al-Karma": "الكرمة", "Al-Minaa": "الميناء", "Naft Maysan": "نفط ميسان",
        "Al-Wehdat": "الوحدات", "Al-Faisaly": "الفيصلي", "Al-Hussein": "الحسين", "Al-Ramtha": "الرمثا",
        "Shabab Al-Ordon": "شباب الأردن", "Al-Salt": "السلط",
        "Al-Seeb": "السيب", "Dhofar": "ظفار", "Al-Nahda": "النهضة", "Al-Suwaiq": "السويق", "Sohar": "صحار", "Al-Nasr": "النصر",
    ]

    /// أسماء الدول بالعربي من النظام (للمنتخبات غير الموجودة أعلاه)
    private static let countries: [String: String] = {
        var m: [String: String] = [:]
        let en = Locale(identifier: "en_US"), arL = Locale(identifier: "ar")
        for r in Locale.Region.isoRegions where r.identifier.count == 2 {
            if let e = en.localizedString(forRegionCode: r.identifier), let a = arL.localizedString(forRegionCode: r.identifier) { m[e] = a }
        }
        return m
    }()
    static func ar(_ name: String, _ short: String) -> String {
        if let v = map[name] ?? map[short] ?? ls[name] { return v }
        let n2 = name.replacingOccurrences(of: "-", with: " ")
        return map[n2] ?? countries[name] ?? countries[short] ?? short
    }
}

// MARK: - النماذج

struct STeam: Codable, Hashable {
    var id: String
    var name: String
    var short: String
    var abbr: String
    var logo: String
    var display: String { Lang.isEN ? short : SNames.ar(name, short) }
    /// اسم عربي معروف للفريق (nil إن لم نعرفه) — للصفوف الضيقة بدل الاختصار اللاتيني
    var knownAr: String? {
        guard !Lang.isEN else { return nil }
        let a = SNames.ar(name, short)
        return a == short || a == name ? nil : a
    }
    static let empty = STeam(id: "", name: "", short: "", abbr: "", logo: "")
}

/// حدث داخل المباراة: هدف أو بطاقة
struct SKey: Codable, Hashable {
    var minute: String
    var kind: String        // goal, pen, og, yellow, red
    var team: String
    var player: String
    var pid: String
    var isGoal: Bool { kind == "goal" || kind == "pen" || kind == "og" }
}

struct SMatch: Codable, Hashable, Identifiable {
    var id: String
    var league: String
    var date: Date
    var state: String           // pre / in / post
    var status: String          // STATUS_FIRST_HALF ...
    var detail: String
    var clock: Double           // ثواني اللعب وقت الجلب
    var at: Date                // وقت الجلب
    var home: STeam
    var away: STeam
    var hs: Int?
    var aws: Int?
    var keys: [SKey] = []
    var round: String = ""

    var live: Bool { state == "in" }
    /// انتهت فعلًا (المؤجلة والملغاة ليست نتيجة: لا ٠-٠ ولا شارة تعادل)
    var done: Bool { state == "post" && !postponed }
    var halftime: Bool { status == "STATUS_HALFTIME" }
    var shootout: Bool { status.contains("PENALTY") || status.contains("SHOOTOUT") }
    /// العدّاد يمشي (مو استراحة ولا ركلات ترجيح)
    var running: Bool { live && !halftime && !shootout && !status.contains("END") }
    var postponed: Bool { status.contains("POSTPONED") || status.contains("CANCELED") || status.contains("SUSPENDED") }
    /// بداية عدّاد اللعب (لحساب الدقيقة لحظيًا بلا تحديث)
    var clockStart: Date { at.addingTimeInterval(-clock) }
    var minuteText: String {
        let m = max(1, Int(clock / 60) + 1)
        return ar(m) + "'"
    }
    func has(_ team: String) -> Bool { home.id == team || away.id == team }
    func opponent(of team: String) -> STeam { home.id == team ? away : home }
    func isHome(_ team: String) -> Bool { home.id == team }
    /// نتيجة الفريق: W / D / L
    func result(for team: String) -> String? {
        guard done, let h = hs, let a = aws else { return nil }
        let mine = home.id == team ? h : a, other = home.id == team ? a : h
        return mine > other ? "W" : mine < other ? "L" : "D"
    }
    func reds(_ team: String) -> Int { keys.filter { $0.kind == "red" && $0.team == team }.count }
    func yellows(_ team: String) -> Int { keys.filter { $0.kind == "yellow" && $0.team == team }.count }
    var goals: [SKey] { keys.filter { $0.isGoal } }
}

struct SRow: Codable, Hashable {
    var rank: Int
    var team: STeam
    var gp: Int
    var w: Int
    var d: Int
    var l: Int
    var gd: Int
    var pts: Int
    var note: String = ""       // لون التأهل
    var group: String? = nil    // المجموعة (في البطولات ذات المجموعات)
}

struct SScorer: Codable, Hashable {
    var rank: Int
    var name: String
    var id: String
    var team: STeam
    var goals: Int
    var assists: Int
    var photo: String
}

struct SportsData: Codable {
    var updated = Date.distantPast
    var team: STeam? = nil
    var league = "ksa.1"
    var rank = 0
    var points = 0
    var played = 0
    var next: [SMatch] = []
    var last: [SMatch] = []
    var day: [SMatch] = []
    var dayLeague = "ksa.1"
    var table: [SRow] = []
    var tableLeague = "ksa.1"
    var scorers: [SScorer] = []

    /// آخر خمس نتائج (الأقدم أولًا)
    var form: [String] {
        guard let t = team?.id else { return [] }
        return Array(last.prefix(5).compactMap { $0.result(for: t) }.reversed())
    }

    /// مباراة الفريق الأهم الآن: الجارية، ثم القادمة إن كانت خلال يومين، ثم الأخيرة إن كانت خلال ١٢ ساعة، ثم القادمة
    func focus(at now: Date = Date()) -> SMatch? {
        if let l = next.first(where: { $0.live }) ?? last.first(where: { $0.live }) { return l }
        if let r = last.first, r.done, now.timeIntervalSince(r.date) < 12 * 3600 { return r }
        if let n = next.first(where: { !$0.done }) { return n }
        return last.first
    }

    func upcoming(_ n: Int, after now: Date = Date()) -> [SMatch] {
        Array(next.filter { !$0.done }.prefix(n))
    }

    var leagueName: String { league == Leagues.nationsKey ? L("منتخب وطني") : Leagues.get(league).name }

    /// صفوف الترتيب المعروضة في الويدجت: مجموعة فريقك أو أول مجموعة
    var groupTable: [SRow] {
        guard table.contains(where: { $0.group != nil }) else { return table }
        let g = table.first(where: { $0.team.id == team?.id })?.group ?? table.first?.group
        return table.filter { $0.group == g }
    }
    /// عنوان الترتيب: البطولة، ثم المجموعة إن وُجدت
    func tableTitle(_ rows: [SRow]) -> String {
        let n = Leagues.get(tableLeague).name
        guard let g = rows.first?.group, !g.isEmpty else { return n }
        return n + " · " + sGroupName(g)
    }
    var hasTeam: Bool { team != nil && !(team?.id.isEmpty ?? true) }
}

// MARK: - الإعدادات

enum SportsPrefs {
    private static var d: UserDefaults { AppGroup.defaults }
    static var teamId: String {
        get { d.string(forKey: "sp_team") ?? "929" }
        set { d.set(newValue, forKey: "sp_team") }
    }
    static var teamLeague: String {
        get { d.string(forKey: "sp_league") ?? "ksa.1" }
        set { d.set(newValue, forKey: "sp_league") }
    }
    /// دوري ويدجت «مباريات» و«الترتيب» و«الهدافين» (فارغ = دوري فريقي)
    static var viewLeague: String {
        get { d.string(forKey: "sp_view_league") ?? "" }
        set { d.set(newValue, forKey: "sp_view_league") }
    }
    static var effectiveViewLeague: String { viewLeague.isEmpty ? teamLeague : viewLeague }

    static var notifyBefore: Bool {
        get { d.object(forKey: "sp_n_before") as? Bool ?? true }
        set { d.set(newValue, forKey: "sp_n_before") }
    }
    static var beforeMinutes: Int {
        get { d.object(forKey: "sp_n_before_min") as? Int ?? 15 }
        set { d.set(newValue, forKey: "sp_n_before_min") }
    }
    static var notifyGoals: Bool {
        get { d.object(forKey: "sp_n_goals") as? Bool ?? true }
        set { d.set(newValue, forKey: "sp_n_goals") }
    }
    static var notifyCards: Bool {
        get { d.object(forKey: "sp_n_cards") as? Bool ?? true }
        set { d.set(newValue, forKey: "sp_n_cards") }
    }
    static var notifyPhases: Bool {
        get { d.object(forKey: "sp_n_phases") as? Bool ?? true }
        set { d.set(newValue, forKey: "sp_n_phases") }
    }
    /// المتابعة المباشرة تبدأ تلقائيًا إذا كان التطبيق صاحيًا قبل المباراة
    static var liveActivity: Bool {
        get { d.object(forKey: "sp_la") as? Bool ?? true }
        set { d.set(newValue, forKey: "sp_la") }
    }
    /// المباراة اللي تتابعها الآن (للويدجت)
    static var following: String {
        get { d.string(forKey: "sp_following") ?? "" }
        set { d.set(newValue, forKey: "sp_following") }
    }
    static var followHeartbeat: Date {
        get { Date(timeIntervalSince1970: d.double(forKey: "sp_follow_hb")) }
        set { d.set(newValue.timeIntervalSince1970, forKey: "sp_follow_hb") }
    }
    /// المتابعة شغّالة فعلًا (التطبيق يحدّث كل ٢٠ ثانية)
    static var isFollowingLive: Bool { !following.isEmpty && Date().timeIntervalSince(followHeartbeat) < 120 }
}

// MARK: - التخزين

enum SportsStore {
    static var url: URL? { AppGroup.container?.appendingPathComponent("sports.json") }
    static func load() -> SportsData? {
        guard let u = url, let data = try? Data(contentsOf: u) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(SportsData.self, from: data)
    }

    static func save(_ s: SportsData) {
        guard let u = url else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let data = try? enc.encode(s) { try? data.write(to: u, options: .atomic) }
    }

    /// البيانات المحفوظة أو بيانات العرض التجريبية
    static func current() -> SportsData { load() ?? SportsDemo.data }
}

// MARK: - الجلب من ESPN

enum ESPN {
    static let site = "https://site.api.espn.com/apis/site/v2/sports/soccer/"
    static let v2 = "https://site.api.espn.com/apis/v2/sports/soccer/"

    static func json(_ url: String, timeout: TimeInterval = 12) async -> JObj? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let res = try? await URLSession.shared.data(for: req),
              let code = (res.1 as? HTTPURLResponse)?.statusCode, code == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: res.0)) as? JObj
    }

    // ── التاريخ ──
    private static let isoA: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mmX"; return f
    }()
    private static let isoB: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssX"; return f
    }()
    private static let isoC: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSX"; return f
    }()
    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoA.date(from: s) ?? isoB.date(from: s) ?? isoC.date(from: s)
    }
    static func ymd(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: d)
    }

    // ── التحليل ──
    static func team(_ t: JObj?) -> STeam {
        guard let t else { return .empty }
        let id = t.s("id") ?? ""
        var logo = t.s("logo") ?? ""
        let logos = t.a("logos")
        if let dark = logos.first(where: { (($0["rel"] as? [String]) ?? []).contains("dark") })?.s("href") { logo = dark }
        else if logo.isEmpty, let l = logos.first?.s("href") { logo = l }
        if logo.isEmpty && !id.isEmpty { logo = "https://a.espncdn.com/i/teamlogos/soccer/500/\(id).png" }
        let name = t.s("displayName") ?? t.s("name") ?? ""
        return STeam(id: id, name: name, short: t.s("shortDisplayName") ?? name,
                     abbr: t.s("abbreviation") ?? String(name.prefix(3)).uppercased(), logo: logo)
    }

    static func score(_ v: Any?) -> Int? {
        if let s = v as? String { return Int(s) }
        if let n = v as? NSNumber { return n.intValue }
        if let o = v as? JObj { return o.d("value").map { Int($0) } ?? o.s("displayValue").flatMap { Int($0) } }
        return nil
    }

    static func match(_ ev: JObj, league: String, now: Date = Date()) -> SMatch? {
        guard let id = ev.s("id"), let comp = ev.a("competitions").first else { return nil }
        let cs = comp.a("competitors")
        guard let h = cs.first(where: { $0.s("homeAway") == "home" }) ?? cs.first,
              let a = cs.first(where: { $0.s("homeAway") == "away" }) ?? cs.last else { return nil }
        let st = comp.o("status") ?? ev.o("status") ?? [:]
        let ty = st.o("type") ?? [:]
        let state = ty.s("state") ?? "pre"
        var m = SMatch(id: id, league: league, date: date(comp.s("date") ?? ev.s("date")) ?? now,
                       state: state, status: ty.s("name") ?? "", detail: ty.s("shortDetail") ?? "",
                       clock: st.d("clock") ?? 0, at: now, home: team(h.o("team")), away: team(a.o("team")),
                       hs: state == "pre" ? nil : score(h["score"]), aws: state == "pre" ? nil : score(a["score"]))
        if let w = ev.o("week")?.d("number") { m.round = String(Int(w)) }
        m.keys = keys(comp.a("details"))
        return m
    }

    static func keys(_ details: [JObj]) -> [SKey] {
        details.compactMap { k -> SKey? in
            // ركلات الترجيح ليست أهدافًا في المباراة
            if k.b("shootout") { return nil }
            let text = (k.o("type")?.s("text") ?? "").lowercased()
            var kind = ""
            if k.b("scoringPlay") || text.contains("goal") {
                kind = k.b("ownGoal") || text.contains("own") ? "og" : (k.b("penaltyKick") || text.contains("penalty") ? "pen" : "goal")
                if text.contains("miss") || text.contains("saved") { return nil }
            } else if k.b("redCard") || text.contains("red card") {
                kind = "red"
            } else if k.b("yellowCard") || text.contains("yellow") {
                kind = "yellow"
            } else { return nil }
            let ath = k.a("athletesInvolved").first ?? k.a("participants").first?.o("athlete") ?? [:]
            return SKey(minute: k.o("clock")?.s("displayValue") ?? "", kind: kind, team: k.o("team")?.s("id") ?? "",
                        player: ath.s("displayName") ?? ath.s("shortName") ?? "", pid: ath.s("id") ?? "")
        }
    }

    // ── النداءات ──
    /// المباريات بين تاريخين (yyyyMMdd-yyyyMMdd) أو أقرب جولة.
    /// ESPN أوقف طلب المدى بين تاريخين (يرجع 400)، فنطلب كل شهر في المدى (yyyyMM) ونصفّي بالتاريخ
    static func scoreboard(_ league: String, dates: String? = nil) async -> [SMatch] {
        if LS.owns(league) { return await LS.scoreboard(league, dates: dates) }
        guard let dates, let r = dayRange(dates) else { return await board(league, dates: dates) }
        var all: [SMatch] = [], seen = Set<String>()
        // بالتتابع (ذاكرة الويدجت محدودة) — شهر أو شهران عادة
        for m in months(from: r.from, to: r.to) {
            for x in await board(league, dates: m) where seen.insert(x.id).inserted { all.append(x) }
        }
        return all.filter { $0.date >= r.from && $0.date < r.to }.sorted { $0.date < $1.date }
    }

    /// «yyyyMMdd-yyyyMMdd» ← (بداية اليوم الأول، نهاية اليوم الأخير) بتوقيت UTC
    static func dayRange(_ s: String) -> (from: Date, to: Date)? {
        let p = s.split(separator: "-").map(String.init)
        guard p.count == 2, p[0].count == 8, p[1].count == 8 else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd"
        guard let a = f.date(from: p[0]), let b = f.date(from: p[1]) else { return nil }
        return (a, b.addingTimeInterval(86400))
    }

    /// الأشهر التي يغطيها المدى بصيغة yyyyMM
    static func months(from a: Date, to b: Date) -> [String] {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        var out: [String] = []
        var cur = c.date(from: c.dateComponents([.year, .month], from: a)) ?? a
        while cur < b && out.count < 4 {
            let k = c.dateComponents([.year, .month], from: cur)
            out.append(String(format: "%04d%02d", k.year ?? 2026, k.month ?? 1))
            guard let n = c.date(byAdding: .month, value: 1, to: cur) else { break }
            cur = n
        }
        return out
    }

    /// طلب واحد لجدول ESPN (يوم واحد yyyyMMdd، أو شهر yyyyMM، أو بلا تاريخ = أقرب جولة)
    private static func board(_ league: String, dates: String?) async -> [SMatch] {
        var u = site + league + "/scoreboard?limit=300"
        if let dates { u += "&dates=" + dates }
        guard let j = await json(u) else { return [] }
        let now = Date()
        return j.a("events").compactMap { match($0, league: league, now: now) }.sorted { $0.date < $1.date }
    }

    /// رمز بطولة المباراة من بياناتها (للجداول الشاملة لكل البطولات)
    static func leagueOf(_ ev: JObj, _ fallback: String) -> String {
        guard let l = ev.o("league"), let slug = l.s("slug"), !slug.isEmpty else { return fallback }
        Leagues.learn(slug, l.s("shortName") ?? l.s("name"))
        return slug
    }

    static func schedule(_ league: String, team: String) async -> [SMatch] {
        if LS.owns(league) { return await LS.schedule(league, team: team) }
        guard let j = await json(site + league + "/teams/" + team + "/schedule") else { return [] }
        let now = Date()
        return j.a("events").compactMap { match($0, league: leagueOf($0, league), now: now) }
    }

    /// كل مباريات الفريق هذا الموسم في كل البطولات (الدوري والكأس والقارية والمنتخبات)
    static func allSchedule(team: String, fallback: String) async -> [SMatch] {
        if team.hasPrefix("ls") { return [] }
        guard let j = await json(site + "all/teams/" + team + "/schedule") else { return [] }
        let now = Date()
        return j.a("events").compactMap { match($0, league: leagueOf($0, fallback), now: now) }
    }

    /// بيانات الفريق ومباراته القادمة في أي بطولة (ثم من الدوري إن تعذّر)
    static func teamInfo(_ league: String, team: String) async -> (STeam, [SMatch])? {
        if LS.owns(league) { return await LS.teamInfo(league, team: team) }
        let now = Date()
        for path in ["all", league] {
            guard let j = await json(site + path + "/teams/" + team), let t = j.o("team") else { continue }
            let next = t.a("nextEvent").compactMap { match($0, league: leagueOf($0, league), now: now) }
            return (self.team(t), next)
        }
        return nil
    }

    static func standingsIf(_ need: Bool, _ league: String, team: String) async -> [SRow] {
        guard need else { return [] }
        return await standings(league, team: team)
    }

    /// الترتيب: مجموعة فريقك فقط إن كان مشاركًا، وإلا كل المجموعات
    static func standings(_ league: String, team: String) async -> [SRow] {
        if LS.owns(league) { return await LS.standings(league, team: team) }
        guard let j = await json(v2 + league + "/standings") else { return [] }
        var groups: [(name: String, entries: [JObj])] = j.a("children").map { ($0.s("name") ?? "", $0.o("standings")?.a("entries") ?? []) }
        if groups.isEmpty, let e = j.o("standings")?.a("entries") { groups = [("", e)] }
        groups = groups.filter { !$0.entries.isEmpty }
        let multi = groups.count > 1
        let pick = groups.first { g in g.entries.contains { $0.o("team")?.s("id") == team } }.map { [$0] } ?? groups
        return pick.flatMap { g -> [SRow] in
            var rows: [SRow] = g.entries.enumerated().map { i, e in
                var st: [String: Double] = [:]
                for s in e.a("stats") { if let n = s.s("name"), let v = s.d("value") { st[n] = v } }
                let r = Int(st["rank"] ?? Double(i + 1))
                return SRow(rank: r == 0 ? i + 1 : r, team: self.team(e.o("team")), gp: Int(st["gamesPlayed"] ?? 0),
                            w: Int(st["wins"] ?? 0), d: Int(st["ties"] ?? 0), l: Int(st["losses"] ?? 0),
                            gd: Int(st["pointDifferential"] ?? 0), pts: Int(st["points"] ?? 0),
                            note: e.o("note")?.s("color") ?? "", group: multi ? g.name : nil)
            }
            rows.sort { $0.rank < $1.rank }
            return rows
        }
    }

    static func scorers(_ league: String) async -> [SScorer] {
        if LS.owns(league) { return [] }   // لا قائمة هدافين في المصدر الثاني
        guard let j = await json(site + league + "/statistics") else { return [] }
        let cat = j.a("stats").first { $0.s("name") == "goalsLeaders" } ?? j.a("stats").first ?? [:]
        return cat.a("leaders").prefix(10).enumerated().map { i, l in
            let a = l.o("athlete") ?? [:]
            var assists = 0, goals = Int(l.d("value") ?? 0)
            for s in a.a("statistics") {
                if s.s("name") == "goalAssists" { assists = Int(s.d("value") ?? 0) }
                if s.s("name") == "totalGoals", let g = s.d("value") { goals = Int(g) }
            }
            let id = a.s("id") ?? ""
            var photo = a.o("headshot")?.s("href") ?? ""
            if photo.isEmpty && !id.isEmpty { photo = "https://a.espncdn.com/i/headshots/soccer/players/full/\(id).png" }
            return SScorer(rank: i + 1, name: a.s("displayName") ?? "", id: id, team: team(a.o("team")),
                           goals: goals, assists: assists, photo: photo)
        }
    }

    /// تفاصيل مباراة واحدة (احتياط لو ما لقيناها في جدول اليوم)
    static func summary(_ league: String, event: String) async -> SMatch? {
        if LS.owns(league) { return await LS.event(league, id: event) }
        guard let j = await json(site + league + "/summary?event=" + event),
              let comp = j.o("header")?.a("competitions").first else { return nil }
        var ev: JObj = ["id": event, "competitions": [comp]]
        if let d = comp.s("date") { ev["date"] = d }
        guard var m = match(ev, league: league) else { return nil }
        let k = keys(j.a("keyEvents"))
        if !k.isEmpty { m.keys = k }
        return m
    }
}

// MARK: - التحديث

enum Sports {
    /// داخل امتداد الويدجت (ذاكرته محدودة): جلب أخف وبالتتابع
    static var inWidget: Bool { Bundle.main.bundleURL.pathExtension == "appex" }

    /// يحدّث كل البيانات (التطبيق كاملًا، والويدجت بشكل أخف إذا قدمت البيانات)
    @discardableResult
    static func refresh() async -> SportsData {
        let teamId = SportsPrefs.teamId, league = SportsPrefs.teamLeague
        var data = SportsStore.load() ?? SportsData()
        // تغيّر الفريق: نبدأ من جديد
        if let t = data.team, t.id != teamId { data = SportsData() }
        // المنتخب: البطولة المعروضة افتراضيًا هي بطولة مبارياته (ويُفضَّل ما له ترتيب)
        let recent = (data.next + data.last).map { $0.league }
        let viewLeague = league == Leagues.nationsKey && SportsPrefs.viewLeague.isEmpty
            ? (recent.first { Leagues.get($0).hasTable } ?? recent.first ?? "fifa.world")
            : SportsPrefs.effectiveViewLeague
        let now = Date()
        let full = !inWidget
        // التطبيق: شهر للخلف وشهر ونص للأمام — الويدجت: ٣ أيام للخلف وأسبوعان للأمام
        let from = ESPN.ymd(now.addingTimeInterval(-(full ? 30 : 3) * 86400))
        let to = ESPN.ymd(now.addingTimeInterval((full ? 45 : 14) * 86400))
        let dayFrom = ESPN.ymd(now.addingTimeInterval(-2 * 86400)), dayTo = ESPN.ymd(now.addingTimeInterval(7 * 86400))
        let tableLeague = Leagues.get(viewLeague).hasTable ? viewLeague : league

        var info: (STeam, [SMatch])? = nil
        var past: [SMatch] = [], ahead: [SMatch] = [], rows: [SRow] = [], sc: [SScorer] = [], day: [SMatch] = []
        var extraPast: [SMatch] = [], extraAhead: [SMatch] = [], ownRows: [SRow] = []
        if full {
            async let i1 = ESPN.teamInfo(league, team: teamId)
            async let e1 = ESPN.allSchedule(team: teamId, fallback: league)
            async let p1 = ESPN.schedule(league, team: teamId)
            async let a1 = ESPN.scoreboard(league, dates: from + "-" + to)
            async let t1 = ESPN.standings(tableLeague, team: teamId)
            async let s1 = ESPN.scorers(tableLeague)
            async let d1 = ESPN.scoreboard(viewLeague, dates: dayFrom + "-" + dayTo)
            // ترتيب دوري الفريق نفسه (لمركزه ونقاطه) إذا كانت البطولة المعروضة غيره
            async let r1 = ESPN.standingsIf(tableLeague != league && Leagues.get(league).hasTable, league, team: teamId)
            // كل مباريات الموسم في كل البطولات: منها نعرف بطولات الفريق الأخرى
            let everything = await e1
            let seen = Set((everything + data.last + data.next).map { $0.league })
            // البطولات الإضافية (الكؤوس والقارية وبطولات المنتخبات): القادمة والأخيرة
            await withTaskGroup(of: [SMatch].self) { g in
                for x in Leagues.extras(for: league, seen: seen) {
                    g.addTask { await ESPN.scoreboard(x, dates: from + "-" + to).filter { $0.has(teamId) } }
                }
                for await r in g { extraPast += r.filter { $0.done }; extraAhead += r.filter { !$0.done } }
            }
            extraPast += everything.filter { $0.done }
            extraAhead += everything.filter { !$0.done && $0.date > now.addingTimeInterval(-3 * 3600) }
            info = await i1; past = await p1; ahead = await a1; rows = await t1; sc = await s1; day = await d1
            ownRows = await r1
        } else {
            // بالتتابع حتى لا تتجمّع الردود الكبيرة في الذاكرة
            info = await ESPN.teamInfo(league, team: teamId)
            ahead = await ESPN.scoreboard(league, dates: from + "-" + to)
            rows = await ESPN.standings(tableLeague, team: teamId)
            if viewLeague == league { day = ahead } else { day = await ESPN.scoreboard(viewLeague, dates: dayFrom + "-" + dayTo) }
        }
        // لا مباريات قريبة في البطولة المعروضة: نعرض أقرب جولة لها
        if day.isEmpty { day = await ESPN.scoreboard(viewLeague) }

        let prevTable = data.tableLeague
        if let t = info?.0, !t.id.isEmpty { data.team = t }
        data.league = league

        // المباريات القادمة والجارية
        var upcoming = ahead.filter { $0.has(teamId) && !$0.done } + extraAhead + (info?.1 ?? []).filter { !$0.done }
        // الويدجت ما يجلب البطولات الإضافية: نُبقي القادمة المحفوظة منها
        if !full { upcoming += data.next.filter { !$0.done && $0.date > now.addingTimeInterval(-3 * 3600) } }
        upcoming = dedupe(upcoming).filter { !$0.postponed || $0.date > now }.sorted { $0.date < $1.date }
        // النتائج الأخيرة
        var results = past.filter { $0.done } + extraPast + ahead.filter { $0.has(teamId) && $0.done }
        if !full { results += data.last }
        results = dedupe(results).filter { $0.done }.sorted { $0.date > $1.date }
        // نفس المباراة قد تنتهي بعد ما جات في القادمة
        let doneIds = Set(results.map { $0.id })
        upcoming.removeAll { doneIds.contains($0.id) }
        if !upcoming.isEmpty || !results.isEmpty {
            // أحداث سبق جلبها لنفس المباراة لا تضيع إذا جاءت المباراة هذه المرة بدونها
            var oldKeys: [String: [SKey]] = [:]
            for m in data.next + data.last where !m.keys.isEmpty { oldKeys[m.id] = m.keys }
            func keep(_ a: [SMatch]) -> [SMatch] {
                a.map { m in
                    guard m.keys.isEmpty, let k = oldKeys[m.id] else { return m }
                    var x = m; x.keys = k; return x
                }
            }
            data.next = keep(Array(upcoming.prefix(8)))
            data.last = keep(Array(results.prefix(8)))
        }

        if let mine = ownRows.first(where: { $0.team.id == teamId }) {
            data.rank = mine.rank; data.points = mine.pts; data.played = mine.gp
        }
        if !rows.isEmpty {
            data.table = rows
            data.tableLeague = tableLeague
            // المركز والنقاط من دوري الفريق نفسه فقط (لا من بطولة أخرى معروضة)
            if tableLeague == league, let mine = rows.first(where: { $0.team.id == teamId }) {
                data.rank = mine.rank; data.points = mine.pts; data.played = mine.gp
                if data.team == nil { data.team = mine.team }
            }
        } else if data.tableLeague != tableLeague {
            // بطولة جديدة بلا ترتيب: لا نُبقي ترتيب البطولة السابقة
            data.table = []; data.tableLeague = tableLeague; data.scorers = []
        }
        if !sc.isEmpty { data.scorers = sc } else if prevTable != tableLeague { data.scorers = [] }
        if !day.isEmpty {
            let recent = day.filter { $0.date >= now.addingTimeInterval(-2 * 86400) }
            data.day = dayList(recent.isEmpty ? day : recent, now: now)
            data.dayLeague = viewLeague
        } else if data.dayLeague != viewLeague {
            data.day = []; data.dayLeague = viewLeague
        }
        // المصدر الثاني: أحداث مباراة فريقك (الأهداف والبطاقات) لا تأتي مع جدول الموسم
        // (والمصدر الأول كذلك: جدول الموسم بلا أهداف — نجلب ملخص المباراة مرة، وتُحفظ أحداثه)
        if let f = data.focus(at: now), f.keys.isEmpty,
           (LS.owns(f.league) && f.live) || (f.done && (f.hs ?? 0) + (f.aws ?? 0) > 0 && now.timeIntervalSince(f.date) < 12 * 3600),
           let m = await ESPN.summary(f.league, event: f.id), !m.keys.isEmpty {
            func upd(_ a: inout [SMatch]) { for i in a.indices where a[i].id == m.id { a[i] = m } }
            upd(&data.next); upd(&data.last); upd(&data.day)
        }
        data.updated = now
        SportsStore.save(data)
        await SportsImages.ensure(data)
        await SportsNotify.schedulePreMatch(data)
        return data
    }

    /// يحدّث مباراة واحدة جارية (كل ٢٠ ثانية أثناء المتابعة)
    static func poll(_ m: SMatch) async -> SMatch? {
        // المصدر الثاني: مباراة واحدة مباشرة (أخف من جلب الموسم كاملًا)
        if LS.owns(m.league) { return await LS.event(m.league, id: m.id) }
        let range = ESPN.ymd(m.date.addingTimeInterval(-86400)) + "-" + ESPN.ymd(m.date.addingTimeInterval(86400))
        let list = await ESPN.scoreboard(m.league, dates: range)
        if let f = list.first(where: { $0.id == m.id }) { return f }
        return await ESPN.summary(m.league, event: m.id)
    }

    /// يدمج مباراة محدّثة داخل البيانات ويحفظها
    @discardableResult
    static func merge(_ m: SMatch) -> SportsData {
        var data = SportsStore.load() ?? SportsData()
        func upd(_ a: inout [SMatch]) { for i in a.indices where a[i].id == m.id { a[i] = m } }
        upd(&data.next); upd(&data.day); upd(&data.last)
        if m.done, let i = data.next.firstIndex(where: { $0.id == m.id }) {
            data.next.remove(at: i)
            if !data.last.contains(where: { $0.id == m.id }) { data.last.insert(m, at: 0) }
        }
        SportsStore.save(data)
        return data
    }

    /// إزالة التكرار: نُبقي ترتيب أول ظهور، ونأخذ النسخة الأغنى بالأحداث (جدول الموسم لا يحمل الأهداف)
    private static func dedupe(_ a: [SMatch]) -> [SMatch] {
        var at: [String: Int] = [:], out: [SMatch] = []
        for m in a {
            if let i = at[m.id] {
                if m.keys.count > out[i].keys.count { out[i] = m }
            } else { at[m.id] = out.count; out.append(m) }
        }
        return out
    }

    static func dayListPublic(_ all: [SMatch], now: Date) -> [SMatch] { dayList(all, now: now) }

    /// مباريات اليوم: الجارية واليوم أولًا، ثم القادمة، وإن ما فيه شيء فآخر جولة
    private static func dayList(_ all: [SMatch], now: Date) -> [SMatch] {
        let today = Cal.gregCal.startOfDay(for: now)
        let live = all.filter { $0.live }
        let todays = all.filter { !$0.live && Cal.gregCal.isDate($0.date, inSameDayAs: now) }
        let later = all.filter { !$0.live && $0.date >= today && !Cal.gregCal.isDate($0.date, inSameDayAs: now) && !$0.done }
        var out = live + todays + later
        if out.count < 3 { out += all.filter { $0.done && $0.date < today }.sorted { $0.date > $1.date } }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }.prefix(10).map { $0 }
    }

    static var reloadKinds: [String] { RafiqiKinds.home + SportsLockKinds.all }

    static func reloadWidgets() {
        for k in reloadKinds { WidgetCenter.shared.reloadTimelines(ofKind: k) }
    }
}

// MARK: - الصور (شعارات الفرق وصور اللاعبين) مخزّنة في مجموعة التطبيق

enum SportsImages {
    private static var cache: [String: UIImage] = [:]
    static var dir: URL? {
        guard let c = AppGroup.container else { return nil }
        let d = c.appendingPathComponent("sports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }
    static func key(_ url: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in url.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 36)
    }
    static func file(_ url: String) -> URL? { dir?.appendingPathComponent(key(url) + ".png") }

    static func image(_ url: String) -> UIImage? {
        guard !url.isEmpty else { return nil }
        if let c = cache[url] { return c }
        guard let f = file(url), let i = UIImage(contentsOfFile: f.path) else { return nil }
        cache[url] = i
        return i
    }

    static func ensure(_ data: SportsData) async {
        var urls = Set<String>()
        if let t = data.team { urls.insert(t.logo) }
        for m in data.next + data.last + data.day { urls.insert(m.home.logo); urls.insert(m.away.logo) }
        for r in data.table { urls.insert(r.team.logo) }
        for s in data.scorers { urls.insert(s.photo); urls.insert(s.team.logo) }
        if let f = data.focus() {
            for k in f.keys where k.isGoal && !k.pid.isEmpty {
                urls.insert("https://a.espncdn.com/i/headshots/soccer/players/full/\(k.pid).png")
            }
        }
        await ensure(urls)
    }

    static func ensure(_ urls: Set<String>) async {
        let missing = Array(urls.filter { u in !u.isEmpty && !(file(u).map { FileManager.default.fileExists(atPath: $0.path) } ?? true) })
        // أربع صور في كل دفعة (ذاكرة الويدجت محدودة)
        var i = 0
        while i < missing.count {
            let batch = missing[i..<min(missing.count, i + 4)]
            await withTaskGroup(of: Void.self) { g in
                for u in batch { g.addTask { await SportsImages.fetch(u) } }
            }
            i += 4
        }
    }

    private static func fetch(_ url: String) async {
        guard let u = URL(string: url), let f = file(url) else { return }
        // تصغير مباشر من الملف بدون فكّ الصورة كاملة (ImageIO)
        guard let res = try? await URLSession.shared.data(from: u),
              (res.1 as? HTTPURLResponse)?.statusCode == 200,
              let src = CGImageSourceCreateWithData(res.0 as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 120,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else {
            // نحفظ ملف فاضي عشان ما نعيد المحاولة كل مرة (صور لاعبين غير موجودة)
            try? Data().write(to: f)
            return
        }
        try? UIImage(cgImage: thumb).pngData()?.write(to: f, options: .atomic)
    }
}

// MARK: - إشعار قبل المباراة (مجدول على الجهاز)

enum SportsNotify {
    static func schedulePreMatch(_ data: SportsData) async {
        let c = UNUserNotificationCenter.current()
        let pending = await c.pendingNotificationRequests().map { $0.identifier }.filter { $0.hasPrefix("sp_pre_") }
        c.removePendingNotificationRequests(withIdentifiers: pending)
        guard SportsPrefs.notifyBefore, let t = data.team else { return }
        let now = Date()
        for m in data.next.prefix(3) where m.state == "pre" && !m.postponed {
            let fire = m.date.addingTimeInterval(-Double(SportsPrefs.beforeMinutes) * 60)
            guard fire > now else { continue }
            let content = UNMutableNotificationContent()
            let opp = m.opponent(of: t.id)
            content.title = "\(m.home.display) - \(m.away.display)"
            content.body = Lang.isEN
                ? "Kick-off in \(SportsPrefs.beforeMinutes) min vs \(opp.display). Tap to follow live."
                : "تبدأ المباراة بعد \(minutesText(SportsPrefs.beforeMinutes)). اضغط للمتابعة المباشرة."
            content.sound = .default
            content.userInfo = ["url": "miqat://follow/\(m.league)/\(m.id)"]
            content.subtitle = Leagues.get(m.league).name
            content.threadIdentifier = "miqat.match"
            content.categoryIdentifier = NotifyKinds.match
            if let a = NotifyArt.attachment(NotifyArt.match(home: m.home.logo, away: m.away.logo, score: STime.time(m.date)),
                                            id: "m\(m.id)") { content.attachments = [a] }
            let comps = Cal.gregCal.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: fire)
            let req = UNNotificationRequest(identifier: "sp_pre_\(m.id)", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await c.add(req)
        }
    }

    /// إشعار فوري (هدف، بطاقة، استراحة، نهاية)
    static func now(_ title: String, _ body: String, id: String, match m: SMatch? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // إشعارات كل مباراة مجمّعة معًا
        content.threadIdentifier = m.map { "miqat.match.\($0.id)" } ?? "miqat.match"
        content.relevanceScore = 1
        if let m {
            content.subtitle = Leagues.get(m.league).name
            let score = Lang.isEN ? "\(m.hs ?? 0) - \(m.aws ?? 0)" : lrmPair(ar(m.aws ?? 0), ar(m.hs ?? 0))
            if let a = NotifyArt.attachment(NotifyArt.match(home: m.home.logo, away: m.away.logo, score: score), id: "g\(m.id)") {
                content.attachments = [a]
            }
        }
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - بيانات تجريبية (للمعاينة قبل أول تحديث)

enum SportsDemo {
    static func t(_ id: String, _ name: String, _ abbr: String) -> STeam {
        STeam(id: id, name: name, short: name, abbr: abbr, logo: "https://a.espncdn.com/i/teamlogos/soccer/500/\(id).png")
    }
    static let hilal = t("929", "Al Hilal", "HIL"), nassr = t("817", "Al Nassr", "NSR"), ittihad = t("2276", "Al Ittihad", "ITT")
    static let ahli = t("8346", "Al Ahli", "AHL"), qadsiah = t("22022", "Al Qadsiah", "QAD"), shabab = t("793", "Al Shabab", "SHA")
    static let fateh = t("13033", "Al Fateh", "FAT"), ettifaq = t("8363", "Al Ettifaq", "ETT"), taawoun = t("18459", "Al Taawoun", "TAA")

    static var data: SportsData {
        let now = Date()
        func m(_ id: String, _ h: STeam, _ a: STeam, _ dt: TimeInterval, _ state: String, _ hs: Int? = nil, _ as_: Int? = nil,
               clock: Double = 0, status: String = "STATUS_SCHEDULED", keys: [SKey] = []) -> SMatch {
            SMatch(id: id, league: "ksa.1", date: now.addingTimeInterval(dt), state: state, status: status, detail: "",
                   clock: clock, at: now, home: h, away: a, hs: hs, aws: as_, keys: keys, round: "11")
        }
        let liveKeys = [
            SKey(minute: "18'", kind: "goal", team: "929", player: "A. Mitrović", pid: ""),
            SKey(minute: "34'", kind: "goal", team: "817", player: "Cristiano Ronaldo", pid: ""),
            SKey(minute: "40'", kind: "yellow", team: "817", player: "Marcelo Brozović", pid: ""),
            SKey(minute: "61'", kind: "goal", team: "929", player: "Malcom", pid: ""),
        ]
        let live = m("d1", hilal, nassr, -70 * 60, "in", 2, 1, clock: 68 * 60, status: "STATUS_SECOND_HALF", keys: liveKeys)
        var d = SportsData()
        d.updated = now
        d.team = hilal
        d.rank = 1; d.points = 28; d.played = 10
        d.next = [live, m("d2", ittihad, hilal, 4 * 86400, "pre"), m("d3", hilal, ahli, 9 * 86400, "pre"),
                  m("d4", qadsiah, hilal, 15 * 86400, "pre")]
        d.last = [m("d5", shabab, hilal, -5 * 86400, "post", 0, 2), m("d6", hilal, fateh, -9 * 86400, "post", 3, 0),
                  m("d7", taawoun, hilal, -13 * 86400, "post", 1, 1), m("d8", hilal, ettifaq, -18 * 86400, "post", 4, 2),
                  m("d9", ahli, hilal, -23 * 86400, "post", 2, 1)]
        d.day = [live, m("d10", ittihad, ahli, 3 * 3600, "pre"), m("d11", qadsiah, shabab, 5 * 3600, "pre"),
                 m("d12", fateh, ettifaq, 26 * 3600, "pre"), m("d13", taawoun, ittihad, 28 * 3600, "pre"),
                 m("d14", ahli, qadsiah, 50 * 3600, "pre")]
        func r(_ rank: Int, _ t: STeam, _ w: Int, _ dr: Int, _ l: Int, _ gd: Int) -> SRow {
            SRow(rank: rank, team: t, gp: w + dr + l, w: w, d: dr, l: l, gd: gd, pts: w * 3 + dr, note: rank <= 4 ? "81D6AC" : "")
        }
        d.table = [r(1, hilal, 9, 1, 0, 21), r(2, nassr, 8, 2, 0, 17), r(3, qadsiah, 8, 1, 1, 12), r(4, ittihad, 7, 1, 2, 9),
                   r(5, ahli, 6, 2, 2, 7), r(6, ettifaq, 5, 2, 3, 3), r(7, shabab, 4, 3, 3, 1), r(8, taawoun, 4, 2, 4, -1)]
        func s(_ rank: Int, _ n: String, _ t: STeam, _ g: Int, _ a: Int) -> SScorer {
            SScorer(rank: rank, name: n, id: "", team: t, goals: g, assists: a, photo: "")
        }
        d.scorers = [s(1, "Cristiano Ronaldo", nassr, 12, 2), s(2, "A. Mitrović", hilal, 10, 3), s(3, "K. Benzema", ittihad, 9, 4),
                     s(4, "Ivan Toney", ahli, 8, 1), s(5, "Malcom", hilal, 7, 6), s(6, "J. Durán", nassr, 7, 2),
                     s(7, "M. Diaby", ittihad, 6, 5), s(8, "Riyad Mahrez", ahli, 5, 6), s(9, "Julián Quiñones", qadsiah, 5, 1),
                     s(10, "Sadio Mané", nassr, 4, 5)]
        return d
    }
}

// MARK: - أوامر الويدجت

enum SportsBridge {
    /// يضبطه التطبيق عند تشغيله (الدوري، المباراة) — فارغ = إيقاف المتابعة
    static var follow: ((String, String) async -> Void)? = nil
}

/// «تابع مباشرة» من الويدجت: يصحّي التطبيق في الخلفية ويبدأ المتابعة الصامتة
struct FollowMatchIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "متابعة المباراة مباشرة"
    static let isDiscoverable = false
    @Parameter(title: "الدوري") var league: String
    @Parameter(title: "المباراة") var match: String
    init() {}
    init(league: String, match: String) {
        self.league = league
        self.match = match
    }
    func perform() async throws -> some IntentResult {
        if let h = SportsBridge.follow { await h(league, match) }
        return .result()
    }
}

/// أسهم التنقّل بين مباريات اليوم
struct SportsPageIntent: AppIntent {
    static let title: LocalizedStringResource = "المباراة التالية"
    static let isDiscoverable = false
    @Parameter(title: "الويدجت") var kind: String
    @Parameter(title: "الخطوة") var delta: Int
    init() {}
    init(kind: String, delta: Int) {
        self.kind = kind
        self.delta = delta
    }
    func perform() async throws -> some IntentResult {
        SportsPage.step(kind, delta)
        return .result()
    }
}

enum SportsPage {
    static func get(_ kind: String) -> Int { AppGroup.defaults.integer(forKey: "sp_page_" + kind) }
    static func step(_ kind: String, _ d: Int) { AppGroup.defaults.set(get(kind) + d, forKey: "sp_page_" + kind) }
}

/// البطولة المعروضة (من «تعديل الأداة»)
enum LeagueOpt: String, AppEnum {
    case mine
    case ksa, kingsCup, gulfCup
    case egy, egyCup, uae, uaeCup, qat, mar, tun, alg, kuw, irq, jor, omn, arabCup
    case world, cwc, friendly, finalissima, olympics, u20, wwc
    case afc, acl2, asianCup, wcqAsia, aff, jpn, chn, aus, ind
    case cafCL, cafCC, afcon, afconQ, wcqAfrica, chan, rsa
    case ucl, uel, uecl, usc, euro, euroQ, unl, wcqEurope
    case eng, esp, ita, ger, fra, por, ned, tur, bel, sco, gre, aut, den, swe, nor, rus, eng2, esp2, ita2, ger2, fra2
    case faCup, eflCup, shield, copaRey, esSuper, coppa, itSuper, pokal, deSuper, cdf, frSuper, taca, knvb, scoCup
    case libertadores, sudamericana, copaAmerica, wcqSA, concacafCC, gold, wcqNA, leaguesCup, bra, arg, usa, mex
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "البطولة"
    static let caseDisplayRepresentations: [LeagueOpt: DisplayRepresentation] = [
        .mine: "حسب إعدادات التطبيق",
        .ksa: "دوري روشن السعودي",
        .kingsCup: "كأس الملك",
        .gulfCup: "كأس الخليج العربي",
        .egy: "الدوري المصري",
        .egyCup: "كأس مصر",
        .uae: "الدوري الإماراتي",
        .uaeCup: "كأس رئيس الدولة الإماراتي",
        .qat: "الدوري القطري",
        .mar: "الدوري المغربي",
        .tun: "الدوري التونسي",
        .alg: "الدوري الجزائري",
        .kuw: "الدوري الكويتي",
        .irq: "دوري نجوم العراق",
        .jor: "الدوري الأردني",
        .omn: "الدوري العُماني",
        .arabCup: "كأس العرب",
        .world: "كأس العالم",
        .cwc: "كأس العالم للأندية",
        .friendly: "مباريات دولية ودية",
        .finalissima: "الفيناليسيما",
        .olympics: "كرة القدم الأولمبية",
        .u20: "كأس العالم للشباب",
        .wwc: "كأس العالم للسيدات",
        .afc: "دوري أبطال آسيا للنخبة",
        .acl2: "دوري أبطال آسيا ٢",
        .asianCup: "كأس آسيا",
        .wcqAsia: "تصفيات كأس العالم: آسيا",
        .aff: "بطولة آسيان",
        .jpn: "الدوري الياباني",
        .chn: "الدوري الصيني",
        .aus: "الدوري الأسترالي",
        .ind: "الدوري الهندي",
        .cafCL: "دوري أبطال أفريقيا",
        .cafCC: "كأس الكونفدرالية الأفريقية",
        .afcon: "كأس أمم أفريقيا",
        .afconQ: "تصفيات كأس أمم أفريقيا",
        .wcqAfrica: "تصفيات كأس العالم: أفريقيا",
        .chan: "بطولة أمم أفريقيا للمحليين",
        .rsa: "الدوري الجنوب أفريقي",
        .ucl: "دوري أبطال أوروبا",
        .uel: "الدوري الأوروبي",
        .uecl: "دوري المؤتمر الأوروبي",
        .usc: "كأس السوبر الأوروبي",
        .euro: "كأس أمم أوروبا",
        .euroQ: "تصفيات كأس أمم أوروبا",
        .unl: "دوري الأمم الأوروبية",
        .wcqEurope: "تصفيات كأس العالم: أوروبا",
        .eng: "الدوري الإنجليزي",
        .esp: "الدوري الإسباني",
        .ita: "الدوري الإيطالي",
        .ger: "الدوري الألماني",
        .fra: "الدوري الفرنسي",
        .por: "الدوري البرتغالي",
        .ned: "الدوري الهولندي",
        .tur: "الدوري التركي",
        .bel: "الدوري البلجيكي",
        .sco: "الدوري الإسكتلندي",
        .gre: "الدوري اليوناني",
        .aut: "الدوري النمساوي",
        .den: "الدوري الدنماركي",
        .swe: "الدوري السويدي",
        .nor: "الدوري النرويجي",
        .rus: "الدوري الروسي",
        .eng2: "دوري البطولة الإنجليزية",
        .esp2: "الدرجة الثانية الإسبانية",
        .ita2: "الدرجة الثانية الإيطالية",
        .ger2: "الدرجة الثانية الألمانية",
        .fra2: "الدرجة الثانية الفرنسية",
        .faCup: "كأس الاتحاد الإنجليزي",
        .eflCup: "كأس الرابطة الإنجليزية",
        .shield: "درع المجتمع",
        .copaRey: "كأس ملك إسبانيا",
        .esSuper: "كأس السوبر الإسباني",
        .coppa: "كأس إيطاليا",
        .itSuper: "كأس السوبر الإيطالي",
        .pokal: "كأس ألمانيا",
        .deSuper: "كأس السوبر الألماني",
        .cdf: "كأس فرنسا",
        .frSuper: "كأس الأبطال الفرنسي",
        .taca: "كأس البرتغال",
        .knvb: "كأس هولندا",
        .scoCup: "كأس إسكتلندا",
        .libertadores: "كأس ليبرتادوريس",
        .sudamericana: "كأس سود أمريكانا",
        .copaAmerica: "كوبا أمريكا",
        .wcqSA: "تصفيات كأس العالم: أمريكا الجنوبية",
        .concacafCC: "كأس أبطال الكونكاكاف",
        .gold: "الكأس الذهبية",
        .wcqNA: "تصفيات كأس العالم: الكونكاكاف",
        .leaguesCup: "كأس الدوريات",
        .bra: "الدوري البرازيلي",
        .arg: "الدوري الأرجنتيني",
        .usa: "الدوري الأمريكي",
        .mex: "الدوري المكسيكي",
    ]
    var code: String {
        switch self {
        case .mine: return ""
        case .ksa: return "ksa.1"
        case .kingsCup: return "ksa.kings.cup"
        case .gulfCup: return "global.gulf_cup"
        case .egy: return "ls.egy.1"
        case .egyCup: return "ls.egy.cup"
        case .uae: return "ls.uae.1"
        case .uaeCup: return "ls.uae.cup"
        case .qat: return "ls.qat.1"
        case .mar: return "ls.mar.1"
        case .tun: return "ls.tun.1"
        case .alg: return "ls.alg.1"
        case .kuw: return "ls.kuw.1"
        case .irq: return "ls.irq.1"
        case .jor: return "ls.jor.1"
        case .omn: return "ls.omn.1"
        case .arabCup: return "ls.arab.cup"
        case .world: return "fifa.world"
        case .cwc: return "fifa.cwc"
        case .friendly: return "fifa.friendly"
        case .finalissima: return "global.finalissima"
        case .olympics: return "fifa.olympics"
        case .u20: return "fifa.world.u20"
        case .wwc: return "fifa.wwc"
        case .afc: return "afc.champions"
        case .acl2: return "afc.cup"
        case .asianCup: return "afc.asian.cup"
        case .wcqAsia: return "fifa.worldq.afc"
        case .aff: return "aff.championship"
        case .jpn: return "jpn.1"
        case .chn: return "chn.1"
        case .aus: return "aus.1"
        case .ind: return "ind.1"
        case .cafCL: return "caf.champions"
        case .cafCC: return "caf.confed"
        case .afcon: return "caf.nations"
        case .afconQ: return "caf.nations_qual"
        case .wcqAfrica: return "fifa.worldq.caf"
        case .chan: return "caf.championship"
        case .rsa: return "rsa.1"
        case .ucl: return "uefa.champions"
        case .uel: return "uefa.europa"
        case .uecl: return "uefa.europa.conf"
        case .usc: return "uefa.super_cup"
        case .euro: return "uefa.euro"
        case .euroQ: return "uefa.euroq"
        case .unl: return "uefa.nations"
        case .wcqEurope: return "fifa.worldq.uefa"
        case .eng: return "eng.1"
        case .esp: return "esp.1"
        case .ita: return "ita.1"
        case .ger: return "ger.1"
        case .fra: return "fra.1"
        case .por: return "por.1"
        case .ned: return "ned.1"
        case .tur: return "tur.1"
        case .bel: return "bel.1"
        case .sco: return "sco.1"
        case .gre: return "gre.1"
        case .aut: return "aut.1"
        case .den: return "den.1"
        case .swe: return "swe.1"
        case .nor: return "nor.1"
        case .rus: return "rus.1"
        case .eng2: return "eng.2"
        case .esp2: return "esp.2"
        case .ita2: return "ita.2"
        case .ger2: return "ger.2"
        case .fra2: return "fra.2"
        case .faCup: return "eng.fa"
        case .eflCup: return "eng.league_cup"
        case .shield: return "eng.charity"
        case .copaRey: return "esp.copa_del_rey"
        case .esSuper: return "esp.super_cup"
        case .coppa: return "ita.coppa_italia"
        case .itSuper: return "ita.super_cup"
        case .pokal: return "ger.dfb_pokal"
        case .deSuper: return "ger.super_cup"
        case .cdf: return "fra.coupe_de_france"
        case .frSuper: return "fra.super_cup"
        case .taca: return "por.taca.portugal"
        case .knvb: return "ned.cup"
        case .scoCup: return "sco.tennents"
        case .libertadores: return "conmebol.libertadores"
        case .sudamericana: return "conmebol.sudamericana"
        case .copaAmerica: return "conmebol.america"
        case .wcqSA: return "fifa.worldq.conmebol"
        case .concacafCC: return "concacaf.champions"
        case .gold: return "concacaf.gold"
        case .wcqNA: return "fifa.worldq.concacaf"
        case .leaguesCup: return "concacaf.leagues.cup"
        case .bra: return "bra.1"
        case .arg: return "arg.1"
        case .usa: return "usa.1"
        case .mex: return "mex.1"
        }
    }
}

struct SportsPosIntent: WidgetConfigurationIntent, Positioned {
    static let title: LocalizedStringResource = "إعداد الويدجت"
    static let description = IntentDescription("اختر البطولة المعروضة، وحدّد موضع الويدجت لتطابق الخلفية، واختر الخلفية والخط.")
    @Parameter(title: "البطولة", default: .mine) var league: LeagueOpt
    @Parameter(title: "المكان", default: .mr) var place: PlaceOpt
    @Parameter(title: "لون الخط", default: .app) var tint: TintOpt
    @Parameter(title: "الخلفية", default: .app) var bg: BgOpt
    @Parameter(title: "الخط", default: .app) var font: FontOpt
    var isGregorian: Bool { false }
    var bgOpt: BgOpt { bg }
    var fontOpt: FontOpt { font }
    var sportOpt: String { league.code }
    init() {}
}

// MARK: - بيانات دوري غير دوري فريقك (لويدجت اختار لها دوريًا آخر)

enum SportsLeagueCache {
    struct Item: Codable {
        var updated: Date
        var day: [SMatch]
        var table: [SRow]
        var scorers: [SScorer]
    }
    static func url(_ l: String) -> URL? { AppGroup.container?.appendingPathComponent("sports_\(l).json") }
    static func load(_ l: String) -> Item? {
        guard let u = url(l), let d = try? Data(contentsOf: u) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(Item.self, from: d)
    }
    static func fetch(_ l: String) async -> Item? {
        let now = Date()
        let from = ESPN.ymd(now.addingTimeInterval(-2 * 86400)), to = ESPN.ymd(now.addingTimeInterval(7 * 86400))
        // بالتتابع (ذاكرة الويدجت محدودة)
        var d = await ESPN.scoreboard(l, dates: from + "-" + to)
        if d.isEmpty { d = await ESPN.scoreboard(l) }   // أقرب جولة
        let t = await SportsLeagueCache.tableIf(l)
        let s = await ESPN.scorers(l)
        guard !d.isEmpty || !t.isEmpty else { return load(l) }
        var tmp = SportsData(); tmp.day = d
        let item = Item(updated: now, day: Sports.dayListPublic(d, now: now), table: t, scorers: s)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        if let u = url(l), let data = try? enc.encode(item) { try? data.write(to: u, options: .atomic) }
        tmp.table = t; tmp.scorers = s; tmp.day = item.day
        await SportsImages.ensure(tmp)
        return item
    }
    static func tableIf(_ l: String) async -> [SRow] {
        guard Leagues.get(l).hasTable else { return [] }
        return await ESPN.standings(l, team: SportsPrefs.teamId)
    }
    /// يطبّق دوريًا آخر على البيانات
    static func apply(_ l: String, to data: SportsData) async -> SportsData {
        var d = data
        var item = load(l)
        let live = item?.day.contains { $0.live } ?? false
        if item == nil || Date().timeIntervalSince(item!.updated) > (live ? 90 : 20 * 60) {
            item = await fetch(l) ?? item
        }
        guard let it = item else { return d }
        d.day = it.day; d.dayLeague = l
        if !it.table.isEmpty { d.table = it.table; d.tableLeague = l; d.scorers = it.scorers }
        else if !it.scorers.isEmpty { d.scorers = it.scorers }
        return d
    }
}

/// أسماء ويدجت شاشة القفل الخاصة بالمباريات
enum SportsLockKinds {
    static let all = ["lock.s.rect", "lock.s.circle", "lock.s.inline"]
}

// MARK: - جدولة ويدجت المباريات

enum SportsTimeline {
    private static let lock = NSLock()
    private static var running: Task<SportsData, Never>?

    /// تحديث واحد مشترك: لو طلبت عدة ويدجت التحديث في نفس اللحظة تنتظر نفس الجلب (ذاكرة الويدجت محدودة)
    private static func shared() async -> SportsData {
        let task: Task<SportsData, Never> = lock.withLock {
            if let r = running { return r }
            let t = Task { await Sports.refresh() }
            running = t
            return t
        }
        let v = await task.value
        lock.withLock { if running == task { running = nil } }
        return v
    }

    /// البيانات للويدجت: يحدّثها إذا قدمت (إلا إذا التطبيق يتابع مباراة الآن ويحدّث بنفسه)
    static func data(league: String, fetch: Bool) async -> SportsData {
        var d = SportsStore.load()
        if fetch && !SportsPrefs.isFollowingLive {
            let now = Date()
            let age = now.timeIntervalSince(d?.updated ?? .distantPast)
            if d == nil || age > 20 * 60 {
                d = await shared()
            } else if let f = d?.focus(at: now), f.live || (f.state == "pre" && f.date <= now) {
                if let m = await Sports.poll(f) { d = Sports.merge(m) }
            }
        }
        var out = d ?? SportsData()
        if !league.isEmpty && league != SportsPrefs.effectiveViewLeague {
            if fetch {
                out = await SportsLeagueCache.apply(league, to: out)
            } else if let it = SportsLeagueCache.load(league) {
                out.day = it.day; out.dayLeague = league
                if !it.table.isEmpty { out.table = it.table; out.tableLeague = league; out.scorers = it.scorers }
                else if !it.scorers.isEmpty { out.scorers = it.scorers }
            }
        }
        return out
    }

    /// أوقات المدخلات (عند بداية كل مباراة، ومنتصف الليل) وموعد التحديث
    static func plan(_ d: SportsData, now: Date) -> (dates: [Date], refresh: Date) {
        let horizon = now.addingTimeInterval(6 * 3600)
        let kicks = (d.next + d.day).filter { $0.state == "pre" && $0.date > now && $0.date < horizon }
            .map { $0.date.addingTimeInterval(2) }
        var set = Set([now, Cal.nextMidnight(after: now).addingTimeInterval(5)])
        for k in kicks { set.insert(k) }
        let dates = set.sorted()
        let live = (d.next + d.day).contains { $0.live }
        var refresh = now.addingTimeInterval(30 * 60)
        if live {
            refresh = now.addingTimeInterval(SportsPrefs.isFollowingLive ? 20 * 60 : 4 * 60)
        } else if let k = kicks.min(), k < refresh {
            refresh = k.addingTimeInterval(3 * 60)
        }
        return (dates, refresh)
    }
}

extension ESPN {
    /// فرق الدوري (لاختيار فريقك)
    static func teams(_ league: String) async -> [STeam] {
        if LS.owns(league) { return await LS.teams(league) }
        guard let j = await json(site + league + "/teams?limit=500") else { return [] }
        let list = j.a("sports").first?.a("leagues").first?.a("teams") ?? []
        return list.compactMap { $0.o("team") }.map { team($0) }.sorted { $0.display < $1.display }
    }
}
