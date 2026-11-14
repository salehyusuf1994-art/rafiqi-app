import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - تبويب المباريات: فريقك، المتابعة المباشرة، القادمة والنتائج، الترتيب والهدافون، والإعدادات

struct SportsView: View {
    @ObservedObject private var live = SportsLive.shared
    @State private var data: SportsData? = SportsStore.load()
    @State private var loading = false
    @State private var section = 0
    @State private var notifyBefore = SportsPrefs.notifyBefore
    @State private var beforeMin = SportsPrefs.beforeMinutes
    @State private var notifyGoals = SportsPrefs.notifyGoals
    @State private var notifyCards = SportsPrefs.notifyCards
    @State private var notifyPhases = SportsPrefs.notifyPhases
    @State private var useLA = SportsPrefs.liveActivity
    @State private var viewLeague = SportsPrefs.viewLeague

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PageHeader(title: "المباريات", subtitle: data.flatMap { d in d.team.map { "\($0.display) · \(d.leagueName)" } })
                }
                .bareRow(top: 0, bottom: 0)
                Section { teamCard }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                if let d = data, let m = d.focus() {
                    Section { followCard(m) } footer: {
                        Text("المتابعة المباشرة صامتة تمامًا؛ لا يُشغَّل أي صوت سوى صوت الإشعارات. تتحدّث النتيجة كل ٢٠ ثانية في الويدجت وشاشة القفل والجزيرة الديناميكية. لا تُغلق رفيقي من قائمة التطبيقات المفتوحة أثناء المتابعة.")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                Section {
                    ChipBar(items: ["المباريات", "الترتيب", "الهدافون", "الإعدادات"], selection: $section)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                if section < 3 {
                    Section { competitionRow }
                        .listRowBackground(Theme.card)
                }
                switch section {
                case 0: matchesSections
                case 1: tableSection
                case 2: scorersSection
                default: settingsSections
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .barSpace()
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await reload() }
            .task {
                if data == nil || Date().timeIntervalSince(data?.updated ?? .distantPast) > 5 * 60 { await reload() }
            }
            .onChange(of: live.match) { _, _ in data = SportsStore.load() ?? data }
        }
    }

    func reload() async {
        loading = true
        data = await Sports.refresh()
        loading = false
        Sports.reloadWidgets()
    }

    /// البطولة المعروضة في الأقسام (تُغيَّر من هنا مباشرة)
    var competitionRow: some View {
        let shown = section == 0 ? (data?.dayLeague ?? SportsPrefs.effectiveViewLeague) : (data?.tableLeague ?? SportsPrefs.effectiveViewLeague)
        return NavigationLink {
            CompetitionPicker(selection: viewLeague) { v in
                viewLeague = v
                SportsPrefs.viewLeague = v
                Task { await reload() }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill").foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("البطولة المعروضة").font(.caption).foregroundStyle(Theme.sub)
                    Text(Leagues.get(shown).name).foregroundStyle(.white)
                }
                Spacer()
                if loading { ProgressView().tint(Theme.gold) }
            }
        }
    }

    // ── فريقي ──
    var teamCard: some View {
        let d = data
        let t = d?.team
        return HStack(spacing: 14) {
            AppLogo(team: t ?? STeam.empty, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(t?.display ?? L("اختر فريقك")).font(Theme.title(20)).foregroundStyle(.white)
                if let d, d.rank > 0 {
                    Text(verbatim: Lang.isEN ? "#\(d.rank) · \(d.points) pts · \(d.leagueName)" : "المركز \(ar(d.rank)) · \(pointsText(d.points)) · \(d.leagueName)")
                        .font(.caption).foregroundStyle(Theme.sub)
                }
                HStack(spacing: 4) {
                    ForEach(Array((d?.form ?? []).enumerated()), id: \.offset) { _, r in SForm(r: r, size: 18) }
                }
            }
            Spacer(minLength: 0)
            if loading { ProgressView().tint(Theme.gold) }
            NavigationLink {
                LeaguePicker(onPick: { Task { await reload() } })
            } label: {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black).frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.gold))
            }
            .buttonStyle(.plain)
        }
        .glassCard(padding: 14)
    }

    // ── المتابعة المباشرة ──
    func followCard(_ m: SMatch) -> some View {
        let following = live.active && live.match?.id == m.id
        let shown = following ? (live.match ?? m) : m
        return VStack(spacing: 12) {
            Text(sLeagueLine(shown)).font(.caption).foregroundStyle(Theme.sub)
            HStack {
                VStack(spacing: 6) { AppLogo(team: shown.home, size: 48); Text(shown.home.display).font(.subheadline.bold()) }
                    .frame(maxWidth: .infinity)
                VStack(spacing: 4) {
                    if shown.postponed {
                        Text("مؤجّلة").font(Theme.title(22))
                        Text(STime.full(shown.date, now: Date())).font(.caption).foregroundStyle(Theme.sub)
                    } else if shown.state == "pre" {
                        Text(verbatim: "\(STime.time(shown.date)) \(STime.ampm(shown.date))").font(.title2.bold())
                        Text(STime.full(shown.date, now: Date())).font(.caption).foregroundStyle(Theme.sub)
                    } else {
                        Text(verbatim: sScoreText(shown)).font(.system(size: 34, weight: .heavy, design: .rounded))
                            .environment(\.layoutDirection, .leftToRight)
                        SStatus(m: shown, now: Date(), size: 12)
                    }
                }
                VStack(spacing: 6) { AppLogo(team: shown.away, size: 48); Text(shown.away.display).font(.subheadline.bold()) }
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(.white)
            .environment(\.sTint, .white)
            .environment(\.wfont, .tajawal)
            if shown.state != "post" && !shown.postponed {
                Button {
                    if following { live.stop() } else { Task { await live.follow(league: shown.league, id: shown.id) } }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: following ? "stop.fill" : "bolt.fill")
                        Text(following ? "إيقاف المتابعة المباشرة" : "تابع المباراة مباشرة")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(following ? .white : .black)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(Capsule().fill(following ? AnyShapeStyle(S_RED) : AnyShapeStyle(Theme.gold)))
                }
                .buttonStyle(.plain)
                if following {
                    HStack(spacing: 6) {
                        Circle().fill(S_RED).frame(width: 7, height: 7)
                        Text(shown.state == "pre" ? "بانتظار انطلاق المباراة، وتبدأ المتابعة تلقائيًا" : "المتابعة المباشرة الصامتة تعمل الآن")
                            .font(.caption).foregroundStyle(Theme.sub)
                    }
                }
            }
        }
        .glassCard(padding: 16)
    }

    // ── المباريات ──
    @ViewBuilder var matchesSections: some View {
        if let d = data, let t = d.team {
            Section("القادمة") {
                ForEach(d.upcoming(8)) { m in matchRow(m, team: t.id) }
            }
            .listRowBackground(Theme.card)
            Section("آخر النتائج") {
                ForEach(d.last.prefix(8)) { m in matchRow(m, team: t.id) }
            }
            .listRowBackground(Theme.card)
            Section(Leagues.get(d.dayLeague).name) {
                if d.day.isEmpty {
                    Text("لا توجد مباريات قريبة في هذه البطولة.").foregroundStyle(Theme.sub)
                } else {
                    ForEach(d.day) { m in dayRow(m) }
                }
            }
            .listRowBackground(Theme.card)
        } else if !loading {
            Section { Text("لم تصل البيانات بعد. اسحب الصفحة إلى الأسفل للتحديث، وتأكّد من الاتصال بالإنترنت.").foregroundStyle(Theme.sub) }
                .listRowBackground(Theme.card)
        }
    }

    func matchRow(_ m: SMatch, team: String) -> some View {
        let opp = m.opponent(of: team)
        return HStack(spacing: 10) {
            AppLogo(team: opp, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(opp.display).foregroundStyle(.white)
                Text(verbatim: "\(m.isHome(team) ? L("على أرضه") : L("خارج أرضه")) · \(Leagues.get(m.league).name)")
                    .font(.caption2).foregroundStyle(Theme.sub)
            }
            Spacer()
            if m.postponed {
                Text("مؤجّلة").font(.subheadline.bold()).foregroundStyle(Theme.sub)
            } else if m.state == "pre" {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "\(STime.time(m.date)) \(STime.ampm(m.date))").font(.subheadline.bold()).foregroundStyle(.white)
                    Text(STime.full(m.date, now: Date())).font(.caption2).foregroundStyle(Theme.sub)
                }
            } else {
                HStack(spacing: 6) {
                    // نتيجة فريقك أولًا في القراءة (يمين في العربي)
                    let mine = m.isHome(team) ? m.hs ?? 0 : m.aws ?? 0, theirs = m.isHome(team) ? m.aws ?? 0 : m.hs ?? 0
                    Text(verbatim: Lang.isEN ? "\(mine) - \(theirs)" : lrmPair(ar(theirs), ar(mine))).font(.headline.monospacedDigit()).foregroundStyle(.white)
                        .environment(\.layoutDirection, .leftToRight)
                    if let r = m.result(for: team) { SForm(r: r, size: 20) }
                    if m.live { Circle().fill(S_RED).frame(width: 7, height: 7) }
                }
            }
        }
    }

    func dayRow(_ m: SMatch) -> some View {
        HStack(spacing: 8) {
            AppLogo(team: m.home, size: 24)
            Text(m.home.display).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 4)
            if m.postponed {
                Text("مؤجّلة").font(.caption.bold()).foregroundStyle(Theme.sub)
            } else if m.state == "pre" {
                Text(verbatim: "\(STime.time(m.date)) \(STime.ampm(m.date)) · \(STime.day(m.date, now: Date()))")
                    .font(.caption.bold()).foregroundStyle(Theme.sub)
            } else {
                Text(verbatim: sScoreText(m)).font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(m.live ? S_RED : .white)
                    .environment(\.layoutDirection, .leftToRight)
            }
            Spacer(minLength: 4)
            Text(m.away.display).foregroundStyle(.white).lineLimit(1)
            AppLogo(team: m.away, size: 24)
        }
        .font(.subheadline)
    }

    // ── الترتيب ──
    /// مجموعات الترتيب بترتيب ظهورها (مجموعة واحدة بلا اسم في الدوريات)
    func tableGroups(_ t: [SRow]) -> [(name: String, rows: [SRow])] {
        var out: [(name: String, rows: [SRow])] = []
        for r in t {
            let g = r.group ?? ""
            if let i = out.firstIndex(where: { $0.name == g }) { out[i].rows.append(r) } else { out.append((g, [r])) }
        }
        return out
    }

    @ViewBuilder var tableSection: some View {
        if let d = data, !d.table.isEmpty {
            ForEach(Array(tableGroups(d.table).enumerated()), id: \.offset) { _, g in
                Section {
                    ForEach(g.rows, id: \.team.id) { r in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 1.5).fill(r.note.isEmpty ? Color.clear : Color(hex: r.note)).frame(width: 3, height: 18)
                            Text(ar(r.rank)).font(.caption.monospacedDigit()).foregroundStyle(Theme.sub).frame(width: 22)
                            AppLogo(team: r.team, size: 22)
                            Text(r.team.display).foregroundStyle(.white).fontWeight(r.team.id == d.team?.id ? .bold : .regular).lineLimit(1)
                            Spacer()
                            Text(ar(r.gp)).foregroundStyle(Theme.sub).frame(width: 26)
                            Text(verbatim: r.gd > 0 ? "+\(ar(r.gd))" : ar(r.gd)).foregroundStyle(Theme.sub).frame(width: 34)
                            Text(ar(r.pts)).bold().foregroundStyle(.white).frame(width: 30)
                        }
                        .font(.subheadline.monospacedDigit())
                        .listRowBackground(r.team.id == d.team?.id ? Theme.cardHi : Theme.card)
                    }
                } header: {
                    HStack {
                        Text(verbatim: g.name.isEmpty ? Leagues.get(d.tableLeague).name : sGroupName(g.name))
                        Spacer()
                        Text("لعب").frame(width: 26)
                        Text("الفارق").frame(width: 34)
                        Text("نقاط").frame(width: 30)
                    }
                }
            }
        } else {
            Section { Text("لا يوجد ترتيب لهذه البطولة.").foregroundStyle(Theme.sub) }.listRowBackground(Theme.card)
        }
    }

    // ── الهدافون ──
    @ViewBuilder var scorersSection: some View {
        if let d = data, !d.scorers.isEmpty {
            Section {
                ForEach(d.scorers, id: \.rank) { s in
                    HStack(spacing: 10) {
                        Text(ar(s.rank)).font(.caption.monospacedDigit()).foregroundStyle(Theme.sub).frame(width: 22)
                        SPhoto(name: s.name, url: s.photo, size: 34).environment(\.sTint, .white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name).foregroundStyle(.white)
                            HStack(spacing: 4) {
                                AppLogo(team: s.team, size: 14)
                                Text(s.team.display).font(.caption2).foregroundStyle(Theme.sub)
                            }
                        }
                        Spacer()
                        VStack(spacing: 0) {
                            Text(ar(s.goals)).font(.headline).foregroundStyle(.white)
                            Text(verbatim: Lang.isEN ? "\(s.assists) ast" : "تمريرات حاسمة: \(ar(s.assists))").font(.caption2).foregroundStyle(Theme.sub)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            } header: {
                Text(Leagues.get(d.tableLeague).name)
            }
        } else {
            Section { Text("لا توجد قائمة هدافين لهذه البطولة.").foregroundStyle(Theme.sub) }.listRowBackground(Theme.card)
        }
    }

    // ── الإعدادات ──
    @ViewBuilder var settingsSections: some View {
        Section {
            NavigationLink {
                CompetitionPicker(selection: viewLeague) { v in
                    viewLeague = v
                    SportsPrefs.viewLeague = v
                    Task { await reload() }
                }
            } label: {
                LabeledContent("بطولة الأقسام والويدجت", value: viewLeague.isEmpty ? L("بطولة فريقي") : Leagues.get(viewLeague).name)
            }
        } footer: {
            Text("تُعرض مبارياتها وترتيبها وهدافوها في التطبيق والويدجت. ويمكنك اختيار بطولة مختلفة لكل ويدجت من «تعديل الأداة».")
        }
        .listRowBackground(Theme.card)

        Section {
            Toggle("تنبيه قبل المباراة", isOn: $notifyBefore)
                .onChange(of: notifyBefore) { _, v in SportsPrefs.notifyBefore = v; resched() }
            if notifyBefore {
                Picker("وقت التنبيه", selection: $beforeMin) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { n in Text(verbatim: minutesText(n)).tag(n) }
                }
                .onChange(of: beforeMin) { _, v in SportsPrefs.beforeMinutes = v; resched() }
            }
            Toggle("الأهداف", isOn: $notifyGoals).onChange(of: notifyGoals) { _, v in SportsPrefs.notifyGoals = v }
            Toggle("البطاقات الحمراء", isOn: $notifyCards).onChange(of: notifyCards) { _, v in SportsPrefs.notifyCards = v }
            Toggle("البداية والاستراحة والنهاية", isOn: $notifyPhases).onChange(of: notifyPhases) { _, v in SportsPrefs.notifyPhases = v }
        } header: {
            Text("الإشعارات")
        } footer: {
            Text("تنبيه ما قبل المباراة يصلك دائمًا. أما الأهداف والبطاقات والبداية والنهاية فتصلك أثناء المتابعة المباشرة.")
        }
        .listRowBackground(Theme.card)

        Section {
            Toggle("النشاط المباشر في شاشة القفل والجزيرة الديناميكية", isOn: $useLA)
                .onChange(of: useLA) { _, v in SportsPrefs.liveActivity = v }
        } footer: {
            Text("يظهر أثناء المتابعة المباشرة: الفريقان والنتيجة والدقيقة وآخر هدف.")
        }
        .listRowBackground(Theme.card)

        Section {
            Text("مصادر البيانات: ESPN، وLiveScore للدوريات العربية وكأس العرب؛ مجانًا ودون حساب، وتغطي أكثر من ٩٠ بطولة للأندية والمنتخبات. تتحدّث الويدجت تلقائيًا كل ربع ساعة تقريبًا، وكل بضع دقائق أثناء المباريات، وكل ٢٠ ثانية أثناء المتابعة المباشرة.")
                .font(.footnote).foregroundStyle(Theme.sub)
        }
        .listRowBackground(Theme.card)
    }

    func resched() {
        if let d = data { Task { await SportsNotify.schedulePreMatch(d) } }
    }
}

/// شعار الفريق داخل التطبيق (من الذاكرة، أو من الإنترنت)
struct AppLogo: View {
    let team: STeam
    var size: CGFloat
    var body: some View {
        Group {
            if let img = SportsImages.image(team.logo) {
                Image(uiImage: img).resizable().scaledToFit()
            } else if let u = URL(string: team.logo), !team.logo.isEmpty {
                AsyncImage(url: u) { p in
                    if let i = p.image { i.resizable().scaledToFit() } else { Circle().fill(Theme.cardHi) }
                }
            } else {
                ZStack {
                    Circle().fill(Theme.cardHi)
                    Image(systemName: "soccerball").foregroundStyle(Theme.sub)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - اختيار الدوري ثم الفريق

struct LeaguePicker: View {
    var onPick: () -> Void
    var body: some View {
        List {
            Section {
                NavigationLink {
                    TeamPicker(league: Leagues.get(Leagues.nationsKey), title: L("المنتخبات الوطنية"), onPick: onPick)
                } label: {
                    Label("المنتخبات الوطنية", systemImage: "flag.fill").foregroundStyle(.white)
                }
            } footer: {
                Text("تابع منتخبك في كأس العالم وتصفياتها والبطولات القارية والمباريات الودية.")
            }
            .listRowBackground(Theme.card)
            ForEach(Leagues.groups) { g in
                let list = Leagues.inGroup(g.id).filter { $0.kind == .league }
                if !list.isEmpty {
                    Section(g.name) {
                        ForEach(list) { l in
                            NavigationLink {
                                TeamPicker(league: l, onPick: onPick)
                            } label: {
                                Text(l.name).foregroundStyle(.white)
                            }
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .navigationTitle("اختر فريقك")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// اختيار البطولة المعروضة: كل البطولات مجمّعة حسب المنطقة، مع البحث
struct CompetitionPicker: View {
    let selection: String
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""

    func match(_ l: SLeague) -> Bool {
        q.isEmpty || l.ar.contains(q) || l.en.localizedCaseInsensitiveContains(q)
    }

    var body: some View {
        List {
            if q.isEmpty {
                Section {
                    row(id: "", name: L("بطولة فريقي"))
                }
                .listRowBackground(Theme.card)
            }
            ForEach(Leagues.groups) { g in
                let list = Leagues.inGroup(g.id).filter(match)
                if !list.isEmpty {
                    Section(g.name) {
                        ForEach(list) { l in row(id: l.id, name: l.name) }
                    }
                    .listRowBackground(Theme.card)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .searchable(text: $q, prompt: "ابحث عن بطولة")
        .navigationTitle("البطولة المعروضة")
        .navigationBarTitleDisplayMode(.inline)
    }

    func row(id: String, name: String) -> some View {
        Button {
            onPick(id)
            dismiss()
        } label: {
            HStack {
                Text(verbatim: name).foregroundStyle(.white)
                Spacer()
                if id == selection { Image(systemName: "checkmark").foregroundStyle(Theme.gold) }
            }
        }
    }
}

struct TeamPicker: View {
    let league: SLeague
    var title: String? = nil
    var onPick: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var teams: [STeam] = []
    @State private var q = ""
    @State private var loading = true

    var body: some View {
        List {
            if loading { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }
            ForEach(teams.filter { q.isEmpty || $0.display.contains(q) || $0.name.localizedCaseInsensitiveContains(q) }, id: \.id) { t in
                Button {
                    SportsPrefs.teamId = t.id
                    SportsPrefs.teamLeague = league.id
                    onPick()
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        AppLogo(team: t, size: 30)
                        Text(t.display).foregroundStyle(.white)
                        Spacer()
                        if t.id == SportsPrefs.teamId { Image(systemName: "checkmark").foregroundStyle(Theme.gold) }
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .searchable(text: $q, prompt: Text(verbatim: L(league.isNations ? "ابحث عن منتخب" : "ابحث عن فريق")))
        .navigationTitle(title ?? league.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            teams = await ESPN.teams(league.id)
            loading = false
        }
    }
}
