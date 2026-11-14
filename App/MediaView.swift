import SwiftUI
import MediaPlayer

// MARK: - تبويب الصوتيات: القرآن، الإذاعات، Apple Music

struct MediaView: View {
    @ObservedObject private var p = AudioPlayer.shared
    @ObservedObject private var dl = QuranDownloads.shared
    @State private var section = ["media2": 1, "media4": 1, "media5": 2][SHOT] ?? 0
    @State private var reciters: [Reciter] = Reciters.builtin
    @State private var reciter = Reciters.selected
    @State private var saved = Stations.saved
    @State private var radioCountry: RadioCountry?
    @State private var otherCountries = false
    @ObservedObject private var lists = PlaylistStore.shared
    @State private var browse: RadioCategory? = SHOT == "media4" ? RadioCategory.all[1] : nil
    @State private var showSurahs = SHOT == "media3"
    @State private var musicOK = MPMediaLibrary.authorizationStatus() == .authorized

    var body: some View {
        NavigationStack {
            List {
                Section { PageHeader(title: "المسموع والمرئي", subtitle: L("القرآن الكريم والإذاعات والقنوات التلفزيونية")) }
                    .bareRow(top: 0, bottom: 0)
                if !(section == 1 && p.state.source == .radio) {
                    Section { nowPlaying }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                Section {
                    ChipBar(items: ["القرآن", "الإذاعات", "القنوات", "Apple Music"], selection: $section)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                switch section {
                case 0: quranSections
                case 1: radioSections
                case 2: TVSections()
                default: musicSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .barSpace()
            .toolbar(.hidden, for: .navigationBar)
            .task {
                reciters = await Reciters.load()
                // شعارات الإذاعات المحفوظة والقنوات (لتظهر في الويدجت)، وروابط القنوات الأحدث
                await TVChannels.refreshIfNeeded()
                await LogoCache.fetch(Stations.saved.compactMap(\.favicon) + TVChannels.all.map(\.logo))
            }
            .onChange(of: saved) { _, s in Task { await LogoCache.fetch(s.compactMap(\.favicon)); RafiqiKinds.reload() } }
            .navigationDestination(item: $browse) { c in StationBrowser(category: c, saved: $saved) }
            .navigationDestination(item: $radioCountry) { c in CountryRadioView(country: c, saved: $saved) }
            .navigationDestination(isPresented: $otherCountries) { OtherCountriesView(saved: $saved) }
            .modifier(NewPlaylistAlert())
            .navigationDestination(isPresented: $showSurahs) { SurahsView(reciter: reciter) }
            .onAppear { saved = Stations.saved }
        }
    }

    // ── المشغّل الحالي ──
    var nowPlaying: some View {
        let s = p.state
        return HStack(spacing: 14) {
            MediaArt(source: s.source, corner: 16, label: s.title)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(Theme.title(17)).foregroundStyle(.white).lineLimit(1)
                Text(s.subtitle).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                if p.loading { ProgressView().controlSize(.mini).tint(Theme.gold) }
                else if let at = p.sleepAt {
                    Label { Text(at, style: .timer).monospacedDigit() } icon: { Image(systemName: "moon.zzz.fill") }
                        .font(.caption2).foregroundStyle(Theme.gold)
                } else if p.sleepAtEnd {
                    Label("يتوقف عند نهاية السورة", systemImage: "moon.zzz.fill").font(.caption2).foregroundStyle(Theme.gold)
                }
            }
            Spacer(minLength: 0)
            if s.source != .music { SleepMenu(label: false).frame(minWidth: 30) }
            HStack(spacing: 6) {
                ctrl("backward.fill") { AudioPlayer.shared.previous() }
                ctrl(s.playing ? "pause.fill" : "play.fill", big: true) { AudioPlayer.shared.toggle() }
                ctrl("forward.fill") { AudioPlayer.shared.next() }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .glassCard(padding: 14)
    }

    func ctrl(_ icon: String, big: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: big ? 18 : 13, weight: .bold)).foregroundStyle(big ? .black : .white)
                .frame(width: big ? 44 : 34, height: big ? 44 : 34)
                .background(Circle().fill(big ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(Theme.cardHi)))
        }
        .buttonStyle(.plain)
    }

    // ── القرآن ──
    @ViewBuilder var quranSections: some View {
        Section {
            NavigationLink {
                ReciterPicker(list: reciters, selected: $reciter)
            } label: {
                TileRow(title: "القارئ", icon: "person.wave.2.fill", color: .teal, subtitle: reciter.name)
            }
        }
        Section {
            NavigationLink {
                SurahsView(reciter: reciter)
            } label: {
                let st = dl.stats(reciter)
                TileRow(title: "السور", icon: "book.closed.fill", color: Theme.gold,
                        subtitle: st.count > 0 ? LF("١١٤ سورة · منزّل %@", ar(st.count)) : L("١١٤ سورة · اضغط للتشغيل أو التنزيل"))
            }
            if let r = dl.fullFor, r == reciter.id {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(dl.fullDone), total: Double(max(1, dl.fullTotal))).tint(Theme.gold)
                    Text(verbatim: LF("جارٍ تنزيل المصحف: %@ من %@", ar(dl.fullDone), ar(dl.fullTotal)))
                        .font(.caption).foregroundStyle(Theme.sub)
                }
            }
        } footer: {
            Text("التلاوات من مكتبة mp3quran.net المجانية. نزّل السور أو المصحف كاملًا لتستمع بدون إنترنت.")
        }
    }

    // ── الإذاعات ──
    @ViewBuilder var radioSections: some View {
        if p.state.source == .radio {
            Section { RadioPlayerCard(saved: $saved) }
                .bareRow()
        }
        // قوائم التشغيل (بدل «إذاعات مختارة»): أكثر من قائمة، وكل قائمة صفحة بإذاعاتها
        Section {
            ForEach(lists.lists) { pl in
                NavigationLink { PlaylistView(id: pl.id, saved: $saved) } label: {
                    TileRow(title: pl.name, icon: "music.note.list", color: .pink,
                            subtitle: LF("%@ إذاعة", ar(pl.stations.count)))
                }
            }
            Button { lists.askNew() } label: {
                Label("قائمة تشغيل جديدة", systemImage: "plus.circle.fill")
                    .font(.subheadline).foregroundStyle(Theme.gold)
            }
        } header: {
            Text("قوائم التشغيل")
        }
        Section {
            RadioCountryGrid(onPick: { radioCountry = $0 }, onOthers: { otherCountries = true })
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        } header: {
            Text("تصفّح حسب الدولة")
        }
        Section {
            Button { browse = .search } label: {
                TileRow(title: "البحث في آلاف الإذاعات", icon: "magnifyingglass", color: .indigo, subtitle: "بالاسم أو الدولة، مع الترتيب والجودة")
            }
            .buttonStyle(.plain)
        }
        Section {
            if saved.isEmpty {
                Text("اضغط النجمة بجانب أي إذاعة لتظهر هنا، أو أضف إذاعة برابطها.")
                    .font(.footnote).foregroundStyle(Theme.sub)
            }
            ForEach(saved) { s in StationRow(station: s, saved: $saved) }
            NavigationLink {
                FavoritesManager(saved: $saved)
            } label: {
                Label("ترتيب المفضلة وإضافة إذاعة برابط", systemImage: "slider.horizontal.3")
                    .font(.subheadline).foregroundStyle(Theme.gold)
            }
        } header: {
            Text("المفضلة")
        }
        Section {
        } footer: {
            Text("التنقّل بالأمام والخلف من الويدجت وشاشة القفل يمرّ على المفضلة ثم قوائم التشغيل بترتيبها. أضف أي إذاعة إلى قائمة بزر الإضافة بجانبها. تعيد الإذاعة الاتصال تلقائيًا إذا انقطع البث.")
        }
    }

    // ── Apple Music ──
    var musicSection: some View {
        Section {
            if musicOK {
                Button { AudioPlayer.shared.useAppleMusic() } label: {
                    TileRow(title: "التحكم في Apple Music من الويدجت", icon: "music.note", color: .pink,
                            subtitle: p.state.source == .music ? "مفعّل الآن" : "اضغط للتفعيل")
                }
            } else {
                Button {
                    Task { musicOK = await AudioPlayer.requestMusicAccess(); if musicOK { AudioPlayer.shared.useAppleMusic() } }
                } label: {
                    TileRow(title: "السماح بالوصول إلى Apple Music", icon: "music.note", color: .pink,
                            subtitle: "لعرض اسم المقطع والتحكم فيه")
                }
            }
        } footer: {
            Text("يعمل مع تطبيق Apple Music فقط. تتحدّث الويدجت عند استخدامها، وقد يتأخر ظهور اسم المقطع إذا غيّرته من تطبيق الموسيقى نفسه. لا يسمح النظام بالتحكم في تطبيقات أخرى مثل يوتيوب وسبوتيفاي.")
        }
    }
}

// MARK: - اختيار القارئ

struct ReciterPicker: View {
    let list: [Reciter]
    @Binding var selected: Reciter
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""

    var body: some View {
        List {
            ForEach(list.filter { q.isEmpty || $0.name.contains(q) }) { r in
                Button {
                    selected = r
                    Reciters.selected = r
                    dismiss()
                } label: {
                    HStack {
                        Text(r.name).foregroundStyle(.white)
                        Spacer()
                        if r.id == selected.id { Image(systemName: "checkmark").foregroundStyle(Theme.gold) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .searchable(text: $q, prompt: "ابحث عن قارئ")
        .navigationTitle("القارئ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
