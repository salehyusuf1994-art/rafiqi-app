import Foundation

// MARK: - مصدر ثانٍ: LiveScore (مجاني بلا حساب ولا مفتاح، ونتائجه لحظية)
// للدوريات العربية وكأس العرب غير الموجودة في ESPN.
// المعرّفات تبدأ بـ ls (البطولات: ls.xxx، الفرق والمباريات: lsNNN) حتى لا تتداخل مع ESPN.

enum LS {
    static let base = "https://prod-public-api.livescore.com/v1/api/app/"
    static let img = "https://lsm-static-prod.livescore.com/medium/"

    struct Def {
        /// مسارات المراحل (الدولة/المرحلة) — للبطولة متعددة المراحل أكثر من مسار
        let paths: [String]
        /// للبحث عن المسار الجديد لو تغيّر اسمه مع الموسم (الدولة، اسم المرحلة)
        var ccd: String? = nil
        var snm: String? = nil
    }

    static let defs: [String: Def] = [
        "ls.egy.1": Def(paths: ["egypt/premier-league"], ccd: "egypt", snm: "Premier League"),
        "ls.egy.cup": Def(paths: ["egypt/cup"], ccd: "egypt", snm: "Cup"),
        "ls.uae.1": Def(paths: ["united-arab-emirates/uae-league"], ccd: "united-arab-emirates", snm: "Pro League"),
        "ls.uae.cup": Def(paths: ["united-arab-emirates/presidents-cup"], ccd: "united-arab-emirates", snm: "President's Cup"),
        "ls.qat.1": Def(paths: ["qatar/qatar-stars-league"], ccd: "qatar", snm: "Qatar Stars League"),
        "ls.mar.1": Def(paths: ["morocco/botola-pro"], ccd: "morocco", snm: "Botola Pro"),
        "ls.tun.1": Def(paths: ["tunisia/ligue-i"], ccd: "tunisia", snm: "Ligue I"),
        "ls.alg.1": Def(paths: ["algeria/ligue-1-2025"], ccd: "algeria", snm: "Ligue 1"),
        "ls.kuw.1": Def(paths: ["kuwait/premier-league"], ccd: "kuwait", snm: "Premier League"),
        "ls.irq.1": Def(paths: ["iraq/iraq-stars-league"], ccd: "iraq", snm: "Iraq Stars League"),
        "ls.jor.1": Def(paths: ["jordan/pro-league"], ccd: "jordan", snm: "Pro League"),
        "ls.omn.1": Def(paths: ["oman/professional-league"], ccd: "oman", snm: "Professional League"),
        "ls.arab.cup": Def(paths: ["intl/fifa-arab-cup-group-a", "intl/fifa-arab-cup-group-b", "intl/fifa-arab-cup-group-c",
                                   "intl/fifa-arab-cup-group-d", "intl/fifa-arab-cup-final-stage"]),
    ]

    static func owns(_ league: String) -> Bool { league.hasPrefix("ls.") }

    // ── الجلب (مع ذاكرة قصيرة: نفس التحديث يطلب المرحلة أكثر من مرة) ──
    private static let lock = NSLock()
    private static var memo: [String: (at: Date, stages: [JObj])] = [:]

    private static func pathKey(_ id: String) -> String { "ls_path_" + id }

    /// المسارات الحالية (مع أي مسار جديد اكتُشف بعد تغيّر الموسم)
    static func paths(_ id: String) -> [String] {
        if let p = AppGroup.defaults.string(forKey: pathKey(id)) { return [p] }
        return defs[id]?.paths ?? []
    }

    static func stage(_ path: String) async -> JObj? {
        guard let j = await ESPN.json(base + "stage/soccer/" + path + "/0?MD=1") else { return nil }
        return j.a("Stages").first
    }

    static func stages(_ id: String) async -> [JObj] {
        if let m = lock.withLock({ memo[id] }), Date().timeIntervalSince(m.at) < 45 { return m.stages }
        var out: [JObj] = []
        // بالتتابع (ذاكرة الويدجت محدودة)
        for p in paths(id) { if let s = await stage(p) { out.append(s) } }
        // المسار تغيّر مع الموسم: نبحث عنه بالاسم في قائمة الدولة
        if out.isEmpty, let d = defs[id], let ccd = d.ccd, let snm = d.snm,
           let j = await ESPN.json(base + "category/soccer/" + ccd + "/0?MD=1"),
           let scd = j.a("Stages").first(where: { $0.s("Snm") == snm })?.s("Scd") {
            let p = ccd + "/" + scd
            if let s = await stage(p) {
                out = [s]
                AppGroup.defaults.set(p, forKey: pathKey(id))
            }
        }
        if !out.isEmpty { lock.withLock { memo[id] = (Date(), out) } }
        return out
    }

    // ── التحليل ──
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMddHHmmss"; return f
    }()

    static func team(_ t: JObj?) -> STeam {
        guard let t else { return .empty }
        let id = "ls" + (t.s("ID") ?? t.s("Tid") ?? "")
        let name = t.s("Nm") ?? t.s("Tnm") ?? ""
        let logo = t.s("Img").map { LS.img + $0 } ?? ""
        return STeam(id: id, name: name, short: name, abbr: t.s("Abr") ?? String(name.prefix(3)).uppercased(), logo: logo)
    }

    /// الحالة بصيغة ESPN نفسها (حتى تعمل الواجهات والإشعارات كما هي)
    static func state(_ e: JObj) -> (state: String, status: String, detail: String, clock: Double) {
        let eps = (e.s("Eps") ?? "").trimmingCharacters(in: .whitespaces)
        let epr = Int(e.s("Epr") ?? "") ?? 0
        let low = eps.lowercased()
        if low.hasPrefix("postp") { return ("pre", "STATUS_POSTPONED", eps, 0) }
        if low.hasPrefix("canc") { return ("pre", "STATUS_CANCELED", eps, 0) }
        if low.hasPrefix("susp") || low.hasPrefix("int") || low.hasPrefix("aband") { return ("post", "STATUS_SUSPENDED", eps, 0) }
        if epr == 2 || ["ft", "aet", "ap", "fen", "ft pen"].contains(low) {
            return ("post", low == "aet" ? "STATUS_FINAL_AET" : low == "ap" ? "STATUS_FINAL_PEN" : "STATUS_FULL_TIME", eps, 0)
        }
        // جارية: حسب رمز المرحلة، أو نص الحالة دقيقةً («67'») أو استراحة
        if epr == 1 || eps.hasSuffix("'") || low == "ht" {
            if low == "ht" { return ("in", "STATUS_HALFTIME", eps, 45 * 60) }
            if low.hasPrefix("pen") { return ("in", "STATUS_SHOOTOUT", eps, 120 * 60) }
            // الدقيقة: "67'" أو "45+2'"
            let parts = eps.replacingOccurrences(of: "'", with: "").split(separator: "+").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if let base = parts.first {
                let m = base + (parts.count > 1 ? parts[1] : 0)
                let st = base <= 45 ? "STATUS_FIRST_HALF" : base <= 90 ? "STATUS_SECOND_HALF" : "STATUS_OVERTIME"
                return ("in", st, eps, Double(max(0, m - 1)) * 60 + 30)
            }
            // استراحة قبل الأشواط الإضافية ونحوها
            return ("in", "STATUS_END_PERIOD", eps, 90 * 60)
        }
        return ("pre", "STATUS_SCHEDULED", eps, 0)
    }

    static func match(_ e: JObj, league: String, round: String = "", now: Date = Date()) -> SMatch? {
        guard let eid = e.s("Eid"), let h = e.a("T1").first, let a = e.a("T2").first else { return nil }
        let st = state(e)
        let date = e.s("Esd").flatMap { fmt.date(from: $0) } ?? now
        var m = SMatch(id: "ls" + eid, league: league, date: date, state: st.state, status: st.status, detail: st.detail,
                       clock: st.clock, at: now, home: team(h), away: team(a),
                       hs: st.state == "pre" ? nil : Int(e.s("Tr1") ?? ""), aws: st.state == "pre" ? nil : Int(e.s("Tr2") ?? ""))
        m.round = round
        return m
    }

    /// أحداث المباراة: الأهداف والبطاقات
    static func keys(_ incs: JObj?, home: String, away: String) -> [SKey] {
        guard let incs else { return [] }
        var flat: [JObj] = []
        for k in incs.keys.sorted() {
            for it in incs.a(k) {
                let sub = it.a("Incs")
                flat += sub.isEmpty ? [it] : sub
            }
        }
        func order(_ i: JObj) -> Int { Int(i.d("Min") ?? 0) * 100 + Int(i.d("MinEx") ?? 0) }
        return flat.sorted { order($0) < order($1) }.compactMap { i -> SKey? in
            let it = Int(i.d("IT") ?? 0)
            let kind: String
            if i["Sc"] != nil {
                kind = it == 37 ? "pen" : it == 39 ? "og" : "goal"
            } else if it == 43 {
                kind = "yellow"
            } else if it == 44 || it == 45 {
                kind = "red"
            } else { return nil }
            let mn = Int(i.d("Min") ?? 0), ex = Int(i.d("MinEx") ?? 0)
            let minute = ex > 0 ? "\(mn)+\(ex)'" : "\(mn)'"
            let side = Int(i.d("Nm") ?? 1)
            let player = i.s("Pn") ?? [i.s("Fn"), i.s("Ln")].compactMap { $0 }.joined(separator: " ")
            return SKey(minute: minute, kind: kind, team: side == 2 ? away : home, player: player, pid: "")
        }
    }

    // ── واجهة مثل ESPN ──

    /// كل مباريات البطولة هذا الموسم
    static func all(_ league: String) async -> [SMatch] {
        let now = Date()
        var out: [SMatch] = []
        for s in await stages(league) {
            out += s.a("Events").compactMap { match($0, league: league, now: now) }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// مثل scoreboard: المباريات بين تاريخين (yyyyMMdd-yyyyMMdd)، أو كل الموسم
    static func scoreboard(_ league: String, dates: String?) async -> [SMatch] {
        let list = await all(league)
        guard let dates else { return list }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd"
        let p = dates.split(separator: "-").map(String.init)
        guard p.count == 2, let a = f.date(from: p[0]), let b = f.date(from: p[1]) else { return list }
        let end = b.addingTimeInterval(86400)
        return list.filter { $0.date >= a && $0.date < end }
    }

    static func schedule(_ league: String, team: String) async -> [SMatch] {
        await all(league).filter { $0.has(team) }
    }

    static func teamInfo(_ league: String, team: String) async -> (STeam, [SMatch])? {
        let list = await all(league).filter { $0.has(team) }
        guard let any = list.first else { return nil }
        let t = any.home.id == team ? any.home : any.away
        return (t, Array(list.filter { !$0.done && !$0.postponed }.prefix(1)))
    }

    /// الترتيب: لكل مرحلة جدولها (مجموعات كأس العرب مثلًا)
    static func standings(_ league: String, team: String) async -> [SRow] {
        var groups: [(name: String, rows: [SRow])] = []
        for s in await stages(league) {
            guard let lt = s.o("LeagueTable"), let l = lt.a("L").first else { continue }
            let table = l.a("Tables").first { Int($0.d("LTT") ?? 1) == 1 } ?? l.a("Tables").first ?? [:]
            let rows: [SRow] = table.a("team").enumerated().map { i, r in
                let gd = Int(r.d("gd") ?? 0)
                return SRow(rank: Int(r.d("rnk") ?? Double(i + 1)), team: self.team(r), gp: Int(r.d("pld") ?? 0),
                            w: Int(r.d("win") ?? 0), d: Int(r.d("drw") ?? 0), l: Int(r.d("lst") ?? 0),
                            gd: gd, pts: Int(r.d("pts") ?? 0), note: "")
            }
            if rows.isEmpty { continue }
            // اسم المجموعة: ما بعد النقطتين في اسم المرحلة («FIFA Arab Cup: Group A» ← «Group A»)
            let snm = s.s("Snm") ?? ""
            let name = snm.components(separatedBy: ": ").last ?? snm
            groups.append((name, rows.sorted { $0.rank < $1.rank }))
        }
        let multi = groups.count > 1
        let pick = groups.first { $0.rows.contains { $0.team.id == team } }.map { [$0] } ?? groups
        return pick.flatMap { g -> [SRow] in
            g.rows.map { (r: SRow) -> SRow in
                var x = r
                x.group = multi ? g.name : nil
                return x
            }
        }
    }

    static func teams(_ league: String) async -> [STeam] {
        var seen = Set<String>(), out: [STeam] = []
        for r in await standings(league, team: "") where seen.insert(r.team.id).inserted { out.append(r.team) }
        for m in await all(league) {
            for t in [m.home, m.away] where !t.id.isEmpty && seen.insert(t.id).inserted { out.append(t) }
        }
        return out.sorted { $0.display < $1.display }
    }

    /// مباراة واحدة لحظيًا: النتيجة والحالة، ثم الأهداف والبطاقات
    static func event(_ league: String, id: String) async -> SMatch? {
        let eid = id.hasPrefix("ls") ? String(id.dropFirst(2)) : id
        async let sb = ESPN.json(base + "scoreboard/soccer/" + eid + "?locale=en")
        async let ic = ESPN.json(base + "incidents/soccer/" + eid + "?locale=en")
        guard let j = await sb, var m = match(j, league: league) else { return nil }
        let inc = await ic
        m.keys = keys(inc?.o("Incs") ?? j.o("Incs-s"), home: m.home.id, away: m.away.id)
        return m
    }
}
