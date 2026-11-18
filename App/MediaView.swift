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
                Section {
                    ChipBar(items: ["القرآن", "الإذاعات", "القنوات", "Apple Music"], selection: $section)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                // المشغّل الحالي عائم أسفل التطبيق (فوق شريط التبويب) — لا يتكرر داخل الصفحة

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
            .hiddenNavBar()
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

    // ── القرآن ──
    @ViewBuilder var quranSections: some View {
        // تابع الاستماع: آخر سورة سُمعت (إن لم تكن في المشغّل العائم الآن)
        if !(p.sessionActive && p.state.source == .quran) {
            let last = NowPlaying.last(.quran)
            Section {
                Button { AudioPlayer.shared.switchTo(.quran) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                            .frame(width: 44, height: 44).background(Circle().fill(Theme.gold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("تابع الاستماع").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                            Text(verbatim: L("سورة") + " " + Surahs.name(last.surah)).font(Theme.title(17)).foregroundStyle(.white)
                            Text(verbatim: last.subtitle.isEmpty ? reciter.name : last.subtitle).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                        }
                        Spacer(minLength: 0)
                        Text(verbatim: Surahs.info(last.surah)).font(Theme.f(.caption2)).foregroundStyle(Theme.sub)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        // سور يكثر سماعها
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach([18, 36, 67, 55, 56, 2, 1, 112], id: \.self) { n in
                        Button { AudioPlayer.shared.playQuran(n, reciter: reciter) } label: {
                            VStack(spacing: 4) {
                                Text(verbatim: Surahs.name(n)).font(Theme.title(16)).foregroundStyle(.white).lineLimit(1)
                                Text(verbatim: Surahs.info(n)).font(Theme.f(.caption2)).foregroundStyle(Theme.sub).lineLimit(1)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 2)
            }
        } header: { Text("سور مختارة") }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
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
                        .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                }
            }
        } footer: {
            Text("التلاوات من مكتبة mp3quran.net المجانية. نزّل السور أو المصحف كاملًا لتستمع بدون إنترنت.")
        }
    }

    // ── الإذاعات ──
    @ViewBuilder var radioSections: some View {
        // بطاقة الإذاعة الكاملة (المفضلة والتحديث والمؤقّت والمشاركة) تُفتح من المشغّل العائم
        // قوائم التشغيل (بدل «إذاعات مختارة»): أكثر من قائمة، وكل قائمة صفحة بإذاعاتها
        Section {
            ForEach(lists.lists) { pl in
                NavigationLink { PlaylistView(id: pl.id, saved: $saved) } label: {
                    TileRow(title: pl.name, icon: "music.note.list", color: .pink,
                            subtitle: stationsText(pl.stations.count))
                }
            }
            Button { lists.askNew() } label: {
                Label("قائمة تشغيل جديدة", systemImage: "plus.circle.fill")
                    .font(Theme.f(.subheadline)).foregroundStyle(Theme.gold)
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
                    .font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
            }
            ForEach(saved) { s in StationRow(station: s, saved: $saved) }
            NavigationLink {
                FavoritesManager(saved: $saved)
            } label: {
                Label("ترتيب المفضلة وإضافة إذاعة برابط", systemImage: "slider.horizontal.3")
                    .font(Theme.f(.subheadline)).foregroundStyle(Theme.gold)
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
        .navigationBarTitleDisplayMode(.large)
    }
}
