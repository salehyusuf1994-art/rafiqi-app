import SwiftUI
import WidgetKit
import AppIntents

// MARK: - مكوّنات ويدجت المباريات

let S_RED = Color(red: 1.0, green: 0.31, blue: 0.31)
let S_GREEN = Color(red: 0.32, green: 0.80, blue: 0.50)
let S_YELLOW = Color(red: 1.0, green: 0.82, blue: 0.20)

private struct STintKey: EnvironmentKey { static let defaultValue: Color = .white }
extension EnvironmentValues {
    /// لون النص في ويدجت المباريات (الشعارات تبقى بألوانها)
    var sTint: Color {
        get { self[STintKey.self] }
        set { self[STintKey.self] = newValue }
    }
}

/// غلاف ويدجت المباريات: نفس الخلفيات، لكن اللون على النص فقط (الشعارات بألوانها الأصلية)
struct SRoot<Content: View>: View {
    let entry: HEntry
    @ViewBuilder let content: (SportsData) -> Content
    private var plain: HEntry {
        var e = entry
        e.tint = .white
        return e
    }
    var body: some View {
        let d = entry.sports ?? SportsData()
        Root(entry: plain) {
            if d.hasTeam || !d.day.isEmpty || !d.table.isEmpty {
                content(d)
            } else {
                SEmpty()
            }
        }
        .environment(\.sTint, entry.tint)
    }
}

/// ملاحظة داخل الويدجت عند غياب البيانات (بطولة بلا ترتيب أو هدافين أو مباريات قريبة)
struct SNote: View {
    let ar: String
    let en: String
    var body: some View {
        VStack {
            Spacer(minLength: 0)
            SName(text: Lang.isEN ? en : ar, size: 12, dim: true).multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
let S_NO_TABLE = SNote(ar: "لا يوجد ترتيب لهذه البطولة", en: "No standings for this competition")
let S_NO_SCORERS = SNote(ar: "لا توجد قائمة هدافين لهذه البطولة", en: "No top scorers for this competition")
let S_NO_DAY = SNote(ar: "لا توجد مباريات قريبة", en: "No upcoming matches")

struct SEmpty: View {
    @Environment(\.sTint) private var tint
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "soccerball").font(.system(size: 26, weight: .semibold)).foregroundStyle(tint.opacity(0.8))
            Text(Lang.isEN ? "Open Rafiqi and pick your team" : "افتح رفيقي واختر فريقك")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(tint.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(14)
    }
}

enum SFont {
    static func name(_ size: CGFloat, _ wf: WFont, _ w: Font.Weight = .semibold) -> Font {
        if Lang.isEN && !wf.latin { return .system(size: size, weight: w, design: .rounded) }
        // الخطوط الزخرفية لا تُقرأ في الأحجام الصغيرة (اسم النادي تحت اللاعب، تسميات الأعمدة): خط واضح
        if size < 12, [.thuluth, .nastaliq, .katibeh, .blaka, .ruqaa].contains(wf) {
            return .custom(WFont.tajawal.ps, size: size)
        }
        switch wf {
        case .thuluth: return .custom(wf.ps, size: size * 1.22)
        case .nastaliq: return .custom(wf.ps, size: size * 1.1)
        case .blaka, .katibeh: return .custom(wf.ps, size: size * 1.12)
        default: return .custom(wf.ps, size: size)
        }
    }
    static func latin(_ size: CGFloat, _ w: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: w, design: .rounded)
    }
}

enum SColor {
    static func of(_ id: String) -> Color {
        let n = id.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 997 }
        return Color(hue: Double(n % 360) / 360, saturation: 0.55, brightness: 0.62)
    }
    static func form(_ r: String) -> Color { r == "W" ? S_GREEN : r == "L" ? S_RED : Color.white.opacity(0.62) }
}

enum STime {
    static func time(_ d: Date) -> String { hm12(d) }
    static func ampm(_ d: Date) -> String {
        if Settings.use24h { return "" }
        let am = Cal.gregCal.component(.hour, from: d) < 12
        return Lang.isEN ? (am ? "AM" : "PM") : (am ? "ص" : "م")
    }
    static func date(_ d: Date) -> String {
        let c = Cal.gregCal.dateComponents([.day, .month], from: d)
        let m = max(0, min(11, (c.month ?? 1) - 1))
        if Lang.isEN { return "\(Words.gmEN[m].prefix(3)) \(c.day ?? 1)" }
        let names = Settings.shamiMonths ? Words.gs : Words.gm
        return "\(ar(c.day ?? 1)) \(names[m])"
    }
    static func weekday(_ d: Date) -> String {
        let i = Cal.weekday(d)
        return Lang.isEN ? String(Words.wdEN[i].prefix(3)) : Words.wd[i]
    }
    static func day(_ d: Date, now: Date) -> String {
        let c = Cal.gregCal
        if c.isDate(d, inSameDayAs: now) { return Lang.isEN ? "Today" : "اليوم" }
        if let t = c.date(byAdding: .day, value: 1, to: now), c.isDate(d, inSameDayAs: t) { return Lang.isEN ? "Tomorrow" : "غدًا" }
        if let y = c.date(byAdding: .day, value: -1, to: now), c.isDate(d, inSameDayAs: y) { return Lang.isEN ? "Yesterday" : "أمس" }
        return date(d)
    }
    static func full(_ d: Date, now: Date) -> String {
        let c = Cal.gregCal
        if abs(c.dateComponents([.day], from: c.startOfDay(for: now), to: c.startOfDay(for: d)).day ?? 9) <= 1 { return day(d, now: now) }
        return "\(weekday(d)) \(date(d))"
    }
}

/// صورة بألوانها حتى في الشاشة الملوّنة (iOS 18)
struct SImage: View {
    let img: UIImage
    var body: some View {
        if #available(iOS 18.0, *) {
            Image(uiImage: img).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFit()
        } else {
            Image(uiImage: img).resizable().scaledToFit()
        }
    }
}

struct SLogo: View {
    let team: STeam
    var size: CGFloat
    var body: some View {
        Group {
            if let img = SportsImages.image(team.logo) {
                SImage(img: img)
            } else {
                ZStack {
                    Circle().fill(SColor.of(team.id))
                    Text(team.abbr.isEmpty ? "?" : team.abbr)
                        .font(.system(size: size * 0.3, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.4)
                        .padding(size * 0.1)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// صورة اللاعب (أو أول حرف من اسمه)
struct SPhoto: View {
    let name: String
    let url: String
    var size: CGFloat
    @Environment(\.sTint) private var tint
    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.14))
            if let img = SportsImages.image(url) {
                SImage(img: img).scaleEffect(1.15, anchor: .top).clipShape(Circle())
            } else {
                Text(String(name.split(separator: " ").last?.prefix(1) ?? "?"))
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded)).foregroundStyle(tint.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
    }
}

struct SName: View {
    let text: String
    var size: CGFloat
    var dim = false
    var weight: Font.Weight = .semibold
    var color: Color? = nil
    @Environment(\.wfont) private var wf
    @Environment(\.sTint) private var tint
    var body: some View {
        // اسم لاتيني (فريق بلا اسم عربي): الخطوط العربية الزخرفية تُسقط بعض حروفه، فنرسمه بخط واضح
        let latinOnly = !text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
        Text(text).font(latinOnly && !wf.latin ? SFont.latin(size, weight) : SFont.name(size, wf, weight))
            .foregroundStyle(color ?? (dim ? tint.opacity(0.55) : tint))
            .lineLimit(1).minimumScaleFactor(0.5)
    }
}

/// نص لاتيني (أسماء اللاعبين والاختصارات)
struct SLatin: View {
    let text: String
    var size: CGFloat
    var dim = false
    var weight: Font.Weight = .semibold
    var color: Color? = nil
    @Environment(\.sTint) private var tint
    var body: some View {
        Text(text).font(SFont.latin(size, weight))
            .foregroundStyle(color ?? (dim ? tint.opacity(0.55) : tint))
            .lineLimit(1).minimumScaleFactor(0.55)
    }
}

/// اسم الفريق المختصر: العربي إن عُرف، وإلا الاختصار اللاتيني
struct STag: View {
    let team: STeam
    var size: CGFloat
    var dim = false
    var weight: Font.Weight = .bold
    var body: some View {
        if let a = team.knownAr {
            SName(text: a, size: size, dim: dim, weight: weight)
        } else {
            SLatin(text: team.abbr, size: size, dim: dim, weight: weight)
        }
    }
}

struct SNum: View {
    let text: String
    var size: CGFloat
    var dim = false
    var color: Color? = nil
    @Environment(\.wfont) private var wf
    @Environment(\.sTint) private var tint
    var body: some View {
        Text(text).font(digitFont(size, bold: true, wf))
            .foregroundStyle(color ?? (dim ? tint.opacity(0.55) : tint))
            .lineLimit(1).minimumScaleFactor(0.5)
            .environment(\.layoutDirection, .leftToRight)
    }
}

struct SLine: View {
    @Environment(\.sTint) private var tint
    var body: some View { Rectangle().fill(tint.opacity(0.13)).frame(height: 0.7) }
}

/// الوقت مع ص/م
struct STimeText: View {
    let date: Date
    var size: CGFloat
    var dim = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.15) {
            SNum(text: STime.time(date), size: size, dim: dim)
            if !STime.ampm(date).isEmpty { SName(text: STime.ampm(date), size: size * 0.5, dim: true) }
        }
    }
}

/// النتيجة: رقم الفريق الأول بجانبه (يمين في العربي)
struct SScore: View {
    let m: SMatch
    var size: CGFloat
    /// في صفوف مباريات فريقك: نتيجته أولًا (مع شارة فوز/خسارة) بدل ترتيب المضيف والضيف
    var team: String? = nil
    @Environment(\.sTint) private var tint
    var body: some View {
        let mineFirst = team.map { !m.isHome($0) } ?? false
        let a = mineFirst ? (m.aws ?? 0) : (m.hs ?? 0), b = mineFirst ? (m.hs ?? 0) : (m.aws ?? 0)
        HStack(spacing: size * 0.22) {
            SNum(text: ar(a), size: size)
            Capsule().fill(tint.opacity(0.75)).frame(width: size * 0.3, height: max(2, size * 0.07))
            SNum(text: ar(b), size: size)
        }
    }
}

/// حالة المباراة: الدقيقة لحظيًا، أو استراحة، أو انتهت
struct SStatus: View {
    let m: SMatch
    let now: Date
    var size: CGFloat
    var body: some View {
        if m.running || (m.state == "pre" && m.date <= now && !m.postponed) {
            HStack(spacing: size * 0.3) {
                Circle().fill(S_RED).frame(width: size * 0.42, height: size * 0.42)
                Text(timerInterval: (m.state == "pre" ? m.date : m.clockStart)...Date.distantFuture,
                     countsDown: false, showsHours: false)
                    .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(S_RED)
                    .multilineTextAlignment(.center)
                    .frame(width: size * 2.9)
            }
            .environment(\.layoutDirection, .leftToRight)
        } else if m.halftime {
            SName(text: Lang.isEN ? "Half-time" : "استراحة", size: size, color: S_RED)
        } else if m.shootout {
            SName(text: Lang.isEN ? "Penalties" : "ركلات الترجيح", size: size, color: S_RED)
        } else if m.live {
            SLatin(text: m.detail, size: size, color: S_RED)
        } else if m.postponed {
            SName(text: Lang.isEN ? "Postponed" : "مؤجّلة", size: size, dim: true)
        } else if m.done {
            SName(text: Lang.isEN ? "Full time" : "انتهت", size: size, dim: true)
        } else {
            SName(text: STime.full(m.date, now: now), size: size, dim: true)
        }
    }
}

/// الوسط: الوقت قبل المباراة، والنتيجة أثناءها وبعدها
struct SCenter: View {
    let m: SMatch
    let now: Date
    var size: CGFloat
    var body: some View {
        VStack(spacing: size * 0.14) {
            if (m.state == "pre" && m.date > now) || m.postponed {
                STimeText(date: m.date, size: size * 0.82)
                SName(text: m.postponed ? (Lang.isEN ? "Postponed" : "مؤجّلة") : STime.full(m.date, now: now), size: size * 0.32, dim: true)
            } else {
                SScore(m: m, size: size)
                SStatus(m: m, now: now, size: size * 0.32)
            }
        }
    }
}

/// شارة النتيجة: ف / ت / خ
struct SForm: View {
    let r: String
    var size: CGFloat
    var body: some View {
        let t = Lang.isEN ? r : (r == "W" ? "ف" : r == "L" ? "خ" : "ت")
        Text(t).font(.system(size: size * 0.62, weight: .heavy, design: .rounded))
            .foregroundStyle(SColor.form(r))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24).fill(SColor.form(r).opacity(0.22)))
    }
}

struct SCard: View {
    let red: Bool
    let n: Int
    var size: CGFloat
    var body: some View {
        Text(ar(n)).font(.system(size: size * 0.7, weight: .heavy, design: .rounded))
            .foregroundStyle(red ? Color.white : Color.black)
            .frame(width: size * 0.78, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.14).fill(red ? S_RED : S_YELLOW))
    }
}

/// عمود الفريق: الشعار والاسم، مع البطاقات فوقه
struct STeamCol: View {
    let m: SMatch
    let home: Bool
    var logo: CGFloat
    var name: CGFloat
    var cards = true
    var body: some View {
        let t = home ? m.home : m.away
        let reds = m.reds(t.id), yel = m.yellows(t.id)
        VStack(spacing: logo * 0.12) {
            if cards {
                HStack(spacing: 3) {
                    if yel > 0 { SCard(red: false, n: yel, size: logo * 0.3) }
                    if reds > 0 { SCard(red: true, n: reds, size: logo * 0.3) }
                }
                .frame(height: logo * 0.3)
            }
            SLogo(team: t, size: logo)
            SName(text: t.display, size: name)
        }
    }
}

/// زر المتابعة المباشرة (أو شارة «مباشر» إذا كانت شغّالة)
struct SFollowButton: View {
    let m: SMatch
    let now: Date
    var size: CGFloat = 11
    var body: some View {
        let soon = m.state == "pre" && m.date.timeIntervalSince(now) < 3 * 3600
        if SportsPrefs.following == m.id && SportsPrefs.isFollowingLive {
            HStack(spacing: 3) {
                Circle().fill(.white).frame(width: size * 0.45, height: size * 0.45)
                Text(Lang.isEN ? "LIVE" : "مباشر").font(.system(size: size, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, size * 0.6).padding(.vertical, size * 0.25)
            .background(Capsule().fill(S_RED))
        } else if m.live || soon {
            Button(intent: FollowMatchIntent(league: m.league, match: m.id)) {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill").font(.system(size: size * 0.85, weight: .bold))
                    Text(Lang.isEN ? "Follow live" : "تابع مباشرة").font(.system(size: size, weight: .bold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, size * 0.7).padding(.vertical, size * 0.3)
                .background(Capsule().fill(Color(red: 0.93, green: 0.80, blue: 0.52)))
            }
            .buttonStyle(.plain)
        }
    }
}

/// اسم البطولة (والجولة)
func sLeagueLine(_ m: SMatch) -> String {
    let l = Leagues.get(m.league), n = l.name
    // رقم الجولة للدوريات فقط (في الكؤوس رقم الأسبوع لا يعني جولة)
    guard l.kind == .league, !m.round.isEmpty, let r = Int(m.round) else { return n }
    return Lang.isEN ? "\(n) · Round \(r)" : "\(n) · الجولة \(ar(r))"
}

/// رقمان يُعرضان بالترتيب المكتوب من اليسار لليمين.
/// الأرقام العربية (٠١٢) تنعكس تلقائيًا في النص، فعلامة LRM حول الفاصل تُبقي الترتيب كما كُتب
func lrmPair(_ a: String, _ b: String, _ sep: String = " - ") -> String { a + "\u{200E}" + sep + "\u{200E}" + b }

/// النتيجة نصًّا لعرضه من اليسار لليمين: في العربي رقم المستضيف يمين (بجانب شعاره)
func sScoreText(_ m: SMatch, sep: String = " - ") -> String {
    Lang.isEN ? "\(m.hs ?? 0)\(sep)\(m.aws ?? 0)" : lrmPair(ar(m.aws ?? 0), ar(m.hs ?? 0), sep)
}

/// النتيجة داخل نص عربي متصل (علامة RLM تُبقي رقم المستضيف أولًا حتى بالأرقام الإنجليزية)
func sScoreInline(_ m: SMatch, sep: String = "-") -> String {
    Lang.isEN ? "\(m.hs ?? 0)\(sep)\(m.aws ?? 0)" : "\(ar(m.hs ?? 0))\u{200F}\(sep)\u{200F}\(ar(m.aws ?? 0))"
}

func sRankLine(_ d: SportsData) -> String {
    guard d.rank > 0 else { return d.leagueName }
    return Lang.isEN ? "#\(d.rank) · \(d.points) pts" : "#\(ar(d.rank)) · \(pointsText(d.points))"
}

/// صف مباراة: الشعار والاسم يمين ويسار، والوقت أو النتيجة في الوسط
struct SMatchRow: View {
    let m: SMatch
    let now: Date
    var logo: CGFloat = 22
    var name: CGFloat = 13
    var names = true
    var mine = ""
    var body: some View {
        HStack(spacing: 8) {
            SLogo(team: m.home, size: logo)
            if names { SName(text: m.home.display, size: name, weight: m.home.id == mine ? .bold : .semibold) }
            Spacer(minLength: 2)
            VStack(spacing: 1) {
                if (m.state == "pre" && m.date > now) || m.postponed {
                    STimeText(date: m.date, size: name * 1.08)
                    SName(text: STime.day(m.date, now: now), size: name * 0.72, dim: true)
                } else {
                    SScore(m: m, size: name * 1.1)
                    SStatus(m: m, now: now, size: name * 0.66)
                }
            }
            .frame(minWidth: logo * 2.4)
            Spacer(minLength: 2)
            if names { SName(text: m.away.display, size: name, weight: m.away.id == mine ? .bold : .semibold) }
            SLogo(team: m.away, size: logo)
        }
    }
}

/// صف من مباريات فريقك: الخصم وأرضه، والوقت أو النتيجة
struct SFixtureRow: View {
    let m: SMatch
    let team: String
    let now: Date
    var logo: CGFloat = 20
    var size: CGFloat = 13
    var showVenue = true
    var showDay = true
    /// صغيرة: التاريخ فقط، أو الوقت فوق اليوم
    var dateOnly = false
    var stacked = false
    var body: some View {
        let opp = m.opponent(of: team)
        HStack(spacing: 7) {
            SLogo(team: opp, size: logo)
            STag(team: opp, size: size)
            if showVenue {
                SName(text: m.isHome(team) ? (Lang.isEN ? "Home" : "على أرضه") : (Lang.isEN ? "Away" : "خارج أرضه"),
                      size: size * 0.78, dim: true)
            }
            Spacer(minLength: 4)
            if (m.state == "pre" && m.date > now) || m.postponed {
                if dateOnly {
                    SName(text: STime.day(m.date, now: now), size: size * 0.85, dim: true)
                } else if stacked {
                    VStack(alignment: .trailing, spacing: 0) {
                        STimeText(date: m.date, size: size * 0.92)
                        SName(text: STime.day(m.date, now: now), size: size * 0.7, dim: true)
                    }
                } else {
                    if showDay { SName(text: STime.full(m.date, now: now), size: size * 0.82, dim: true) }
                    STimeText(date: m.date, size: size * 0.95)
                }
            } else {
                if m.live || (m.state == "pre") { SStatus(m: m, now: now, size: size * 0.75) }
                SScore(m: m, size: size, team: team)
                if let r = m.result(for: team) { SForm(r: r, size: size * 1.2) }
            }
        }
    }
}

struct STableRow: View {
    let r: SRow
    var mine = false
    var size: CGFloat = 13
    var gd = false
    @Environment(\.sTint) private var tint
    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5).fill(r.note.isEmpty ? Color.clear : Color(hex: r.note))
                .frame(width: 3, height: size * 1.2)
            SNum(text: ar(r.rank), size: size * 0.9, dim: true).frame(width: size * 1.4)
            SLogo(team: r.team, size: size * 1.4)
            SName(text: r.team.display, size: size, weight: mine ? .bold : .semibold)
            Spacer(minLength: 4)
            SNum(text: ar(r.gp), size: size * 0.9, dim: true).frame(width: size * 1.8)
            if gd { SNum(text: r.gd > 0 ? "+\(ar(r.gd))" : ar(r.gd), size: size * 0.9, dim: true).frame(width: size * 2.2) }
            SNum(text: ar(r.pts), size: size * 1.05).frame(width: size * 2)
        }
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(mine ? 0.09 : 0)))
    }
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

struct SScorerRow: View {
    let s: SScorer
    var size: CGFloat = 13
    var assists = false
    var body: some View {
        HStack(spacing: 7) {
            SNum(text: ar(s.rank), size: size * 0.85, dim: true).frame(width: size * 1.3)
            SPhoto(name: s.name, url: s.photo, size: size * 1.7)
            VStack(alignment: .leading, spacing: 0) {
                SLatin(text: s.name, size: size)
                if assists { SName(text: s.team.display, size: size * 0.7, dim: true) }
            }
            Spacer(minLength: 4)
            if assists { SNum(text: ar(s.assists), size: size * 0.9, dim: true).frame(width: size * 1.8) }
            SNum(text: ar(s.goals), size: size * 1.1).frame(width: size * 1.8)
        }
    }
}

/// صف هدف: الدقيقة، اللاعب، والفريق
struct SGoalRow: View {
    let k: SKey
    let m: SMatch
    var size: CGFloat = 13
    var photo = true
    var body: some View {
        let t = k.team == m.home.id ? m.home : m.away
        HStack(spacing: 7) {
            SLatin(text: k.minute, size: size * 0.85, dim: true).frame(width: size * 2.4, alignment: .leading)
            if photo { SPhoto(name: k.player, url: k.pid.isEmpty ? "" : "https://a.espncdn.com/i/headshots/soccer/players/full/\(k.pid).png", size: size * 1.6) }
            SLatin(text: k.player + (k.kind == "pen" ? " (P)" : k.kind == "og" ? " (OG)" : ""), size: size)
            Spacer(minLength: 4)
            STag(team: t, size: size * 0.82, dim: true, weight: .semibold)
            Image(systemName: "soccerball").font(.system(size: size * 0.9, weight: .semibold))
        }
    }
}

/// الحدث (هدف أو بطاقة) في عمود الفريق
struct SEventCell: View {
    let k: SKey
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: 5) {
            SLatin(text: k.minute, size: size * 0.85, dim: true)
            if k.isGoal {
                Image(systemName: "soccerball").font(.system(size: size * 0.9, weight: .semibold))
            } else {
                RoundedRectangle(cornerRadius: 1.5).fill(k.kind == "red" ? S_RED : S_YELLOW).frame(width: size * 0.6, height: size * 0.85)
            }
            SLatin(text: k.player, size: size)
            Spacer(minLength: 0)
        }
    }
}

/// الشريط السفلي: المباراة التالية
struct SNextBar: View {
    let m: SMatch
    let now: Date
    var size: CGFloat = 11
    var body: some View {
        HStack(spacing: 6) {
            SName(text: STime.full(m.date, now: now), size: size)
            Spacer(minLength: 4)
            SLogo(team: m.home, size: size * 1.5)
            SName(text: m.home.display, size: size)
            SName(text: "–", size: size, dim: true)
            SName(text: m.away.display, size: size)
            SLogo(team: m.away, size: size * 1.5)
            Spacer(minLength: 4)
            STimeText(date: m.date, size: size)
        }
    }
}

extension SportsData {
    /// مباريات اليوم مع الصفحة الحالية (لأسهم التنقّل)
    func dayPick(_ kind: String) -> SMatch? {
        guard !day.isEmpty else { return focus() }
        let n = day.count
        let p = ((SportsPage.get(kind) % n) + n) % n
        return day[p]
    }
    func nextAfter(_ m: SMatch?) -> SMatch? {
        upcoming(4).first { $0.id != m?.id && !$0.live }
    }
    func rowsFor(_ n: Int) -> [SRow] {
        let table = groupTable
        guard let t = team?.id, let mine = table.first(where: { $0.team.id == t }), mine.rank > n else { return Array(table.prefix(n)) }
        return Array(table.prefix(n - 1)) + [mine]
    }
}

// MARK: - صغيرة

/// فريقي: الشعار والترتيب، وثلاث مباريات قادمة
struct SportsTeamSmallView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            let t = d.team ?? STeam.empty
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    SLogo(team: t, size: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        SName(text: t.display, size: 15)
                        SName(text: sRankLine(d), size: 10, dim: true)
                    }
                    Spacer(minLength: 0)
                }
                SLine()
                ForEach(Array(d.upcoming(3).enumerated()), id: \.offset) { i, m in
                    if i > 0 { SLine() }
                    SFixtureRow(m: m, team: t.id, now: entry.date, logo: 20, size: 13, showVenue: false, dateOnly: true)
                        .frame(maxHeight: .infinity)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
        }
    }
}

/// مباراة: البطولة والفريقان والموعد أو النتيجة
struct SportsMatchSmallView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            if let m = d.focus(at: entry.date) {
                VStack(alignment: .leading, spacing: 6) {
                    SName(text: Leagues.get(m.league).name, size: 12)
                    if Leagues.get(m.league).kind == .league, !m.round.isEmpty, let r = Int(m.round) {
                        SName(text: Lang.isEN ? "Round \(r)" : "الجولة \(ar(r))", size: 10, dim: true)
                    }
                    Spacer(minLength: 0)
                    teamRow(m.home, m.hs, m)
                    teamRow(m.away, m.aws, m)
                    Spacer(minLength: 0)
                    if m.state == "pre" && m.date > entry.date {
                        HStack(spacing: 4) {
                            SName(text: STime.full(m.date, now: entry.date), size: 10, dim: true)
                            SName(text: "•", size: 10, dim: true)
                            STimeText(date: m.date, size: 11, dim: true)
                        }
                    } else {
                        SStatus(m: m, now: entry.date, size: 11)
                    }
                }
                .padding(14)
            } else { SEmpty() }
        }
    }
    func teamRow(_ t: STeam, _ s: Int?, _ m: SMatch) -> some View {
        HStack(spacing: 8) {
            SLogo(team: t, size: 26)
            SName(text: t.display, size: 15)
            Spacer(minLength: 2)
            if m.state != "pre" { SNum(text: ar(s ?? 0), size: 18) }
        }
    }
}

/// مباريات: ثلاث مباريات بالشعارات والموعد
struct SportsMatchesSmallView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            VStack(spacing: 4) {
                if d.day.isEmpty { S_NO_DAY }
                ForEach(Array(d.day.prefix(3).enumerated()), id: \.offset) { i, m in
                    if i > 0 { SLine() }
                    SMatchRow(m: m, now: entry.date, logo: 24, name: 13, names: false)
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(13)
        }
    }
}

/// الهدافون: أول ثلاثة
struct SportsScorersSmallView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            VStack(spacing: 4) {
                SName(text: Lang.isEN ? "Top scorers" : "الهدافون", size: 13)
                if d.scorers.isEmpty { S_NO_SCORERS }
                ForEach(Array(d.scorers.prefix(3).enumerated()), id: \.offset) { i, s in
                    if i > 0 { SLine() }
                    SScorerRow(s: s, size: 13).frame(maxHeight: .infinity)
                }
            }
            .padding(13)
        }
    }
}

/// مباريات فريقي (نتائجه بالنقاط الملوّنة)
struct SportsFormSmallView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            let t = d.team ?? STeam.empty
            let rows = sRows(d)
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    SLogo(team: t, size: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        SName(text: t.display, size: 14)
                        HStack(spacing: 3) {
                            ForEach(Array(d.form.enumerated()), id: \.offset) { _, r in
                                Circle().fill(SColor.form(r)).frame(width: 6, height: 6)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                SLine()
                ForEach(Array(rows.enumerated()), id: \.offset) { i, m in
                    if i > 0 { SLine() }
                    SFixtureRow(m: m, team: t.id, now: entry.date, logo: 18, size: 12, showVenue: false, stacked: true)
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(13)
        }
    }
    func sRows(_ d: SportsData) -> [SMatch] {
        var out: [SMatch] = []
        if let f = d.focus(at: entry.date) { out.append(f) }
        for m in d.upcoming(4) where !out.contains(where: { $0.id == m.id }) { out.append(m) }
        return Array(out.prefix(3))
    }
}

/// بطاقة المباراة: الحالة فوق، والفريقان بالنتيجة
struct SportsCardSmallView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            if let m = d.focus(at: entry.date) {
                VStack(spacing: 7) {
                    HStack {
                        SName(text: Leagues.get(m.league).name, size: 11)
                        Spacer(minLength: 2)
                    }
                    if m.state != "pre" || m.date <= entry.date {
                        HStack { SStatus(m: m, now: entry.date, size: 10); Spacer(minLength: 0) }
                    }
                    Spacer(minLength: 0)
                    row(m.home, m.hs, m)
                    row(m.away, m.aws, m)
                    Spacer(minLength: 0)
                    HStack {
                        SName(text: STime.day(m.date, now: entry.date), size: 10, dim: true)
                        Spacer()
                        STimeText(date: m.date, size: 11, dim: true)
                    }
                }
                .padding(13)
            } else { SEmpty() }
        }
    }
    func row(_ t: STeam, _ s: Int?, _ m: SMatch) -> some View {
        HStack(spacing: 7) {
            SLogo(team: t, size: 22)
            SName(text: t.display, size: 14)
            Spacer(minLength: 2)
            SNum(text: m.state == "pre" ? "–" : ar(s ?? 0), size: 18)
        }
    }
}

/// أحداث المباراة: النتيجة وأهدافها
struct SportsEventsSmallView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            if let m = d.focus(at: entry.date) {
                VStack(spacing: 6) {
                    HStack(spacing: 5) {
                        SLogo(team: m.home, size: 20)
                        SLatin(text: m.home.abbr, size: 11, weight: .bold)
                        Spacer(minLength: 2)
                        VStack(spacing: 1) {
                            if m.postponed {
                                SName(text: Lang.isEN ? "Postponed" : "مؤجّلة", size: 11, dim: true)
                            } else if m.state == "pre" && m.date > entry.date {
                                STimeText(date: m.date, size: 14)
                            } else {
                                SScore(m: m, size: 16)
                                SStatus(m: m, now: entry.date, size: 9)
                            }
                        }
                        Spacer(minLength: 2)
                        SLatin(text: m.away.abbr, size: 11, weight: .bold)
                        SLogo(team: m.away, size: 20)
                    }
                    SLine()
                    if m.goals.isEmpty {
                        Spacer(minLength: 0)
                        SName(text: m.state == "pre" ? (Lang.isEN ? "Not started" : "لم تبدأ بعد") : sNoGoalsText(m),
                              size: 12, dim: true)
                        Spacer(minLength: 0)
                    } else {
                        ForEach(Array(m.goals.suffix(3).enumerated()), id: \.offset) { i, k in
                            if i > 0 { SLine() }
                            SGoalRow(k: k, m: m, size: 11, photo: false).frame(maxHeight: .infinity)
                        }
                    }
                }
                .padding(13)
            } else { SEmpty() }
        }
    }
}

/// النتيجة الكبيرة
struct SportsScoreSmallView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            if let m = d.focus(at: entry.date) {
                VStack(spacing: 4) {
                    SName(text: Leagues.get(m.league).name, size: 10, dim: true)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        STeamCol(m: m, home: true, logo: 40, name: 11, cards: false).frame(width: 48)
                        Spacer(minLength: 0)
                        SCenter(m: m, now: entry.date, size: 24)
                        Spacer(minLength: 0)
                        STeamCol(m: m, home: false, logo: 40, name: 11, cards: false).frame(width: 48)
                    }
                    Spacer(minLength: 0)
                    SFollowButton(m: m, now: entry.date, size: 10)
                }
                .padding(12)
            } else { SEmpty() }
        }
    }
}

// MARK: - متوسطة

/// المباراة: الشعاران الكبيران والنتيجة، والمباراة التالية تحت
struct SportsMatchMediumView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            if let m = d.focus(at: entry.date) {
                VStack(spacing: 6) {
                    ZStack {
                        SName(text: sLeagueLine(m), size: 12, dim: true)
                        HStack { SFollowButton(m: m, now: entry.date, size: 10); Spacer() }
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    HStack(spacing: 6) {
                        STeamCol(m: m, home: true, logo: 50, name: 13).frame(width: 96)
                        Spacer(minLength: 0)
                        SCenter(m: m, now: entry.date, size: 38)
                        Spacer(minLength: 0)
                        STeamCol(m: m, home: false, logo: 50, name: 13).frame(width: 96)
                    }
                    .frame(maxHeight: .infinity)
                    if let n = d.nextAfter(m) {
                        SLine()
                        SNextBar(m: n, now: entry.date, size: 11)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            } else { SEmpty() }
        }
    }
}

/// مواجهة اليوم: تتنقّل بين مباريات اليوم بالأسهم
struct SportsVsMediumView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            if let m = d.dayPick(entry.kind) {
                VStack(spacing: 4) {
                    SName(text: sLeagueLine(m), size: 12, dim: true)
                    HStack(spacing: 4) {
                        arrow(-1, Lang.isEN ? "chevron.left" : "chevron.right")
                        STeamCol(m: m, home: true, logo: 54, name: 13).frame(width: 90)
                        Spacer(minLength: 0)
                        SCenter(m: m, now: entry.date, size: 40)
                        Spacer(minLength: 0)
                        STeamCol(m: m, home: false, logo: 54, name: 13).frame(width: 90)
                        arrow(1, Lang.isEN ? "chevron.right" : "chevron.left")
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 10).padding(.vertical, 12)
            } else { SEmpty() }
        }
    }
    func arrow(_ delta: Int, _ icon: String) -> some View {
        Button(intent: SportsPageIntent(kind: entry.kind, delta: delta)) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
                .frame(width: 22, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(entry.tint.opacity(0.6))
    }
}

/// الأهداف: النتيجة فوق، وأهداف المباراة بالصور
struct SportsGoalsMediumView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            if let m = d.focus(at: entry.date) {
                VStack(spacing: 5) {
                    SScoreHeader(m: m, now: entry.date, logo: 22, size: 14)
                    SLine()
                    SGoalsList(m: m, now: entry.date, count: 3, size: 13)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            } else { SEmpty() }
        }
    }
}

/// سطر النتيجة: الشعار والاسم والنتيجة
struct SScoreHeader: View {
    let m: SMatch
    let now: Date
    var logo: CGFloat = 22
    var size: CGFloat = 14
    var body: some View {
        HStack(spacing: 7) {
            SLogo(team: m.home, size: logo)
            SName(text: m.home.display, size: size)
            Spacer(minLength: 4)
            VStack(spacing: 0) {
                if (m.state == "pre" && m.date > now) || m.postponed {
                    STimeText(date: m.date, size: size * 1.2)
                } else {
                    SScore(m: m, size: size * 1.45)
                }
                SStatus(m: m, now: now, size: size * 0.6)
            }
            Spacer(minLength: 4)
            SName(text: m.away.display, size: size)
            SLogo(team: m.away, size: logo)
        }
    }
}

/// نص قائمة الأهداف الفارغة: النتيجة فيها أهداف لكن المصدر لم يرسل تفاصيلها، أو لا أهداف فعلًا
func sNoGoalsText(_ m: SMatch) -> String {
    if m.postponed { return Lang.isEN ? "Postponed" : "مؤجّلة" }
    if (m.hs ?? 0) + (m.aws ?? 0) > 0 { return Lang.isEN ? "Goal details unavailable" : "تفاصيل الأهداف غير متوفرة" }
    if m.state == "post" { return Lang.isEN ? "No goals" : "بلا أهداف" }
    return Lang.isEN ? "No goals yet" : "لم تُسجَّل أهداف بعد"
}

struct SGoalsList: View {
    let m: SMatch
    let now: Date
    var count: Int
    var size: CGFloat
    private var emptyText: String {
        if m.state != "pre" { return sNoGoalsText(m) }
        let when = "\(STime.full(m.date, now: now)) \(STime.time(m.date))"
        return Lang.isEN ? "Kick-off \(when)" : "تبدأ \(when)"
    }
    var body: some View {
        if m.goals.isEmpty {
            VStack {
                Spacer(minLength: 0)
                SName(text: emptyText, size: size, dim: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 4) {
                ForEach(Array(m.goals.suffix(count).enumerated()), id: \.offset) { i, k in
                    if i > 0 { SLine() }
                    SGoalRow(k: k, m: m, size: size).frame(maxHeight: .infinity)
                }
                if m.goals.count < count { Spacer(minLength: 0) }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// الترتيب: أول أربعة (وفريقك دائمًا)
struct SportsTableMediumView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            VStack(spacing: 4) {
                SName(text: d.tableTitle(d.groupTable), size: 12, dim: true)
                if d.table.isEmpty { S_NO_TABLE }
                ForEach(Array(d.rowsFor(4).enumerated()), id: \.offset) { i, r in
                    if i > 0 { SLine() }
                    STableRow(r: r, mine: r.team.id == d.team?.id, size: 13).frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }
}

/// رأس فريقي: الشعار والاسم والترتيب وآخر النتائج
struct STeamHeader: View {
    let d: SportsData
    var logo: CGFloat = 34
    var size: CGFloat = 16
    var body: some View {
        let t = d.team ?? STeam.empty
        HStack(spacing: 9) {
            SLogo(team: t, size: logo)
            VStack(alignment: .leading, spacing: 2) {
                SName(text: t.display, size: size)
                HStack(spacing: 6) {
                    SName(text: sRankLine(d), size: size * 0.66, dim: true)
                    HStack(spacing: 3) {
                        ForEach(Array(d.form.enumerated()), id: \.offset) { _, r in SForm(r: r, size: size * 0.95) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// فريقي: الرأس وثلاث مباريات قادمة
struct SportsTeamMediumView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            VStack(spacing: 5) {
                STeamHeader(d: d, logo: 32, size: 15)
                SLine()
                ForEach(Array(d.upcoming(3).enumerated()), id: \.offset) { i, m in
                    if i > 0 { SLine() }
                    SFixtureRow(m: m, team: d.team?.id ?? "", now: entry.date, logo: 18, size: 13)
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }
}

/// مباريات اليوم: ثلاث مباريات بالأسماء
struct SportsListMediumView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            VStack(spacing: 4) {
                if d.day.isEmpty { S_NO_DAY }
                ForEach(Array(d.day.prefix(3).enumerated()), id: \.offset) { i, m in
                    if i > 0 { SLine() }
                    SMatchRow(m: m, now: entry.date, logo: 22, name: 13, mine: d.team?.id ?? "").frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }
}

// MARK: - كبيرة

/// فريقي الكامل: القادمة والنتائج
struct SportsTeamLargeView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            let tid = d.team?.id ?? ""
            VStack(spacing: 6) {
                STeamHeader(d: d, logo: 38, size: 17)
                SLine()
                ForEach(Array(d.upcoming(3).enumerated()), id: \.offset) { i, m in
                    if i > 0 { SLine() }
                    SFixtureRow(m: m, team: tid, now: entry.date, logo: 20, size: 14).frame(maxHeight: .infinity)
                }
                SLine()
                ForEach(Array(d.last.prefix(3).enumerated()), id: \.offset) { i, m in
                    if i > 0 { SLine() }
                    SFixtureRow(m: m, team: tid, now: entry.date, logo: 20, size: 14).frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
        }
    }
}

/// كتلة المباراة الكبيرة (للويدجت الكبيرة)
struct SBigMatch: View {
    let m: SMatch
    let now: Date
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                SName(text: sLeagueLine(m), size: 13, dim: true)
                HStack { SFollowButton(m: m, now: now, size: 11); Spacer() }
                    .environment(\.layoutDirection, .leftToRight)
            }
            HStack(spacing: 6) {
                STeamCol(m: m, home: true, logo: 58, name: 14).frame(width: 104)
                Spacer(minLength: 0)
                SCenter(m: m, now: now, size: 44)
                Spacer(minLength: 0)
                STeamCol(m: m, home: false, logo: 58, name: 14).frame(width: 104)
            }
        }
    }
}

/// سجل المباراة: الأهداف والبطاقات لكل فريق في عمود
struct SportsLogLargeView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            if let m = d.focus(at: entry.date) {
                let hk = m.keys.filter { $0.team == m.home.id }, ak = m.keys.filter { $0.team == m.away.id }
                let n = min(6, max(hk.count, ak.count))
                VStack(spacing: 8) {
                    SBigMatch(m: m, now: entry.date)
                    SLine()
                    if n == 0 {
                        Spacer(minLength: 0)
                        SName(text: m.postponed ? (Lang.isEN ? "Postponed" : "مؤجّلة") : m.state == "pre" ? (Lang.isEN ? "Not started" : "لم تبدأ بعد") : (Lang.isEN ? "No events yet" : "لا أحداث حتى الآن"),
                              size: 13, dim: true)
                        Spacer(minLength: 0)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(0..<n, id: \.self) { i in
                                HStack(spacing: 8) {
                                    Group { if i < hk.count { SEventCell(k: hk[i], size: 12) } else { Color.clear } }
                                        .frame(maxWidth: .infinity)
                                    Rectangle().fill(entry.tint.opacity(0.13)).frame(width: 0.7, height: 18)
                                    Group { if i < ak.count { SEventCell(k: ak[i], size: 12) } else { Color.clear } }
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
            } else { SEmpty() }
        }
    }
}

/// المباراة والترتيب
struct SportsMatchTableLargeView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            VStack(spacing: 8) {
                if let m = d.focus(at: entry.date) { SBigMatch(m: m, now: entry.date) }
                SLine()
                HStack(spacing: 7) {
                    SName(text: Lang.isEN ? "Standings" : "الترتيب", size: 12, dim: true)
                    Spacer()
                    SName(text: Lang.isEN ? "P" : "لعب", size: 10, dim: true).frame(width: 23)
                    SName(text: Lang.isEN ? "GD" : "الفارق", size: 10, dim: true).frame(width: 29)
                    SName(text: Lang.isEN ? "PTS" : "نقاط", size: 10, dim: true).frame(width: 26)
                }
                .environment(\.layoutDirection, Lang.dir)
                if d.table.isEmpty { S_NO_TABLE }
                ForEach(Array(d.rowsFor(4).enumerated()), id: \.offset) { i, r in
                    if i > 0 { SLine() }
                    STableRow(r: r, mine: r.team.id == d.team?.id, size: 13, gd: true).frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
        }
    }
}

/// جدول المباريات: مباريات الأيام القادمة
struct SportsScheduleLargeView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            VStack(spacing: 4) {
                SName(text: Leagues.get(d.dayLeague).name, size: 12, dim: true)
                if d.day.isEmpty { S_NO_DAY }
                ForEach(Array(d.day.prefix(6).enumerated()), id: \.offset) { i, m in
                    if i > 0 { SLine() }
                    SMatchRow(m: m, now: entry.date, logo: 24, name: 13, mine: d.team?.id ?? "").frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }
}

/// الهدافون: أول عشرة
struct SportsScorersLargeView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            VStack(spacing: 3) {
                HStack(spacing: 7) {
                    SName(text: Lang.isEN ? "Top scorers" : "الهدافون", size: 13)
                    Spacer()
                    SName(text: Lang.isEN ? "A" : "صنع", size: 10, dim: true).frame(width: 23)
                    SName(text: Lang.isEN ? "G" : "أهداف", size: 10, dim: true).frame(width: 23)
                }
                if d.scorers.isEmpty { S_NO_SCORERS }
                ForEach(Array(d.scorers.prefix(8).enumerated()), id: \.offset) { i, s in
                    if i > 0 { SLine() }
                    SScorerRow(s: s, size: 13, assists: true).frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }
}

/// المباراة والأهداف بالصور
struct SportsGoalsLargeView: View {
    let entry: HEntry
    var body: some View {
        SRoot(entry: entry) { d in
            if let m = d.focus(at: entry.date) {
                VStack(spacing: 8) {
                    SBigMatch(m: m, now: entry.date)
                    SLine()
                    SGoalsList(m: m, now: entry.date, count: 5, size: 14)
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
            } else { SEmpty() }
        }
    }
}

// MARK: - شاشة القفل

struct SportsLockEntry: TimelineEntry {
    let date: Date
    let data: SportsData
}

struct SportsLockProvider: TimelineProvider {
    func placeholder(in context: Context) -> SportsLockEntry { SportsLockEntry(date: Date(), data: SportsStore.current()) }
    func getSnapshot(in context: Context, completion: @escaping (SportsLockEntry) -> Void) {
        completion(SportsLockEntry(date: Date(), data: SportsStore.current()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SportsLockEntry>) -> Void) {
        Task {
            let d = await SportsTimeline.data(league: "", fetch: true)
            let now = Date()
            let plan = SportsTimeline.plan(d, now: now)
            completion(Timeline(entries: plan.dates.map { SportsLockEntry(date: $0, data: d) }, policy: .after(plan.refresh)))
        }
    }
}

struct SportsLockRect: View {
    let entry: SportsLockEntry
    var body: some View {
        Group {
            if let m = entry.data.focus(at: entry.date) {
                HStack(spacing: 6) {
                    VStack(spacing: 2) {
                        SLogo(team: m.home, size: 24)
                        Text(m.home.abbr).font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 1) {
                        if (m.state == "pre" && m.date > entry.date) || m.postponed {
                            Text(verbatim: "\(STime.time(m.date)) \(STime.ampm(m.date))").font(.system(size: 18, weight: .bold, design: .rounded))
                            Text(STime.full(m.date, now: entry.date)).font(.system(size: 10, weight: .semibold))
                        } else {
                            Text(verbatim: sScoreText(m)).font(.system(size: 22, weight: .heavy, design: .rounded))
                                .environment(\.layoutDirection, .leftToRight)
                            SLockStatus(m: m, now: entry.date)
                        }
                    }
                    .lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        SLogo(team: m.away, size: 24)
                        Text(m.away.abbr).font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                }
                .environment(\.layoutDirection, Lang.dir)
            } else {
                Image(systemName: "soccerball")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct SLockStatus: View {
    let m: SMatch
    let now: Date
    var body: some View {
        if m.running || (m.state == "pre" && m.date <= now) {
            Text(timerInterval: (m.state == "pre" ? m.date : m.clockStart)...Date.distantFuture, countsDown: false, showsHours: false)
                .font(.system(size: 11, weight: .bold).monospacedDigit()).multilineTextAlignment(.center).frame(width: 46)
        } else if m.halftime {
            Text(Lang.isEN ? "HT" : "استراحة").font(.system(size: 11, weight: .bold))
        } else {
            Text(m.done ? (Lang.isEN ? "FT" : "انتهت") : m.detail).font(.system(size: 11, weight: .semibold))
        }
    }
}

struct SportsLockCircle: View {
    let entry: SportsLockEntry
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let m = entry.data.focus(at: entry.date), let t = entry.data.team {
                VStack(spacing: 1) {
                    SLogo(team: m.opponent(of: t.id), size: 22)
                    if (m.state == "pre" && m.date > entry.date) || m.postponed {
                        Text(STime.time(m.date)).font(.system(size: 11, weight: .bold, design: .rounded))
                    } else {
                        // نتيجة فريقك أولًا في القراءة
                        let mine = m.isHome(t.id) ? m.hs ?? 0 : m.aws ?? 0, theirs = m.isHome(t.id) ? m.aws ?? 0 : m.hs ?? 0
                        Text(verbatim: Lang.isEN ? "\(mine)-\(theirs)" : lrmPair(ar(theirs), ar(mine), "-")).font(.system(size: 13, weight: .heavy, design: .rounded))
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .minimumScaleFactor(0.6)
            } else {
                Image(systemName: "soccerball").font(.system(size: 22))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct SportsLockInline: View {
    let entry: SportsLockEntry
    var body: some View {
        Group {
            if let m = entry.data.focus(at: entry.date) {
                if (m.state == "pre" && m.date > entry.date) || m.postponed {
                    Text(verbatim: "\(m.home.display) × \(m.away.display) \(STime.time(m.date))")
                } else if m.live {
                    Text(verbatim: "\(m.home.display) \(sScoreInline(m)) \(m.away.display) \(m.halftime ? "" : m.minuteText)")
                } else {
                    Text(verbatim: "\(m.home.display) \(sScoreInline(m)) \(m.away.display)")
                }
            } else {
                Text(Lang.isEN ? "Rafiqi" : "رفيقي")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct LS_Rect: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lock.s.rect", provider: SportsLockProvider()) { SportsLockRect(entry: $0) }
            .configurationDisplayName(L("مباراة فريقي"))
            .description(L("النتيجة والدقيقة أثناء المباراة، والموعد قبلها"))
            .supportedFamilies([.accessoryRectangular])
    }
}
struct LS_Circle: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lock.s.circle", provider: SportsLockProvider()) { SportsLockCircle(entry: $0) }
            .configurationDisplayName(L("خصم فريقي"))
            .description(L("شعار الخصم مع الموعد أو النتيجة"))
            .supportedFamilies([.accessoryCircular])
    }
}
struct LS_Inline: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lock.s.inline", provider: SportsLockProvider()) { SportsLockInline(entry: $0) }
            .configurationDisplayName(L("مباراة فريقي (أعلى الساعة)"))
            .description(L("الفريقان والنتيجة أو الموعد"))
            .supportedFamilies([.accessoryInline])
    }
}
