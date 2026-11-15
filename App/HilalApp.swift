import SwiftUI
import PhotosUI
import Photos
import WidgetKit
import CoreLocation
import AVFoundation
import UserNotifications

@main
struct HilalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    init() {
        // اختبار الواجهة: قناة مضافة تجريبية (نسخة من رابط قناة القرآن)
        if ProcessInfo.processInfo.arguments.contains("-seedTV"), TVChannels.custom.isEmpty,
           let q = TVChannels.all.first(where: { $0.name == "قناة القرآن الكريم" }) {
            TVChannels.addCustom([TVChannel(id: "custom.test", name: "تجربة مضافة", cat: q.cat,
                                            urls: [q.urls[0] + (q.urls[0].contains("?") ? "&" : "?") + "t=1"],
                                            logo: q.logo, source: "قائمة تجربة")])
            if !TVChannels.favorites.contains("custom.test") { TVChannels.toggle("custom.test") }
        }
        // أوامر ويدجت الوسائط وشاشة القفل تُنفَّذ هنا حتى لو فُتح التطبيق في الخلفية
        AudioPlayer.shared.configure()
        // المتابعة المباشرة للمباريات (تبدأ من الويدجت حتى والتطبيق في الخلفية)
        UNUserNotificationCenter.current().delegate = NotifDelegate.shared
        NotifDelegate.registerCategories()
        // الأذان كاملًا كمنبّه (iOS 26.1+)
        if AdhanAlarms.supported { Notify.alarmBridge = { await AdhanAlarms.sync($0) } }
        // شريط التبويب الافتراضي مخفي (نستخدم الشريط العائم)
        UITabBar.appearance().isHidden = true
        Self.styleBars()
    }

    /// عناوين الصفحات الداخلية بخط التطبيق (تجوّل) بدل خط النظام، وشريط زجاجي موحّد
    private static func styleBars() {
        guard !Lang.isEN, let title = UIFont(name: "Tajawal-Bold", size: 18), let large = UIFont(name: "Tajawal-Bold", size: 32) else { return }
        let a = UINavigationBarAppearance()
        a.configureWithTransparentBackground()
        a.titleTextAttributes = [.font: title, .foregroundColor: UIColor.white]
        a.largeTitleTextAttributes = [.font: large, .foregroundColor: UIColor.white]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        scrolled.titleTextAttributes = a.titleTextAttributes
        scrolled.largeTitleTextAttributes = a.largeTitleTextAttributes
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = scrolled
        bar.compactAppearance = scrolled
        bar.scrollEdgeAppearance = a
        // أزرار الشريط والتبويبات المقسّمة وخانات البحث بخط التطبيق نفسه
        let regular = UIFont(name: "Tajawal-Medium", size: 16) ?? title
        let barButton = UIBarButtonItem.appearance()
        for st: UIControl.State in [.normal, .highlighted, .disabled] {
            barButton.setTitleTextAttributes([.font: regular], for: st)
        }
        let seg = UISegmentedControl.appearance()
        seg.setTitleTextAttributes([.font: UIFont(name: "Tajawal-Medium", size: 14) ?? regular], for: .normal)
        seg.setTitleTextAttributes([.font: UIFont(name: "Tajawal-Bold", size: 14) ?? regular], for: .selected)
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).font = UIFont(name: "Tajawal-Regular", size: 16)
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .font(Theme.f(.body))
                .environment(\.layoutDirection, Lang.dir)
                .digitsLocale()
                .preferredColorScheme(.dark)
        }
    }
}

func reloadWidgets() { WidgetCenter.shared.reloadAllTimelines() }

// MARK: - الموقع

final class Locator: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let m = CLLocationManager()
    @Published var status: CLAuthorizationStatus = .notDetermined
    @Published var busy = false
    override init() { super.init(); m.delegate = self; status = m.authorizationStatus }
    func ask() { m.requestWhenInUseAuthorization() }
    var allowed: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if allowed && Settings.isAuto { sync() }
    }
    func sync() {
        busy = true
        Task {
            await LocationSync.refreshIfNeeded(force: true)
            await MainActor.run { busy = false; reloadWidgets(); objectWillChange.send() }
        }
    }
}

// MARK: - آخر لقطة شاشة

enum LatestShot {
    static func load() async -> UIImage? {
        let st = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard st == .authorized || st == .limited else { return nil }
        let o = PHFetchOptions()
        o.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", Int(PHAssetMediaSubtype.photoScreenshot.rawValue))
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: .image, options: o).firstObject else { return nil }
        let ro = PHImageRequestOptions()
        ro.isNetworkAccessAllowed = true; ro.version = .current; ro.deliveryMode = .highQualityFormat
        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: ro) { data, _, _, _ in
                cont.resume(returning: data.flatMap { UIImage(data: $0) })
            }
        }
    }
}

// MARK: - الشاشة الرئيسية: معرض الويدجتات + الإعدادات

/// وضع التصوير للمراجعة: ‎-shot home | gallery | detail | settings | render
let SHOT = UserDefaults.standard.string(forKey: "shot") ?? ""
let SHOT_FILTER = UserDefaults.standard.string(forKey: "filter") ?? "الكل"
let SHOT_WIDGET = SHOT == "detail" ? (UserDefaults.standard.string(forKey: "wid") ?? "") : ""

/// نتيجة اختبار الفصل الذاتي (تظهر نصًا ليقرأها الفحص الآلي)
@MainActor final class SepTestResult: ObservableObject { static let shared = SepTestResult(); @Published var text = "" }

struct ContentView: View {
    @State private var tab = ["home": 0, "gallery": 1, "detail": 1, "notify": 2, "notifyd": 2,
                              "settings": 3, "settings2": 3, "settings3": 3, "cities": 3, "style": 3, "media": 4, "media2": 4, "media3": 4, "media4": 4, "media5": 4,
                              "files": 5, "filesdl": 5, "filesweb": 5, "filesset": 5, "filesstore": 5, "fileswifi": 5, "scanner": 5, "filesact": 5, "filestools": 5][SHOT] ?? 0
    @ObservedObject private var tvRouter = TVRouter.shared
    @ObservedObject private var filesRouter = FilesRouter.shared
    @ObservedObject private var sepTest = SepTestResult.shared
    @Environment(\.scenePhase) private var phase
    var body: some View {
        if SHOT.hasPrefix("notify") {
            NavigationStack { NotifyCenterView() }
        } else {
            tabs
        }
    }

    static var statusBarHeight: CGFloat {
        let w = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        return w?.safeAreaInsets.top ?? 59
    }

    private let items = [TabItem(tag: 0, title: "الرئيسية", icon: "moon.stars.fill"),
                         TabItem(tag: 1, title: "الويدجت", icon: "square.grid.2x2.fill"),
                         TabItem(tag: 4, title: "المسموع والمرئي", icon: "play.rectangle.fill"),
                         TabItem(tag: 5, title: "إدارة الملفات", icon: "folder.fill"),
                         TabItem(tag: 3, title: "الإعدادات", icon: "gearshape.fill")]

    var tabs: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                HomeView(openGallery: { tab = 1 }, openTab: { tab = $0 })
                    .toolbar(.hidden, for: .tabBar).tag(0)
                GalleryView()
                    .toolbar(.hidden, for: .tabBar).tag(1)
                MediaView()
                    .toolbar(.hidden, for: .tabBar).tag(4)
                FilesTab()
                    .toolbar(.hidden, for: .tabBar).tag(5)
                SettingsView()
                    .toolbar(.hidden, for: .tabBar).tag(3)
            }
            FloatingTabBar(tab: $tab, items: items)
                .padding(.bottom, 2)
                .ignoresSafeArea(.keyboard)
        }
        // تظليل خفيف تحت شريط الحالة: المحتوى المُمرَّر لا يتداخل مع الساعة والبطارية
        .overlay(alignment: .top) {
            // ارتفاع شريط الحالة من النافذة نفسها: داخل منطقة تتجاهل الحواف الآمنة يكون صفرًا،
            // فكان التظليل ١٨ نقطة فقط ويظهر المحتوى المُمرَّر خلف الساعة
            LinearGradient(stops: [.init(color: Color.black.opacity(0.92), location: 0),
                                   .init(color: Color.black.opacity(0.75), location: 0.6),
                                   .init(color: Color.black.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: Self.statusBarHeight + 18)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .center) {
            if !sepTest.text.isEmpty { Text(verbatim: sepTest.text).font(.caption).padding(8).background(Color.black).accessibilityElement(children: .ignore).accessibilityLabel(sepTest.text).accessibilityIdentifier("septest").accessibilityAddTraits(.isStaticText) }
        }
        .tint(Theme.gold)
        .onOpenURL { url in
            // ملف مُرسل من تطبيق آخر («مشاركة» ← رفيقي أو «فتح باستخدام»): يُحفظ في «الواردة»
            if url.isFileURL {
                let inbox = FileStore.shared.root.appendingPathComponent(L("الواردة"), isDirectory: true)
                try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
                FileStore.shared.importFiles([url], to: inbox)
                // نسخة النظام في Inbox لم تعد لازمة
                if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
                FilesRouter.shared.page = .files
                FilesRouter.shared.path = [inbox]
                tab = 5
                return
            }
            // miqat://edit/<kind> — الضغط على ويدجت يفتح صفحة تصميمها
            if url.host == "media" { tab = 4; return }
            // miqat://download?url=… (من الاختصارات أو أي تطبيق): يُضاف للتنزيلات
            if url.host == "download", let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value {
                DownloadManager.shared.add(link)
                FilesRouter.shared.page = .downloads
                tab = 5
                return
            }
            // miqat://tv/<القناة>
            if url.host == "tv" {
                tab = 4
                if let id = url.pathComponents.last, id != "/" { tvRouter.show(id: id) }
                return
            }
            if url.host == "edit", let id = url.pathComponents.last, id != "/" {
                tab = 1
                GalleryNav.shared.open = id
            }
        }
        .onChange(of: filesRouter.openTab) { _, on in if on { tab = 5; filesRouter.openTab = false } }
        .onChange(of: phase) { _, p in
            if p == .active { tvRouter.checkPending() }
        }
        .task {
            TVBridge.open = { id in TVRouter.shared.show(id: id) }
            // إعادة ربط التنزيلات الجارية بالخلفية
            _ = DownloadManager.shared
            if ProcessInfo.processInfo.arguments.contains("-sepTest") {
                Task.detached {
                    let r = await Separator.selfTest()
                    NSLog("%@", r)
                    await MainActor.run { SepTestResult.shared.text = r }
                }
            }
            tvRouter.checkPending()
            Backdrop.ensureCrops()
            // إذن الإشعارات: يُطلب عند أول تشغيل (التنبيهات مفعّلة افتراضيًا فلم يكن يُطلب أبدًا)
            if SHOT.isEmpty, Notify.enabled { await Notify.askIfNeeded() }
            await Notify.reschedule()
            guard !SHOT.isEmpty else { return }
            Backdrop.screenPt = CGSize(width: 440, height: 956)
            if Backdrop.hasWallpaper { Backdrop.regenerate() }
            if SHOT == "render" { GalleryShots.render(weather: await Weather.load()) }
            if SHOT == "matrix" { GalleryShots.matrix(weather: await Weather.load()) }
        }
    }
}

/// قائمة خطوات مرقّمة
struct StepsList: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                HStack(alignment: .top, spacing: 10) {
                    Text(ar(i + 1)).font(Theme.f(.caption, .bold)).foregroundStyle(.black)
                        .frame(width: 20, height: 20).background(Circle().fill(Theme.gold))
                    Text(L(t)).font(Theme.f(.footnote)).foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SettingsView: View {
    @State private var showCities = SHOT == "cities"
    @State private var showStyle = SHOT == "style"
    @State private var showNotify = false
    @State private var mode = Settings.mode
    @State private var place = Settings.placeName
    @State private var medina = Settings.isMedina
    @State private var hasBG = Backdrop.hasWallpaper
    @State private var use24 = Settings.use24h
    @State private var offset = Settings.hijriOffset
    @State private var shami = Settings.shamiMonths
    @State private var western = Settings.westernDigits
    @State private var lockFont = Styles.lockFont
    @State private var fahr = Settings.fahrenheit
    @State private var windMS = Settings.windMS
    @State private var methodID = Settings.methodID
    @StateObject private var loc = Locator()

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return ar(v) + " (" + ar(b) + ")"
    }

    var body: some View {
        NavigationStack {
          ScrollViewReader { proxy in
            List {
                Section { PageHeader(title: "الإعدادات") }
                    .bareRow(top: 0, bottom: 0)
                header
                toolsSection
                notifySection
                prayerSection
                widgetSection
                dateSection
                weatherSection
                locationSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .barSpace()
            .onAppear {
                if SHOT == "settings2" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo("loc", anchor: .top) } }
                if SHOT == "settings3" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo("date", anchor: .top) } }
            }
            .navigationDestination(isPresented: $showStyle) { GlobalStyleView() }
            .navigationDestination(isPresented: $showNotify) { NotifyCenterView() }
            .navigationDestination(isPresented: $showCities) {
                CityPicker { c in
                    Settings.setCity(name: c.name, lat: c.lat, lng: c.lng, tz: c.tz)
                    reloadWidgets(); medina = Settings.isMedina; place = c.name
                    // تنبيهات الصلاة بأوقات المدينة الجديدة فورًا
                    Task { await Notify.reschedule() }
                }
            }
          }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { hasBG = Backdrop.hasWallpaper; place = Settings.placeName }
            .onReceive(loc.objectWillChange) { _ in DispatchQueue.main.async { medina = Settings.isMedina; place = Settings.placeName } }
        }
    }

    // ── الأقسام ──

    var header: some View {
        Section {
            HStack(spacing: 14) {
                Image("AppIconPreview").resizable().scaledToFit().frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                VStack(alignment: .leading, spacing: 3) {
                    Text("رفيقي").font(Theme.title(21)).foregroundStyle(.white)
                    Text("رفيقك اليومي: الصلاة والتاريخ والقرآن والوسائط").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                    Text(L("الإصدار") + " " + version).font(Theme.f(.caption2)).foregroundStyle(Theme.sub.opacity(0.8))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    var toolsSection: some View {
        Section {
            NavigationLink { QiblaView() } label: {
                TileRow(title: "القبلة", icon: "location.north.line.fill", color: Color(red: 0.20, green: 0.70, blue: 0.55),
                        subtitle: "بوصلة باتجاه الكعبة المشرفة من موقعك")
            }
            NavigationLink { UmmAlQuraView() } label: {
                TileRow(title: "تقويم أم القرى", icon: "calendar", color: .orange,
                        subtitle: "التقويم الرسمي والمناسبات ومحوّل التاريخ")
            }
        } header: { Text("الأدوات") }
    }

    var notifySection: some View {
        Section {
            Button { showNotify = true } label: {
                TileRow(title: "الإشعارات", icon: "bell.badge.fill", color: .red,
                        subtitle: "تنبيهات الصلاة وأصواتها")
            }
            .buttonStyle(.plain)
        }
    }

    var prayerSection: some View {
        Section {
            NavigationLink {
                MethodPicker(selected: Binding(get: { methodID }, set: { v in
                    methodID = v; Settings.methodID = v; reloadWidgets()
                    Task { await Notify.reschedule() }
                }))
            } label: {
                TileRow(title: "طريقة حساب الأوقات", icon: "function", color: Color(red: 0.16, green: 0.55, blue: 0.42),
                        subtitle: CalcMethods.get(methodID).name)
            }
        } header: {
            Text("أوقات الصلاة")
        } footer: {
            Text("الافتراضي أم القرى، وهو المعتمد في المملكة. غيّره إن كان مسجدك يؤذّن بطريقة أخرى.")
        }
    }

    var widgetSection: some View {
        Section {
            NavigationLink { GlobalStyleView() } label: {
                TileRow(title: "التصميم العام", icon: "paintbrush.pointed.fill", color: .pink,
                        subtitle: "الخلفية والخط والزخرفة ولون الخط")
            }
            NavigationLink { WallpaperSettings() } label: {
                HStack {
                    TileRow(title: "الخلفية الشفافة", icon: "photo.fill", color: Theme.goldDeep,
                            subtitle: "مطابقة الويدجت مع خلفية شاشتك")
                    Text(hasBG ? "مضبوطة" : "غير مضبوطة").font(Theme.f(.caption)).foregroundStyle(hasBG ? .green : .orange)
                }
            }
            Picker(selection: Binding(get: { lockFont }, set: { lockFont = $0; Styles.lockFont = $0; reloadWidgets() })) {
                ForEach(WFont.allCases) { f in Text(f.title).tag(f) }
            } label: {
                TileRow(title: "خط ويدجت شاشة القفل", icon: "lock.fill", color: .indigo)
            }
        } header: { Text("الويدجت") }
    }

    var dateSection: some View {
        Section {
            Toggle(isOn: Binding(get: { use24 }, set: { use24 = $0; Settings.use24h = $0; reloadWidgets() })) {
                TileRow(title: "نظام ٢٤ ساعة", icon: "clock.fill", color: .indigo, subtitle: use24 ? "مثال: ١٧:٣٠" : "مثال: ٥:٣٠")
            }
            .tint(Theme.gold)
            Stepper(value: Binding(get: { offset }, set: { v in
                offset = v; Settings.hijriOffset = v; reloadWidgets()
                Task { await Notify.reschedule() }
            }), in: -2...2) {
                TileRow(title: "تعديل التاريخ الهجري", icon: "moon.fill", color: .teal,
                        subtitle: hijriToday + offsetText)
            }
            Toggle(isOn: Binding(get: { shami }, set: { shami = $0; Settings.shamiMonths = $0; reloadWidgets() })) {
                TileRow(title: "أسماء الأشهر الشامية", icon: "calendar", color: .orange,
                        subtitle: shami ? "كانون الثاني، شباط، آذار…" : "يناير، فبراير، مارس…")
            }
            .tint(Theme.gold)
            Toggle(isOn: Binding(get: { western }, set: { western = $0; Settings.westernDigits = $0; reloadWidgets() })) {
                TileRow(title: "الأرقام الإنجليزية", icon: "textformat.123", color: .mint,
                        subtitle: western ? "123 بدلًا من ١٢٣" : "١٢٣ (الأرقام العربية)")
            }
            .tint(Theme.gold)
        } header: {
            Text("التاريخ والوقت").id("date")
        } footer: {
            Text("التقويم الهجري وفق أم القرى. عدّل التاريخ إن اختلف عن رؤية الهلال في بلدك.")
        }
    }

    var offsetText: String {
        if offset == 0 { return "" }
        let sign = offset > 0 ? "+" : "−"
        let unit = L(abs(offset) == 1 ? "يوم" : "يومان")
        return "  (" + sign + ar(abs(offset)) + " " + unit + ")"
    }

    var hijriToday: String {
        let h = Cal.dmy(Date(), greg: false)
        let m = max(0, min(11, h.m - 1))
        let month = Lang.isEN ? Words.hmEN[m] : Words.hm[m]
        let era = Lang.isEN ? " AH" : " هـ"
        return ar(h.d) + " " + month + " " + ar(h.y) + era
    }

    var weatherSection: some View {
        Section("الطقس") {
            Picker(selection: Binding(get: { fahr }, set: { fahr = $0; Settings.fahrenheit = $0; reloadWidgets() })) {
                Text("مئوية °م").tag(false)
                Text("فهرنهايت °ف").tag(true)
            } label: { TileRow(title: "درجة الحرارة", icon: "thermometer.medium", color: .red) }
            Picker(selection: Binding(get: { windMS }, set: { windMS = $0; Settings.windMS = $0; reloadWidgets() })) {
                Text("كم/س").tag(false)
                Text("م/ث").tag(true)
            } label: { TileRow(title: "سرعة الرياح", icon: "wind", color: .cyan) }
        }
    }

    @ViewBuilder var aboutSection: some View {
        Section {
            Button {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            } label: {
                HStack {
                    TileRow(title: "اللغة", icon: "globe", color: .blue)
                    Text(Lang.isEN ? "English" : "العربية").foregroundStyle(Theme.sub)
                }
            }
        } footer: {
            Text("لتغيير لغة التطبيق إلى الإنجليزية أو العكس، افتح «الإعدادات» في الجوال ← «رفيقي» ← «اللغة».")
        }
        Section("حول التطبيق") {
            NavigationLink { FontsAbout() } label: {
                TileRow(title: "الخطوط", icon: "textformat", color: .brown, subtitle: LF("%@ خطوط عربية مجانية", ar(WFont.allCases.count)))
            }
            HStack {
                TileRow(title: "الإصدار", icon: "info.circle.fill", color: .gray)
                Text(version).foregroundStyle(Theme.sub)
            }
        }
    }

    var locationSection: some View {
        Section {
            Picker("طريقة تحديد الموقع", selection: Binding(get: { mode }, set: { v in
                // الإحداثيات الحالية جاءت من الموقع التلقائي: منطقتها الزمنية هي منطقة الجوال
                if v == "city" && Settings.isAuto { Settings.placeTZ = TimeZone.current.identifier }
                mode = v; Settings.mode = v
                if v == "auto" { if loc.allowed { loc.sync() } else { loc.ask() } }
                else { reloadWidgets() }
                Task { await Notify.reschedule() }
            })) {
                Text("تلقائي").tag("auto")
                Text("مدينة محددة").tag("city")
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))

            if mode == "auto" {
                HStack {
                    TileRow(title: Settings.placeName.isEmpty ? "جارٍ تحديد الموقع…" : Settings.placeName, icon: "location.fill",
                            color: .blue, subtitle: "يُحدَّث تلقائيًا عند تغيّر موقعك")
                    if loc.busy { ProgressView() }
                }
                Button { if loc.allowed { loc.sync() } else { loc.ask() } } label: {
                    TileRow(title: "تحديث الموقع", icon: "arrow.clockwise", color: .teal)
                }
                if loc.status == .denied || loc.status == .restricted {
                    Button {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    } label: {
                        TileRow(title: "الوصول إلى الموقع غير مسموح", icon: "exclamationmark.triangle.fill", color: .red,
                                subtitle: "افتح الإعدادات واختر «أثناء استخدام التطبيق أو الأدوات»")
                    }
                }
            } else {
                NavigationLink {
                    CityPicker { c in
                        Settings.setCity(name: c.name, lat: c.lat, lng: c.lng, tz: c.tz)
                        reloadWidgets(); medina = Settings.isMedina; place = c.name
                        Task { await Notify.reschedule() }
                    }
                } label: {
                    TileRow(title: "المدينة", icon: "building.2.fill", color: .orange, subtitle: place)
                }
            }
        } header: {
            Text("الموقع").id("loc")
        } footer: {
            Text(mode == "auto"
                 ? "تُحسب أوقات الصلاة والطقس من موقعك الفعلي، وتُحدَّث عند انتقالك إلى مدينة أخرى. يتطلّب ذلك السماح بالموقع «أثناء استخدام التطبيق أو الأدوات»."
                 : "٤٥٨١ مدينة وقرية في جميع مناطق المملكة، ويمكنك البحث عن أي مدينة في العالم. تُعرض الأوقات بتوقيت جوالك.")
        }
    }
}

// MARK: - طريقة حساب أوقات الصلاة

struct MethodPicker: View {
    @Binding var selected: String
    @State private var cur: String? = nil   // نسخة محلية تُحدّث العلامة فورًا
    var body: some View {
        let now = cur ?? selected
        List {
            Section {
                ForEach(CalcMethods.all) { m in
                    Button { cur = m.id; selected = m.id } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.name).foregroundStyle(.white)
                                Text(verbatim: m.detail).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: m.id == now ? "checkmark.circle.fill" : "circle")
                                .font(Theme.f(.title3)).foregroundStyle(m.id == now ? Theme.gold : Theme.sub)
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityAddTraits(m.id == now ? .isSelected : [])
                }
            } footer: {
                Text("العصر لجميع الطرق على قول الجمهور (ظل الشيء مثله). في البلاد البعيدة شمالًا، إذا لم تبلغ الشمس زاوية الفجر أو العشاء صيفًا، يُحسب الوقت بجزء من الليل.")
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .navigationTitle("طريقة الحساب")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - الخلفية الشفافة ومطابقة المواضع

struct WallpaperSettings: View {
    @State private var pick: PhotosPickerItem?
    @State private var msg = ""
    @State private var busy = false
    @State private var hasBG = Backdrop.hasWallpaper
    @State private var calibrated = Backdrop.calibratedFrames.count
    @State private var unmatched = Backdrop.unmatchedSlots
    @State private var calibOn = Backdrop.calibrating(at: Date())

    var screenPx: CGSize {
        let b = UIScreen.main.nativeBounds.size
        return CGSize(width: min(b.width, b.height), height: max(b.width, b.height))
    }
    var screenPt: CGSize {
        let b = UIScreen.main.bounds.size
        return CGSize(width: min(b.width, b.height), height: max(b.width, b.height))
    }

    var body: some View {
        List {
            backgroundSection
            if calibOn || !unmatched.isEmpty || calibrated == 0 { placesSection }
            if calibOn == false && calibrated > 0 && unmatched.isEmpty {
                Section { placesButton } footer: { Text("أعِد الضبط إذا غيّرت حجم الأيقونات أو نقلت إحدى الويدجت.") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .navigationTitle("الخلفية الشفافة")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in refresh() }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            busy = true
            Task {
                let img = (try? await item.loadTransferable(type: Data.self)).flatMap { UIImage(data: $0) }
                await MainActor.run { pick = nil; if let img { use(img) } else { msg = "تعذّر فتح الصورة."; busy = false } }
            }
        }
    }

    func refresh() {
        Backdrop.screenPt = screenPt
        hasBG = Backdrop.hasWallpaper
        calibrated = Backdrop.calibratedFrames.count
        unmatched = Backdrop.unmatchedSlots
        calibOn = Backdrop.calibrating(at: Date())
    }

    /// صورة وحدة تكفي: إذا فيها مربعات المعايرة الملوّنة تضبط الأماكن، وإلا تصير هي الخلفية
    func use(_ img: UIImage) {
        let w = img.size.width * img.scale, h = img.size.height * img.scale
        let isShot = abs(w - screenPx.width) < 2 && abs(h - screenPx.height) < 2
        let found = isShot ? Backdrop.detect(in: img, screenPt: screenPt) : []
        if !found.isEmpty {
            Backdrop.merge(found)
            Backdrop.calibUntil = .distantPast
            if Backdrop.hasWallpaper { Backdrop.regenerate() }
            msg = (found.count == 1 ? L("تم ضبط موضع واحد.") : LF("تم ضبط %@ مواضع.", ar(found.count)))
                + (Backdrop.hasWallpaper ? "" : " " + L("الخطوة التالية: التقط صورة لصفحة فارغة لضبط الخلفية."))
        } else if Backdrop.setWallpaper(img, screenPx: screenPx) {
            msg = isShot ? "تم ضبط الخلفية." : "تم اعتماد الصورة خلفيةً. إن لم تتطابق تمامًا، فاستخدم لقطة شاشة."
        } else {
            msg = "تعذّر حفظ الخلفية. حاول مرة أخرى."
        }
        reloadWidgets(); refresh(); busy = false
    }

    var backgroundSection: some View {
        Section {
            Button {
                busy = true
                Task {
                    let img = await LatestShot.load()
                    await MainActor.run {
                        if let img { use(img) } else { msg = "تعذّر العثور على لقطة شاشة. تأكّد من السماح بالوصول إلى الصور."; busy = false }
                    }
                }
            } label: {
                HStack {
                    TileRow(title: "استخدام آخر لقطة شاشة", icon: "camera.viewfinder", color: Theme.goldDeep,
                            subtitle: "يتعرّف تلقائيًا على صورة الخلفية أو صورة الضبط")
                    if busy { Spacer(); ProgressView() }
                }
            }
            .disabled(busy)
            PhotosPicker(selection: $pick, matching: .images) {
                TileRow(title: "اختيار من الصور", icon: "photo.on.rectangle", color: .teal,
                        subtitle: "لقطة شاشة أو صورة الخلفية الأصلية")
            }
            if hasBG {
                Button(role: .destructive) {
                    Backdrop.clearWallpaper(); reloadWidgets(); refresh(); msg = "أُزيلت الخلفية."
                } label: { TileRow(title: "إزالة الخلفية", icon: "trash.fill", color: .red) }
            }
            if !msg.isEmpty {
                Label(L(msg), systemImage: "info.circle").font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
            }
            DisclosureGroup {
                StepsList(items: [
                    "اضغط مطوّلًا على الشاشة الرئيسية حتى تهتز الأيقونات.",
                    "مرّر إلى آخر صفحة حتى تظهر صفحة فارغة.",
                    "التقط صورة للشاشة بالضغط على الزر الجانبي وزر رفع الصوت معًا.",
                    "عُد إلى التطبيق واختر «استخدام آخر لقطة شاشة».",
                ])
            } label: {
                Text("طريقة التقاط صورة الخلفية").font(Theme.f(.subheadline)).foregroundStyle(Theme.gold)
            }
        } header: {
            HStack {
                Text("خلفية الويدجت")
                if hasBG { Spacer(); Text("مضبوطة").foregroundStyle(.green) }
            }
        } footer: {
            Text("لتغيير الخلفية، كرّر الخطوات نفسها بعد تغيير خلفية الجوال.")
        }
    }

    var placesButton: some View {
        Button {
            Backdrop.calibUntil = Date().addingTimeInterval(600); reloadWidgets(); refresh()
        } label: {
            TileRow(title: "ضبط المواضع", icon: "viewfinder", color: .purple,
                    subtitle: unmatched.isEmpty ? "مطابقة دقيقة لكل حجم من أحجام الأيقونات" : "تغيّر حجم الأيقونات، ويُنصح بإعادة الضبط")
        }
    }

    var placesSection: some View {
        Section {
            if calibOn {
                VStack(alignment: .leading, spacing: 10) {
                    Label("وضع الضبط مفعّل لمدة عشر دقائق", systemImage: "viewfinder.circle.fill")
                        .font(Theme.f(.subheadline, .semibold)).foregroundStyle(.purple)
                    StepsList(items: [
                        "انتقل إلى صفحة الويدجت في الشاشة الرئيسية.",
                        "التقط صورة للشاشة.",
                        "عُد إلى التطبيق واختر «استخدام آخر لقطة شاشة».",
                    ])
                }
                .padding(.vertical, 4)
                Button("إلغاء الضبط", role: .cancel) { Backdrop.calibUntil = .distantPast; reloadWidgets(); refresh() }
            } else {
                placesButton
            }
        } header: { Text("مطابقة المواضع") }
          footer: { Text("قبل الضبط، حدّد موضع كل ويدجت من «تعديل الأداة» ثم «المكان».") }
    }
}
