import SwiftUI
import AVFoundation
import UserNotifications

// MARK: - مركز الإشعارات

/// حالة مشتركة لإعدادات التنبيهات
final class NotifyStore: ObservableObject {
    @Published var at = Notify.atKeys
    @Published var pre = Notify.preKeys
    @Published var voice = Notify.voice
    @Published var extra = Notify.extraOn
    @Published var muezzin = Notify.muezzinID
    @Published var fajrMuezzin = Notify.fajrMuezzinID
    @Published var modes: [String: Notify.SoundMode] = Dictionary(uniqueKeysWithValues: Notify.items.map { ($0.id, Notify.mode($0.id)) })
    @Published var note = ""
    @Published var denied = false
    @Published var playing: String? = nil   // الصوت المسموع الآن (يتحوّل زره إلى إيقاف)
    private var player: AVAudioPlayer?

    func set(_ id: String, pre isPre: Bool, _ on: Bool) {
        if isPre {
            if on { pre.insert(id) } else { pre.remove(id) }
            Notify.preKeys = pre
        } else {
            if on { at.insert(id) } else { at.remove(id) }
            Notify.atKeys = at
        }
        apply(requesting: on)
    }

    func setExtra(_ id: String, _ on: Bool) {
        if on { extra.insert(id) } else { extra.remove(id) }
        Notify.extraOn = extra
        apply(requesting: on)
    }

    func setMode(_ key: String, _ m: Notify.SoundMode) {
        note = ""
        if m == .full {
            guard AdhanAlarms.supported else {
                Notify.setMode(key, .part); modes[key] = .part
                note = L("يتطلّب الأذان الكامل iOS 26.1 أو أحدث، لذا اختير جزء الأذان بدلًا منه.")
                apply(requesting: false)
                return
            }
            Task {
                _ = await Notify.askIfNeeded()
                let ok = await AdhanAlarms.requestAccess()
                await MainActor.run {
                    let final: Notify.SoundMode = ok ? .full : .part
                    Notify.setMode(key, final); self.modes[key] = final
                    if !ok { self.note = L("لم يُسمح لرفيقي باستخدام المنبّهات. فعّل الإذن من «الإعدادات» ← «رفيقي»، ثم اختر «الأذان كاملًا» مرة أخرى.") }
                }
                await Notify.reschedule()
            }
            return
        }
        Notify.setMode(key, m); modes[key] = m
        apply(requesting: false)
    }

    func setMuezzin(_ id: String, fajr: Bool) {
        if fajr { fajrMuezzin = id; Notify.fajrMuezzinID = id } else { muezzin = id; Notify.muezzinID = id }
        apply(requesting: false)
    }

    func playFile(_ file: String) {
        let name = (file as NSString).deletingPathExtension
        toggle(name)
    }

    func stopPlaying() { player?.stop(); playing = nil }

    /// تشغيل الصوت أو إيقافه إن كان هو المسموع الآن
    private func toggle(_ name: String) {
        if playing == name { stopPlaying(); return }
        guard let u = Bundle.main.url(forResource: name, withExtension: "caf") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: u)
        guard let p = player, p.play() else { playing = nil; return }
        playing = name
        DispatchQueue.main.asyncAfter(deadline: .now() + p.duration + 0.2) { [weak self, weak p] in
            guard let self, let p, self.player === p, !p.isPlaying else { return }
            self.playing = nil
        }
    }

    func isPlaying(file: String) -> Bool { playing == (file as NSString).deletingPathExtension }
    func isPlaying(_ id: String, pre isPre: Bool) -> Bool { playing == "miqat_\(isPre ? "pre_" : "")\(id)" }

    func setVoice(_ v: Bool) {
        voice = v; Notify.voice = v
        // الصلوات التي لم يُختر لها صوت تتبع هذا الخيار
        modes = Dictionary(uniqueKeysWithValues: Notify.items.map { ($0.id, Notify.mode($0.id)) })
        apply(requesting: false)
    }

    func apply(requesting: Bool) {
        Task {
            if requesting, !(await Notify.authorized()) {
                let ok = await Notify.requestPermission()
                await MainActor.run { self.denied = !ok }
            }
            await Notify.reschedule()
        }
    }

    func checkPermission() {
        Task {
            if SHOT.isEmpty, Notify.enabled { _ = await Notify.askIfNeeded(); await Notify.reschedule() }
            let s = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run { self.denied = s.authorizationStatus == .denied && Notify.enabled }
        }
    }

    /// تشغيل صوت التنبيه للتجربة
    func play(_ id: String, pre isPre: Bool) {
        toggle("miqat_\(isPre ? "pre_" : "")\(id)")
    }
}

extension Notify.Item {
    /// رمز الوقت بنمط التطبيق الموحّد
    var appIcon: String {
        switch id {
        case "fajr": return "moon.haze"
        case "sunrise": return "sunrise"
        case "dhuhr": return "sun.max"
        case "asr": return "sun.min"
        case "maghrib": return "sunset"
        case "isha": return "moon.stars"
        default: return "moon"
        }
    }
    var color: Color {
        switch id {
        case "fajr": return Color(red: 0.36, green: 0.78, blue: 0.45)
        case "sunrise": return Color(red: 0.98, green: 0.80, blue: 0.25)
        case "dhuhr": return Color(red: 0.98, green: 0.60, blue: 0.25)
        case "asr": return Color(red: 0.35, green: 0.75, blue: 0.92)
        case "maghrib": return Color(red: 0.78, green: 0.40, blue: 0.90)
        case "isha": return Color(red: 0.42, green: 0.40, blue: 0.95)
        default: return Color(white: 0.92)
        }
    }
    /// وقت اليوم (أو القادم) لهذا البند
    func time(on date: Date) -> Date? {
        if id == "midnight" { return Prayer.midnight(after: date)?.time }
        return Prayer.dayTimes(date).first { $0.key.rawValue == id || (id == "dhuhr" && $0.key == .jumuah) }?.time
    }
}

/// صفحة الإشعارات: تُفتح بالدفع داخل تنقّل الإعدادات (لا ورقة بتنقّل مستقل داخلها؛
/// ذلك كان يمنع فتح صفحات الصلوات والمؤذن عند الضغط)
struct NotifyCenterView: View {
    @StateObject private var store = NotifyStore()
    @State private var openID: String? = SHOT == "notifyd" ? "dhuhr" : nil
    @State private var picker: Int? = nil   // ٠ المؤذن، ١ أذان الفجر
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BackRow()
                    PageHeader(title: "الإشعارات", subtitle: L("تنبيهات الأوقات بصوت رفيقي"))
                    NotifPreview()
                    if store.denied {
                        Button {
                            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                        } label: {
                            TileRow(title: "الإشعارات غير مسموح بها", icon: "exclamationmark.triangle.fill", color: .red,
                                    subtitle: "اضغط هنا، ثم فعّل «السماح بالإشعارات» لتطبيق رفيقي.")
                                .glassCard(padding: 14)
                        }
                        .buttonStyle(.plain)
                    }

                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(Notify.items) { it in
                            Button { openID = it.id } label: { tile(it) }
                                .buttonStyle(PressStyle())
                        }
                    }

                    adhanCard

                    extras

                    Toggle(isOn: Binding(get: { store.voice }, set: { store.setVoice($0) })) {
                        TileRow(title: "الصوت الناطق", icon: "speaker.wave.2.fill", color: .teal,
                                subtitle: "يُعلن التنبيه بصوت، مثل: «حان وقت صلاة الظهر»")
                    }
                    .tint(Theme.gold)
                    .glassCard(padding: 14)

                    Text("تصل الإشعارات والتطبيق مغلق، وتتجدّد تلقائيًا بحسب موقعك.")
                        .font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .hiddenNavBar()
            .navigationDestination(isPresented: Binding(get: { openID != nil }, set: { if !$0 { openID = nil } })) {
                if let id = openID, let it = Notify.item(id) { NotifyDetail(item: it, store: store) }
            }
            .navigationDestination(isPresented: Binding(get: { picker != nil }, set: { if !$0 { picker = nil } })) {
                MuezzinPicker(store: store, fajr: picker == 1)
            }
            .onAppear { store.checkPermission() }
    }

    /// المؤذن (لجزء الأذان والأذان كاملًا)
    var adhanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("الأذان").font(Theme.title(17)).foregroundStyle(.white)
            Button { picker = 0 } label: {
                TileRow(title: "المؤذن", icon: "speaker.wave.3.fill", color: Theme.goldDeep,
                        subtitle: Notify.muezzin(for: "dhuhr").name)
            }
            .buttonStyle(.plain)
            Divider().overlay(Theme.stroke)
            Button { picker = 1 } label: {
                TileRow(title: "أذان الفجر", icon: "sunrise.fill", color: Color(red: 0.36, green: 0.78, blue: 0.45),
                        subtitle: Notify.muezzin(for: "fajr").name)
            }
            .buttonStyle(.plain)
            Text("اختر صوت كل صلاة من صفحتها: التنبيه الناطق، أو نغمة، أو جزء من الأذان، أو الأذان كاملًا.")
                .font(Theme.f(.caption)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
        }
        .glassCard(padding: 14)
        .id(store.muezzin + store.fajrMuezzin)
    }

    /// تنبيهات صوتية إضافية (لا تظهر في المواقيت ولا الويدجت)
    var extras: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("تنبيهات إضافية").font(Theme.title(17)).foregroundStyle(.white)
            extraRow("duha", title: "صلاة الضحى", icon: "sun.max.fill", color: Color(red: 0.98, green: 0.70, blue: 0.25),
                     subtitle: LF("كل يوم قبل أذان الظهر بـ%@ دقيقة", ar(Notify.duhaBeforeDhuhr)))
            Divider().overlay(Theme.stroke)
            extraRow("jhour", title: "ساعة الإجابة يوم الجمعة", icon: "hands.and.sparkles.fill", color: Color(red: 0.55, green: 0.45, blue: 0.95),
                     subtitle: LF("كل جمعة قبل أذان المغرب بـ%@ دقيقة", ar(Notify.jhourBeforeMaghrib)))
        }
        .glassCard(padding: 14)
    }

    func extraRow(_ id: String, title: String, icon: String, color: Color, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { store.extra.contains(id) }, set: { store.setExtra(id, $0) })) {
                TileRow(title: title, icon: icon, color: color, subtitle: subtitle)
            }
            .tint(Theme.gold)
            if store.voice {
                Button { store.play(id, pre: false) } label: {
                    Image(systemName: store.isPlaying(id, pre: false) ? "stop.circle.fill" : "play.circle.fill")
                        .font(Theme.f(.title3)).foregroundStyle(Theme.gold)
                }
                .accessibilityLabel(L(store.isPlaying(id, pre: false) ? "إيقاف" : "تشغيل"))
                .buttonStyle(.borderless)
            }
        }
    }

    func tile(_ it: Notify.Item) -> some View {
        let on = store.at.contains(it.id), pre = store.pre.contains(it.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Badge(name: it.appIcon, size: 34, active: on || pre)
                Fit("pr_\(it.id)_t", 72, 28)
                Spacer(minLength: 0)
                Image(systemName: Lang.isEN ? "chevron.right" : "chevron.left").font(Theme.f(.footnote, .bold)).foregroundStyle(Theme.sub)
            }
            HStack(spacing: 6) {
                Image(systemName: on ? "bell.fill" : "bell.slash")
                    .font(Theme.f(.caption)).foregroundStyle(on ? Theme.gold : Theme.sub)
                Text(L(on ? (pre ? "مفعّل، وقبله بـ٥ دقائق" : "مفعّل") : (pre ? "قبله بـ٥ دقائق فقط" : "متوقّف")))
                    .font(Theme.f(.caption)).foregroundStyle(on || pre ? .white.opacity(0.85) : Theme.sub)
                Spacer(minLength: 0)
                if let t = it.time(on: Date()) {
                    Digits(text: hm12(t), size: 13, color: .white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(on || pre ? Theme.gold.opacity(0.08) : Theme.card)
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(on || pre ? AnyShapeStyle(Theme.gold.opacity(0.35)) : AnyShapeStyle(Theme.edge), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }
}

/// معاينة شكل الإشعار كما يصل على شاشة القفل
struct NotifPreview: View {
    var body: some View {
        let st = Prayer.prevNext(at: Date())
        let key = st.next.key == .midnight ? PKey.isha : st.next.key
        VStack(alignment: .leading, spacing: 8) {
            Text("هكذا يصلك التنبيه").font(Theme.title(14)).foregroundStyle(Theme.sub)
            HStack(alignment: .center, spacing: 10) {
                Image(AppIcons.currentPreview).resizable().scaledToFit().frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(Notify.title(key.rawValue, pre: false)).font(Theme.f(.subheadline, .semibold)).foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("الآن").font(Theme.f(.caption2)).foregroundStyle(Theme.sub)
                    }
                    if !Settings.placeName.isEmpty {
                        Text(Settings.placeName).font(Theme.f(.caption, .semibold)).foregroundStyle(.white.opacity(0.85))
                    }
                    Text(LF("الساعة %@", hm12(st.next.time)) + ".").font(Theme.f(.caption)).foregroundStyle(.white.opacity(0.75))
                }
                ZStack {
                    LinearGradient(colors: key.sky, startPoint: .top, endPoint: .bottom)
                    Fit("pr_\(key.rawValue)_t", 40, 22)
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.regularMaterial))
            .environment(\.colorScheme, .dark)
        }
    }
}

struct NotifyDetail: View {
    let item: Notify.Item
    @ObservedObject var store: NotifyStore

    var body: some View {
        let jumuahNote = item.id == "dhuhr"
        List {
            Section {
                VStack(spacing: 10) {
                    Badge(name: item.appIcon, size: 84, active: true)
                    Text(L(item.name)).font(Theme.title(28)).foregroundStyle(.white)
                    if let t = item.time(on: Date()) {
                        HStack(spacing: 6) {
                            Text("وقت اليوم").font(Theme.f(.subheadline)).foregroundStyle(Theme.sub)
                            Digits(text: hm12(t), size: 17, color: Theme.gold, bold: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                row(pre: false,
                    title: item.isPrayer ? "تنبيه دخول الوقت" : "تنبيه عند حلوله",
                    icon: "bell.badge.fill", color: .red)
            } footer: {
                Text(LF("نص الإشعار: «%@»", Notify.title(item.id, pre: false))
                     + (jumuahNote ? LF("، ويوم الجمعة: «%@».", Notify.title("jumuah", pre: false)) : "."))
            }

            if item.isPrayer {
                Section {
                    ForEach(Notify.SoundMode.allCases) { m in
                        Button { store.setMode(item.id, m) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.title).foregroundStyle(.white)
                                    Text(m.subtitle).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: store.modes[item.id] == m ? "checkmark.circle.fill" : "circle")
                                    .font(Theme.f(.title3)).foregroundStyle(store.modes[item.id] == m ? Theme.gold : Theme.sub)
                            }
                        }
                    }
                    if store.modes[item.id] == .part || store.modes[item.id] == .full {
                        Button { store.playFile(Notify.muezzin(for: item.id).part) } label: {
                            Label(LF("استمع: %@", Notify.muezzin(for: item.id).name),
                                  systemImage: store.isPlaying(file: Notify.muezzin(for: item.id).part) ? "stop.circle.fill" : "play.circle.fill")
                                .font(Theme.f(.subheadline)).foregroundStyle(Theme.gold)
                        }
                        .buttonStyle(.borderless)
                    }
                    if !store.note.isEmpty {
                        Text(store.note).font(Theme.f(.footnote)).foregroundStyle(.orange)
                    }
                } header: {
                    Text("صوت تنبيه دخول الوقت")
                } footer: {
                    Text("يعمل الأذان الكامل كمنبّه: يُسمع والجوال صامت أو مقفل، ويتكرر حتى تضغط «إيقاف». يُجدوَل عند فتح التطبيق لثلاثة أيام قادمة، لذا افتح رفيقي مرة كل يومين على الأقل.")
                }
            }

            Section {
                row(pre: true,
                    title: item.isPrayer ? LF("تنبيه قبل الأذان بـ%@ دقائق", ar(Notify.preMinutes)) : LF("تنبيه قبله بـ%@ دقائق", ar(Notify.preMinutes)),
                    icon: "clock.badge.exclamationmark.fill", color: .orange)
            } footer: {
                Text(LF("نص الإشعار: «%@»", Notify.title(item.id, pre: true))
                     + (jumuahNote ? LF("، ويوم الجمعة: «%@».", Notify.title("jumuah", pre: true)) : "."))
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(L(item.name))
        .navigationBarTitleDisplayMode(.large)
        .onDisappear { store.stopPlaying(); store.note = "" }
    }

    func row(pre: Bool, title: String, icon: String, color: Color) -> some View {
        let on = (pre ? store.pre : store.at).contains(item.id)
        return VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { on }, set: { store.set(item.id, pre: pre, $0) })) {
                TileRow(title: title, icon: icon, color: color)
            }
            .tint(Theme.gold)
            // صوت التنبيه الناطق (لتنبيه دخول الوقت فقط إذا كان صوته «التنبيه الناطق»)
            if store.voice && (pre || !item.isPrayer || store.modes[item.id] == .voice) {
                Button { store.play(item.id, pre: pre) } label: {
                    Label("استمع إلى الصوت", systemImage: store.isPlaying(item.id, pre: pre) ? "stop.circle.fill" : "play.circle.fill")
                        .font(Theme.f(.subheadline)).foregroundStyle(Theme.gold)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - اختيار المؤذن

struct MuezzinPicker: View {
    @ObservedObject var store: NotifyStore
    let fajr: Bool
    private var list: [Notify.Muezzin] { fajr ? [Notify.fajrAdhan] + Notify.muezzins : Notify.muezzins }
    private var selected: String { fajr ? store.fajrMuezzin : store.muezzin }

    var body: some View {
        List {
            Section {
                ForEach(list) { m in
                    HStack(spacing: 12) {
                        Button { store.setMuezzin(m.id, fajr: fajr) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: m.id == selected ? "checkmark.circle.fill" : "circle")
                                    .font(Theme.f(.title3)).foregroundStyle(m.id == selected ? Theme.gold : Theme.sub)
                                Text(m.name).foregroundStyle(.white)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        Button { store.playFile(m.part) } label: {
                            Image(systemName: store.isPlaying(file: m.part) ? "stop.circle.fill" : "play.circle.fill")
                                .font(Theme.f(.title2)).foregroundStyle(Theme.gold)
                        }
                        .accessibilityLabel(L(store.isPlaying(file: m.part) ? "إيقاف" : "تشغيل"))
                        .buttonStyle(.borderless)
                    }
                }
            } footer: {
                Text(fajr ? "أذان الفجر بصيغته الخاصة: «الصلاة خير من النوم»." : "يُستخدم في جزء الأذان والأذان الكامل لكل الصلوات عدا الفجر، فلها اختيار مستقل.")
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(fajr ? L("أذان الفجر") : L("المؤذن"))
        .navigationBarTitleDisplayMode(.large)
        .onDisappear { store.stopPlaying() }
    }
}
