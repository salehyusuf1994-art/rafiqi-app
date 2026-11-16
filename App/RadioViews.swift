import SwiftUI
import AVKit
import MediaPlayer

// MARK: - تبويب الإذاعات: مشغّل احترافي، تصنيفات، مفضّلة قابلة للترتيب، إضافة برابط، مؤقّت نوم

/// تصنيف لتصفّح دليل الإذاعات
struct RadioCategory: Hashable, Identifiable {
    var id: String { title }
    let title: String
    let icon: String
    let color: Color
    var tag: String? = nil
    var language: String? = nil
    var country: String? = nil

    /// كل التصنيفات عربية فقط (لغة البث العربية)
    static let all: [RadioCategory] = [
        .init(title: "القرآن الكريم", icon: "book.closed.fill", color: Theme.gold, tag: "quran", language: "arabic"),
        .init(title: "الأكثر استماعًا", icon: "flame.fill", color: .teal, language: "arabic"),
        .init(title: "إذاعات سعودية", icon: "star.circle.fill", color: .green, language: "arabic", country: "SA"),
        .init(title: "الأخبار", icon: "newspaper.fill", color: .blue, tag: "news", language: "arabic"),
        .init(title: "الرياضة", icon: "sportscourt.fill", color: .mint, tag: "sports", language: "arabic"),
        .init(title: "حوارية وبرامج", icon: "mic.fill", color: .orange, tag: "talk", language: "arabic"),
    ]
    static let search = RadioCategory(title: "البحث في الإذاعات", icon: "magnifyingglass", color: .gray, language: "arabic")

    /// القسم نفسه داخل دولة معيّنة
    func inCountry(_ c: RadioCountry) -> RadioCategory {
        RadioCategory(title: title + " — " + c.name, icon: icon, color: color, tag: tag, language: c.arabicOnly ? language : nil, country: c.code)
    }

    func hash(into h: inout Hasher) { h.combine(title) }
    static func == (a: Self, b: Self) -> Bool { a.title == b.title }
}

enum RadioCountries {
    static let list: [(String, String)] = [
        ("", "كل الدول"), ("SA", "السعودية"), ("AE", "الإمارات"), ("KW", "الكويت"), ("QA", "قطر"), ("BH", "البحرين"),
        ("OM", "عُمان"), ("YE", "اليمن"), ("IQ", "العراق"), ("JO", "الأردن"), ("SY", "سوريا"), ("LB", "لبنان"),
        ("PS", "فلسطين"), ("EG", "مصر"), ("SD", "السودان"), ("LY", "ليبيا"), ("TN", "تونس"), ("DZ", "الجزائر"),
        ("MA", "المغرب"), ("MR", "موريتانيا"),
    ]
    static func name(_ code: String) -> String { list.first { $0.0 == code }.map { L($0.1) } ?? code }
}

// ── شعار الإذاعة ──
struct StationArt: View {
    let station: Station?
    var size: CGFloat = 44
    var body: some View {
        let r = size * 0.26
        ZStack {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(LinearGradient(colors: [Theme.gold.opacity(0.35), Theme.goldDeep.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Theme.gold)
            if let f = station?.favicon, let u = URL(string: f) {
                AsyncImage(url: u) { ph in
                    if let img = ph.image {
                        ZStack {
                            Color.white
                            img.resizable().scaledToFit().padding(size * 0.08)
                        }
                        .frame(width: size, height: size)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

// ── سطر الدولة والجودة: كل جزء في مكانه (بلا خلط بين العربي والإنجليزي) ──
struct StationMeta: View {
    let station: Station
    var body: some View {
        let country = station.country.map(RadioCountries.name) ?? ""
        HStack(spacing: 5) {
            if !station.flag.isEmpty { Text(verbatim: station.flag) }
            if !country.isEmpty { Text(verbatim: country) }
            if !station.quality.isEmpty {
                if !country.isEmpty || !station.flag.isEmpty { Text(verbatim: "·") }
                Text(verbatim: station.quality).environment(\.layoutDirection, .leftToRight)
            }
        }
        .font(Theme.f(.caption2)).foregroundStyle(Theme.sub).lineLimit(1)
    }
}

// ── شارة «مباشر» ──
struct LiveBadge: View {
    let on: Bool
    var body: some View {
        HStack(spacing: 5) {
            // نبض النقطة الحمراء أثناء البث فقط
            Circle().fill(on ? Color.red : Theme.sub).frame(width: 7, height: 7)
                .phaseAnimator(on ? [1.0, 0.3] : [1.0]) { v, op in v.opacity(op) } animation: { _ in .easeInOut(duration: 0.8) }
            Text("مباشر").font(Theme.font(11, .bold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(on ? Color.red.opacity(0.22) : Theme.card))
        .overlay(Capsule().strokeBorder(on ? Color.red.opacity(0.5) : Theme.stroke, lineWidth: 1))
    }
}

// ── زر AirPlay ──
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Theme.gold)
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}

// ── شريط صوت النظام ──
struct SystemVolume: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView()
        v.tintColor = UIColor(Theme.gold)
        return v
    }
    func updateUIView(_ v: MPVolumeView, context: Context) {}
}

// ── قائمة مؤقّت النوم (مشتركة للقرآن والإذاعة) ──
struct SleepMenu: View {
    @ObservedObject private var p = AudioPlayer.shared
    var label: Bool = true
    var body: some View {
        Menu {
            if p.sleepAt != nil || p.sleepAtEnd {
                Button(role: .destructive) { p.cancelSleep() } label: { Label("إلغاء المؤقّت", systemImage: "xmark") }
            }
            ForEach([15, 30, 45, 60, 90], id: \.self) { m in
                Button(LF("بعد %@ دقيقة", ar(m))) { p.sleep(minutes: m) }
            }
            if p.state.source == .quran {
                Button("عند نهاية السورة") { p.sleepAtEndOfSurah() }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: p.sleepAt != nil || p.sleepAtEnd ? "moon.zzz.fill" : "moon.zzz")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(p.sleepAt != nil || p.sleepAtEnd ? Theme.gold : .white)
                if label {
                    Group {
                        if let at = p.sleepAt {
                            Text(at, style: .timer).monospacedDigit()
                        } else if p.sleepAtEnd {
                            Text("نهاية السورة")
                        } else {
                            Text("مؤقّت النوم")
                        }
                    }
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.sub).lineLimit(1)
                }
            }
            .frame(minWidth: label ? 54 : 28)
        }
    }
}

// MARK: - مشغّل الإذاعة

struct RadioPlayerCard: View {
    @ObservedObject private var p = AudioPlayer.shared
    @Binding var saved: [Station]

    var body: some View {
        let st = p.station ?? currentFallback
        let on = p.state.playing
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                StationArt(station: st, size: 74)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        LiveBadge(on: on)
                        if p.loading { ProgressView().controlSize(.mini).tint(Theme.gold) }
                    }
                    Text(p.state.title).font(Theme.title(18)).foregroundStyle(.white).lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if let t = p.streamTitle {
                        Label { Text(verbatim: t).lineLimit(2) } icon: { Image(systemName: "waveform") }
                            .font(Theme.f(.caption)).foregroundStyle(Theme.gold)
                    }
                    let meta = [st?.flag ?? "", st?.quality ?? ""].filter { !$0.isEmpty }.joined(separator: "  ")
                    if !meta.isEmpty { Text(verbatim: meta).font(Theme.f(.caption2).monospacedDigit()).foregroundStyle(Theme.sub) }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 22) {
                round("backward.fill") { AudioPlayer.shared.previous() }
                Button { AudioPlayer.shared.toggle() } label: {
                    Image(systemName: on ? "stop.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 66, height: 66)
                        .background(Circle().fill(Theme.gold))
                        .shadow(color: Theme.gold.opacity(0.35), radius: 12)
                }
                .buttonStyle(.plain)
                round("forward.fill") { AudioPlayer.shared.next() }
            }
            .environment(\.layoutDirection, .leftToRight)

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                SystemVolume().frame(height: 30)
                Image(systemName: "speaker.wave.3.fill").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            }
            .environment(\.layoutDirection, .leftToRight)

            HStack {
                if let st {
                    action(Stations.isSaved(st) ? "star.fill" : "star", Stations.isSaved(st) ? "في المفضلة" : "إلى المفضلة",
                           on: Stations.isSaved(st)) {
                        Stations.toggle(st); saved = Stations.saved
                    }
                }
                Spacer()
                action("arrow.clockwise", "تحديث البث", on: false) { AudioPlayer.shared.refreshLive() }
                Spacer()
                SleepMenu()
                Spacer()
                VStack(spacing: 3) {
                    RoutePicker().frame(width: 26, height: 22)
                    Text("AirPlay").font(Theme.font(10, .medium)).foregroundStyle(Theme.sub)
                }
                .frame(minWidth: 54)
                Spacer()
                if let st, let u = URL(string: st.url) {
                    ShareLink(item: u, subject: Text(st.name)) {
                        VStack(spacing: 3) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                            Text("مشاركة").font(Theme.font(10, .medium)).foregroundStyle(Theme.sub)
                        }
                        .frame(minWidth: 54)
                    }
                }
            }
        }
        .glassCard(padding: 18)
    }

    private var currentFallback: Station? {
        guard let u = AppGroup.defaults.string(forKey: "last_station") else { return nil }
        return (Stations.saved + Stations.recent + Stations.builtin).first { $0.url == u }
            ?? Station(name: p.state.title, url: u)
    }

    private func round(_ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 46, height: 46).background(Circle().fill(Theme.cardHi))
        }
        .buttonStyle(.plain)
    }

    private func action(_ icon: String, _ title: String, on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(on ? Theme.gold : .white)
                Text(L(title)).font(Theme.font(10, .medium)).foregroundStyle(Theme.sub).lineLimit(1)
            }
            .frame(minWidth: 54)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - صف إذاعة

struct StationRow: View {
    let station: Station
    @Binding var saved: [Station]
    var showStar = true
    /// زر «إضافة إلى قائمة تشغيل»
    var showAdd = true
    @ObservedObject private var p = AudioPlayer.shared
    @ObservedObject private var lists = PlaylistStore.shared

    var body: some View {
        let current = p.state.source == .radio && (p.station?.url ?? AppGroup.defaults.string(forKey: "last_station")) == station.url
        let fav = saved.contains { $0.url == station.url }
        HStack(spacing: 12) {
            Button { AudioPlayer.shared.playStation(station) } label: {
                HStack(spacing: 12) {
                    StationArt(station: station, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: station.name).font(Theme.f(.body, current ? .semibold : .regular))
                            .foregroundStyle(current ? Theme.gold : .white).lineLimit(1)
                        StationMeta(station: station)
                    }
                    Spacer(minLength: 0)
                    if current && p.state.playing {
                        Image(systemName: "waveform").symbolEffect(.variableColor.iterative, options: .repeating)
                            .foregroundStyle(Theme.gold)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showAdd {
                Menu { addMenu } label: {
                    Image(systemName: "text.badge.plus").foregroundStyle(.white.opacity(0.8))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
            }
            if showStar {
                Button { Stations.toggle(station); saved = Stations.saved } label: {
                    Image(systemName: fav ? "star.fill" : "star").foregroundStyle(Theme.gold)
                }
                .buttonStyle(.borderless)
            }
        }
        .contextMenu {
            Menu { addMenu } label: { Label("إضافة إلى قائمة تشغيل", systemImage: "text.badge.plus") }
            Button { AudioPlayer.shared.playStation(station) } label: { Label("تشغيل", systemImage: "play.fill") }
            Button { Stations.toggle(station); saved = Stations.saved } label: {
                Label(fav ? "إزالة من المفضلة" : "إضافة إلى المفضلة", systemImage: fav ? "star.slash" : "star")
            }
            if let u = URL(string: station.url) { ShareLink(item: u) { Label("مشاركة الرابط", systemImage: "square.and.arrow.up") } }
        }
    }

    /// قوائم التشغيل: علامة صح على القوائم التي فيها الإذاعة، والضغط يضيف أو يزيل
    @ViewBuilder private var addMenu: some View {
        ForEach(lists.lists) { pl in
            let inside = pl.stations.contains { $0.url == station.url }
            Button {
                if inside { lists.remove(station.url, from: pl.id) } else { lists.add(station, to: pl.id) }
            } label: {
                Label(pl.name, systemImage: inside ? "checkmark.circle.fill" : "plus.circle")
            }
        }
        Divider()
        Button { lists.askNew(with: station) } label: { Label("قائمة تشغيل جديدة…", systemImage: "plus") }
    }
}

// MARK: - تصفّح وبحث

struct StationBrowser: View {
    let category: RadioCategory
    @Binding var saved: [Station]
    @State private var q = ""
    @State private var country = ""
    @State private var order = "clickcount"
    @State private var results: [Station] = []
    @State private var loading = false
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                HStack {
                    if category.country == nil {
                        Menu {
                            Picker("الدولة", selection: $country) {
                                ForEach(RadioCountries.list, id: \.0) { c in Text(L(c.1)).tag(c.0) }
                            }
                        } label: { filterChip("globe", country.isEmpty ? L("كل الدول") : RadioCountries.name(country)) }
                    }
                    Menu {
                        Picker("الترتيب", selection: $order) {
                            Text("الأكثر استماعًا").tag("clickcount")
                            Text("الأعلى تقييمًا").tag("votes")
                            Text("الأعلى جودة").tag("bitrate")
                            Text("الاسم").tag("name")
                        }
                    } label: { filterChip("arrow.up.arrow.down", orderName) }
                    Spacer(minLength: 0)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))

            Section {
                if loading && results.isEmpty {
                    HStack { Spacer(); ProgressView().tint(Theme.gold); Spacer() }.padding(.vertical, 20)
                } else if loaded && results.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash").font(Theme.f(.title2)).foregroundStyle(Theme.sub)
                        Text("لا توجد نتائج. جرّب اسمًا آخر أو دولة أخرى.").font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
                }
                ForEach(results) { s in StationRow(station: s, saved: $saved) }
            } footer: {
                Text("من دليل radio-browser.info المفتوح. الإذاعات المعطّلة مستبعدة تلقائيًا.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .searchable(text: $q, prompt: "اسم الإذاعة")
        .onSubmit(of: .search) { Task { await load() } }
        .navigationTitle(L(category.title))
        .navigationBarTitleDisplayMode(.inline)
        .task { if !loaded { await load() } }
        .onChange(of: country) { Task { await load() } }
        .onChange(of: order) { Task { await load() } }
        .refreshable { await load() }
    }

    private var orderName: String {
        switch order { case "votes": L("الأعلى تقييمًا"); case "bitrate": L("الأعلى جودة"); case "name": L("الاسم"); default: L("الأكثر استماعًا") }
    }

    private func filterChip(_ icon: String, _ t: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(Theme.f(.caption))
            Text(verbatim: t).font(Theme.f(.footnote, .semibold))
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    private func load() async {
        loading = true
        // عربي فقط: لغة البث عربية دائمًا، وإن لم تُحدَّد دولة فالدول العربية كلها
        let r = await Stations.search(q.trimmingCharacters(in: .whitespaces), country: country.isEmpty ? category.country : country,
                                      tag: category.tag, language: category.language ?? "arabic", limit: 100, order: order)
        // لغة البث عربية تكفي: تشمل إذاعات عربية تبث من خارج الدول العربية (مثل مونت كارلو الدولية)
        results = order == "name" ? r.sorted { $0.name.localizedCompare($1.name) == .orderedAscending } : r
        loading = false
        loaded = true
    }
}

// MARK: - إدارة المفضلة: ترتيب، حذف، تعديل الاسم، إضافة برابط

struct FavoritesManager: View {
    @Binding var saved: [Station]
    @State private var adding = false
    @State private var renaming: Station?
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                Button { adding = true } label: {
                    TileRow(title: "إضافة إذاعة برابط", icon: "link.badge.plus", color: .teal, subtitle: "رابط بث مباشر (MP3 / AAC / M3U8)")
                }
            }
            Section {
                if saved.isEmpty {
                    Text("لا توجد إذاعات في المفضلة بعد. اضغط النجمة بجانب أي إذاعة لإضافتها.")
                        .font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
                }
                ForEach(saved) { s in
                    HStack(spacing: 12) {
                        StationArt(station: s, size: 38)
                        Text(verbatim: s.name).foregroundStyle(.white).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .swipeActions(edge: .leading) {
                        Button { newName = s.name; renaming = s } label: { Label("تعديل الاسم", systemImage: "pencil") }.tint(.blue)
                    }
                }
                .onMove { from, to in var l = saved; l.move(fromOffsets: from, toOffset: to); Stations.saved = l; saved = l }
                .onDelete { idx in var l = saved; l.remove(atOffsets: idx); Stations.saved = l; saved = l }
            } header: {
                Text("المفضلة")
            } footer: {
                Text("رتّب الإذاعات بالسحب بعد «تعديل». ترتيبها هنا هو ترتيب التنقّل بالأمام والخلف من الويدجت وشاشة القفل.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .navigationTitle("المفضلة")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !saved.isEmpty { EditButton().tint(Theme.gold) } }
        .sheet(isPresented: $adding) { AddStationSheet(saved: $saved) }
        .alert("تعديل الاسم", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("الاسم", text: $newName)
            Button("حفظ") {
                if let r = renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Stations.rename(r, to: newName.trimmingCharacters(in: .whitespaces)); saved = Stations.saved
                }
                renaming = nil
            }
            Button("إلغاء", role: .cancel) { renaming = nil }
        }
    }
}

struct AddStationSheet: View {
    @Binding var saved: [Station]
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""

    private var valid: URL? {
        let t = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: t), let s = u.scheme?.lowercased(), s == "https" || s == "http", u.host != nil else { return nil }
        return u
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("اسم الإذاعة", text: $name)
                    TextField("https://…", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                } footer: {
                    Text("الصق رابط البث المباشر للإذاعة. يمكنك تجربته قبل الحفظ.")
                }
                Section {
                    Button { if let u = valid { AudioPlayer.shared.playStation(Station(name: displayName, url: u.absoluteString)) } } label: {
                        Label("تجربة التشغيل", systemImage: "play.circle")
                    }
                    .disabled(valid == nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("إضافة إذاعة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        guard let u = valid else { return }
                        let s = Station(name: displayName, url: u.absoluteString)
                        if !Stations.isSaved(s) { Stations.toggle(s) }
                        saved = Stations.saved
                        dismiss()
                    }
                    .disabled(valid == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var displayName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? (valid?.host ?? L("إذاعة")) : n
    }
}

// MARK: - شبكة التصنيفات

struct RadioCategoryGrid: View {
    let onPick: (RadioCategory) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(RadioCategory.all) { c in
                Button { onPick(c) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: c.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(c.color)
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(c.color.opacity(0.16)))
                        Text(L(c.title)).font(Theme.f(.subheadline, .semibold)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
                    .environment(\.colorScheme, .dark)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - الدول: «راديو السعودية»، «راديو مصر»… وفي كل دولة أقسامها

struct RadioCountry: Hashable, Identifiable {
    let code: String
    let name: String
    var id: String { code }
    /// الدول العربية: البث العربي فقط؛ (لا نقيّد اللغة إن كانت الإذاعات قليلة جدًا فيها)
    var arabicOnly = true
    var flag: String {
        code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
    }

    /// الدول الرئيسية (فيها إذاعات كثيرة)
    static let main: [RadioCountry] = [
        .init(code: "SA", name: L("السعودية")), .init(code: "EG", name: L("مصر")), .init(code: "AE", name: L("الإمارات")),
        .init(code: "KW", name: L("الكويت")), .init(code: "QA", name: L("قطر")), .init(code: "OM", name: L("عُمان")),
        .init(code: "BH", name: L("البحرين")), .init(code: "JO", name: L("الأردن")), .init(code: "IQ", name: L("العراق")),
        .init(code: "LB", name: L("لبنان")), .init(code: "SY", name: L("سوريا")), .init(code: "PS", name: L("فلسطين")),
        .init(code: "MA", name: L("المغرب")), .init(code: "DZ", name: L("الجزائر")), .init(code: "TN", name: L("تونس")),
    ]
    /// دول عربية أخرى (إذاعاتها قليلة) — داخل «دول عربية أخرى»
    static let others: [RadioCountry] = [
        .init(code: "LY", name: L("ليبيا")), .init(code: "SD", name: L("السودان")), .init(code: "YE", name: L("اليمن")),
        .init(code: "MR", name: L("موريتانيا")), .init(code: "SO", name: L("الصومال"), arabicOnly: false),
        .init(code: "DJ", name: L("جيبوتي"), arabicOnly: false), .init(code: "KM", name: L("جزر القمر"), arabicOnly: false),
    ]
}

/// شبكة الدول في «تصفّح»
struct RadioCountryGrid: View {
    let onPick: (RadioCountry) -> Void
    let onOthers: () -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(RadioCountry.main) { c in
                Button { onPick(c) } label: { tile(c.flag, LF("راديو %@", c.name)) }.buttonStyle(.plain)
            }
            Button { onOthers() } label: { tile("🌍", L("دول عربية أخرى")) }.buttonStyle(.plain)
        }
    }

    private func tile(_ flag: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: flag).font(.system(size: 22))
                .frame(width: 32, height: 32)
            Text(verbatim: title).font(Theme.f(.subheadline, .semibold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }
}

/// صفحة الدولة: أقسامها (القرآن، الأكثر استماعًا، الأخبار، الرياضة، البرامج)
struct CountryRadioView: View {
    let country: RadioCountry
    @Binding var saved: [Station]
    @State private var cat: RadioCategory?

    private var sections: [RadioCategory] {
        RadioCategory.all.filter { $0.country == nil }.map { $0.inCountry(country) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Text(verbatim: country.flag).font(.system(size: 44))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: LF("راديو %@", country.name)).font(Theme.title(24)).foregroundStyle(.white)
                        Text("اختر قسمًا، أو اضغط «كل الإذاعات»").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)

            let official = OfficialRadio.list(country.code)
            if !official.isEmpty {
                Section {
                    ForEach(official) { s in StationRow(station: s, saved: $saved) }
                } header: {
                    Text("الإذاعات الرسمية")
                } footer: {
                    Text("لكل إذاعة رسمية روابط احتياطية تُجرَّب تلقائيًا إن تعطّل البث.")
                }
            }

            Section {
                let all = RadioCategory(title: L("كل الإذاعات") + " — " + country.name, icon: "dot.radiowaves.left.and.right",
                                        color: .teal, language: country.arabicOnly ? "arabic" : nil, country: country.code)
                Button { cat = all } label: {
                    TileRow(title: "كل الإذاعات", icon: "dot.radiowaves.left.and.right", color: .teal, subtitle: "الأكثر استماعًا أولًا")
                }
                .buttonStyle(.plain)
                ForEach(sections) { c in
                    Button { cat = c } label: {
                        TileRow(title: String(c.title.split(separator: "—").first ?? "").trimmingCharacters(in: .whitespaces),
                                icon: c.icon, color: c.color, subtitle: nil)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("الأقسام")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .navigationTitle(LF("راديو %@", country.name))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $cat) { c in StationBrowser(category: c, saved: $saved) }
    }
}

/// «دول عربية أخرى»
struct OtherCountriesView: View {
    @Binding var saved: [Station]
    var body: some View {
        List {
            Section {
                ForEach(RadioCountry.others) { c in
                    NavigationLink { CountryRadioView(country: c, saved: $saved) } label: {
                        HStack(spacing: 12) {
                            Text(verbatim: c.flag).font(.system(size: 26))
                            Text(verbatim: LF("راديو %@", c.name)).foregroundStyle(.white)
                        }
                    }
                }
            } footer: {
                Text("دول إذاعاتها في الدليل المفتوح قليلة.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .navigationTitle("دول عربية أخرى")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - قوائم التشغيل

@MainActor
final class PlaylistStore: ObservableObject {
    static let shared = PlaylistStore()
    @Published private(set) var lists: [RadioPlaylist] = Playlists.all
    /// طلب قائمة جديدة (من زر «قائمة تشغيل جديدة…» في أي صف)
    @Published var newFor: Station?
    @Published var askingNew = false

    private func sync() {
        lists = Playlists.all
        RafiqiKinds.reload()
        Task { await LogoCache.fetch(lists.flatMap(\.stations).compactMap(\.favicon)) }
    }
    func add(_ s: Station, to id: String) { Playlists.add(s, to: id); sync() }
    func remove(_ url: String, from id: String) { Playlists.remove(url, from: id); sync() }
    func setStations(_ id: String, _ l: [Station]) { Playlists.setStations(id, l); sync() }
    func rename(_ id: String, _ n: String) { Playlists.rename(id, n); sync() }
    func delete(_ id: String) { Playlists.delete(id); sync() }
    @discardableResult func create(_ n: String, with s: Station? = nil) -> String {
        let id = Playlists.create(n)
        if let s { Playlists.add(s, to: id) }
        sync()
        return id
    }
    func askNew(with s: Station? = nil) { newFor = s; askingNew = true }
}

/// حقل اسم القائمة الجديدة (يُعرض من الصفحة الرئيسية للإذاعات)
struct NewPlaylistAlert: ViewModifier {
    @ObservedObject private var store = PlaylistStore.shared
    @State private var name = ""
    func body(content: Content) -> some View {
        content.alert("قائمة تشغيل جديدة", isPresented: $store.askingNew) {
            TextField("اسم القائمة", text: $name)
            Button("إنشاء") {
                let n = name.trimmingCharacters(in: .whitespaces)
                store.create(n.isEmpty ? L("قائمتي") : n, with: store.newFor)
                name = ""; store.newFor = nil
            }
            Button("إلغاء", role: .cancel) { name = ""; store.newFor = nil }
        } message: {
            if let s = store.newFor { Text(verbatim: LF("وتُضاف إليها «%@»", s.name)) }
        }
    }
}

/// صفحة قائمة تشغيل: تشغيل، ترتيب، حذف، إعادة تسمية، وإضافة من الدول
struct PlaylistView: View {
    let id: String
    @Binding var saved: [Station]
    @ObservedObject private var store = PlaylistStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        let pl = store.lists.first { $0.id == id }
        List {
            if let pl {
                Section {
                    if pl.stations.isEmpty {
                        Text("القائمة فارغة. اضغط «إضافة إذاعات» واختر دولة، ثم اضغط زر الإضافة بجانب أي إذاعة.")
                            .font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
                    }
                    ForEach(pl.stations) { s in StationRow(station: s, saved: $saved, showAdd: false) }
                        .onMove { from, to in var l = pl.stations; l.move(fromOffsets: from, toOffset: to); store.setStations(id, l) }
                        .onDelete { idx in var l = pl.stations; l.remove(atOffsets: idx); store.setStations(id, l) }
                } header: {
                    Text(verbatim: stationsText(pl.stations.count))
                } footer: {
                    Text("اسحب للحذف، أو اضغط «تعديل» لإعادة الترتيب. تظهر إذاعات القوائم في ويدجت البكرة، وتنتقل بينها بزرّي التالي والسابق.")
                }
                Section {
                    NavigationLink { AllCountriesView(saved: $saved) } label: {
                        TileRow(title: "إضافة إذاعات", icon: "plus.circle.fill", color: .green, subtitle: "من الدول العربية وأقسامها")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .navigationTitle(pl?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !(pl?.stations.isEmpty ?? true) { EditButton().tint(Theme.gold) }
                Menu {
                    Button { newName = pl?.name ?? ""; renaming = true } label: { Label("إعادة التسمية", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("حذف القائمة", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(Theme.gold) }
            }
        }
        .alert("إعادة التسمية", isPresented: $renaming) {
            TextField("اسم القائمة", text: $newName)
            Button("حفظ") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { store.rename(id, n) }
            }
            Button("إلغاء", role: .cancel) {}
        }
        .confirmationDialog("حذف هذه القائمة؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) { store.delete(id); dismiss() }
        }
    }
}

/// كل الدول (للإضافة إلى القوائم)
struct AllCountriesView: View {
    @Binding var saved: [Station]
    @State private var country: RadioCountry?
    @State private var others = false
    var body: some View {
        List {
            Section {
                RadioCountryGrid(onPick: { country = $0 }, onOthers: { others = true })
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            } footer: {
                Text("اختر دولة ثم قسمًا، واضغط زر الإضافة بجانب الإذاعة لتضيفها إلى القائمة.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .navigationTitle("الدول")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $country) { c in CountryRadioView(country: c, saved: $saved) }
        .navigationDestination(isPresented: $others) { OtherCountriesView(saved: $saved) }
    }
}
