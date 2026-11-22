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
    /// إعداد «الأرقام الإنجليزية» يُراقَب هنا: تتبدّل أرقام العدّادات والمنتقيات فورًا لا بعد إعادة التشغيل
    @AppStorage("western_digits", store: AppGroup.defaults) private var westernDigits = false
    init() {
        // اختبار الواجهة: قناة مضافة تجريبية (نسخة من رابط قناة القرآن)
        if ProcessInfo.processInfo.arguments.contains("-seedTV"), TVChannels.custom.isEmpty,
           let q = TVChannels.all.first(where: { $0.name == "قناة القرآن الكريم" }) {
            TVChannels.addCustom([TVChannel(id: "custom.test", name: "تجربة مضافة", cat: q.cat,
                                            urls: [q.urls[0] + (q.urls[0].contains("?") ? "&" : "?") + "t=1"],
                                            logo: q.logo, source: "قائمة تجربة")])
            if !TVChannels.favorites.contains("custom.test") { TVChannels.toggle("custom.test") }
        }
        // الخامة «تلقائي» هي الأساس (مرة واحدة، ولا تغيّر لونًا اختاره المستخدم)
        Tint.migrateToAuto()
        // أوامر ويدجت الوسائط وشاشة القفل تُنفَّذ هنا حتى لو فُتح التطبيق في الخلفية
        AudioPlayer.shared.configure()
        // إشعارات الصلاة وأزرارها
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
                .environment(\.locale, Locale(identifier: Lang.isEN ? "en_US" : (westernDigits ? "ar@numbers=latn" : "ar@numbers=arab")))
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
        // لقطة حديثة فقط (آخر ساعة): مع «وصول محدود للصور» قد لا تظهر اللقطة الجديدة فتُستخدم لقطة قديمة بالخطأ
        o.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0 AND creationDate > %@",
                                  Int(PHAssetMediaSubtype.photoScreenshot.rawValue), Date().addingTimeInterval(-3600) as NSDate)
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
                              "settings": 3, "appicon": 3, "settings2": 3, "settings3": 3, "cities": 3, "style": 3, "media": 4, "media2": 4, "media3": 4, "media4": 4, "media5": 4,
                              "files": 5, "filesdl": 5, "filesweb": 5, "filesset": 5, "filesstore": 5, "fileswifi": 5, "scanner": 5, "filesact": 5, "filestools": 5][SHOT] ?? 0
    @ObservedObject private var tvRouter = TVRouter.shared
    @ObservedObject private var filesRouter = FilesRouter.shared
    @ObservedObject private var sepTest = SepTestResult.shared
    @Environment(\.scenePhase) private var phase
    /// رابط تنزيل وصل من خارج التطبيق وينتظر موافقة المستخدم
    @State private var pendingLink: String?
    @State private var linkError = false
    var body: some View {
        if SHOT.hasPrefix("notify") {
            NavigationStack { NotifyCenterView() }
        } else if SHOT.hasPrefix("lockpad") {
            // لقطات مراجعة تصميم قفل المشغّل (فوق مشهد فيديو تجريبي)
            ZStack {
                LinearGradient(colors: [Color(red: 0.10, green: 0.16, blue: 0.24), Color(red: 0.32, green: 0.22, blue: 0.14)],
                               startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                PasscodePad(purpose: SHOT == "lockpad2" ? .create(lockAfter: true) : .unlock) { _ in }
            }
        } else {
            tabs
        }
    }

    /// زر في مركز التحكم طلب فتح صفحة (الماسح أو القبلة) — خلال آخر دقيقة فقط
    private func openPendingTarget() {
        let d = AppGroup.defaults
        guard let t = d.string(forKey: "open_target"), Date().timeIntervalSince1970 - d.double(forKey: "open_target_at") < 60 else { return }
        d.removeObject(forKey: "open_target")
        route(t)
    }

    /// فتح صفحة من ويدجت أو زر: miqat://open/<الهدف> أو من «open_target»
    private func route(_ t: String) {
        // مشغّل مقفل (قفل الأطفال): لا يغلقه زر ويدجت ولا مركز التحكم
        guard !PlayerLockState.active else { return }
        Self.dismissPresented()
        func scanner(_ m: ScanMode?) {
            tab = 5; filesRouter.path = []; filesRouter.page = .files
            filesRouter.scanMode = m; filesRouter.openScanner = true
        }
        switch t {
        case "scanner": scanner(nil)
        case "qr": scanner(.qr)
        case "idcard": scanner(.idCard)
        case "qibla": tab = 0; HomeRouter.shared.open = .qibla
        case "files": tab = 5; filesRouter.path = []; filesRouter.page = .files
        case "storage": tab = 5; filesRouter.path = []; filesRouter.page = .files; filesRouter.openStorage = true
        default:
            // file:<المسار النسبي داخل ملفاتي>
            if t.hasPrefix("file:") {
                let rel = String(t.dropFirst(5)).removingPercentEncoding ?? String(t.dropFirst(5))
                let u = FileStore.shared.root.appendingPathComponent(rel)
                // لا يُقبل مسار يخرج من مجلد الملفات (الويدجت لا تعرض ما في الخزنة أصلًا)
                guard FileStore.isInside(u, FileStore.shared.root) else { return }
                tab = 5; filesRouter.path = []; filesRouter.page = .files; filesRouter.openFile = u
            }
        }
    }

    /// يحفظ ملفًا مُرسلًا من تطبيق آخر في «الواردة» ويرجع المجلد
    @MainActor @discardableResult
    static func saveIncoming(_ url: URL) -> URL {
        let inbox = FileStore.shared.root.appendingPathComponent(L("الواردة"), isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let dest = FileStore.shared.unique(FileStore.shared.sanitize(url.lastPathComponent), in: inbox)
        // النسخ في الخلفية: فيديو كبير أو ملف من iCloud لم يُنزَّل بعد لا يجمّد الواجهة (يظهر في «الواردة» حين يكتمل)
        Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var ok = false
            var err: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &err) { src in
                let fm = FileManager.default
                ok = (try? fm.copyItem(at: src, to: dest)) != nil
                // لا نكتب فوق ملف موجود أبدًا
                if !ok, !fm.fileExists(atPath: dest.path) { ok = FileStore.streamCopy(src, to: dest) }
            }
            // نسخة النظام في Inbox لم تعد لازمة — تُحذف فقط بعد نجاح الحفظ (وإلا تبقى ولا يضيع الملف)
            if ok, url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
            await MainActor.run { FileStore.shared.touch() }
        }
        return inbox
    }

    /// يغلق ما فوق الشاشة الرئيسية (sheet أو شاشة كاملة) قبل التنقل من رابط أو ويدجت
    @MainActor static func dismissPresented() {
        let root = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
        guard let root, root.presentedViewController != nil else { return }
        root.dismiss(animated: false)
    }

    static var statusBarHeight: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // شريط الحالة من المشهد نفسه (يتوفر حتى قبل أن تصبح النافذة رئيسية)، وأقلّه ٥٤ في أجهزة الجزيرة
        let bar = scenes.compactMap { $0.statusBarManager?.statusBarFrame.height }.max() ?? 0
        let safe = scenes.flatMap(\.windows).map(\.safeAreaInsets.top).max() ?? 0
        // قبل جاهزية النافذة تكون القيمتان صفرًا: ٥٤ مؤقتًا. أما الجوال ذو الزر (SE: ٢٠) فلا يُفرض عليه ظل أعلى من شريطه فيغطي العناوين
        let v = max(bar, safe)
        return v > 0 ? v : 54
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
            VStack(spacing: 8) {
                // مشغّل واحد عائم فوق شريط التبويب في كل الصفحات
                GlobalMiniPlayer().padding(.horizontal, 12)
                FloatingTabBar(tab: $tab, items: items)
            }
                .padding(.bottom, 2)
                .ignoresSafeArea(.keyboard)
        }
        // تظليل خفيف تحت شريط الحالة: المحتوى المُمرَّر لا يتداخل مع الساعة والبطارية
        .overlay(alignment: .top) {
            // ارتفاع شريط الحالة من النافذة نفسها: داخل منطقة تتجاهل الحواف الآمنة يكون صفرًا،
            // فكان التظليل ١٨ نقطة فقط ويظهر المحتوى المُمرَّر خلف الساعة
            // تظليل متدرّج على طريقة النظام: تمويه + لون داكن ثابت حتى أسفل الساعة، ثم يتلاشى
            // ينتهي التظليل بعد حافة شريط الحالة بقليل: عنوان الصفحة في وضعه الطبيعي يبقى ساطعًا (كان يبهت تحته)
            let h = Self.statusBarHeight, total = h + 10, solid = max(0, h - 10) / total
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: solid),
                                                 .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                LinearGradient(stops: [.init(color: Color(red: 0.03, green: 0.04, blue: 0.07).opacity(0.97), location: 0),
                                       .init(color: Color(red: 0.03, green: 0.04, blue: 0.07).opacity(0.9), location: solid),
                                       .init(color: Color(red: 0.03, green: 0.04, blue: 0.07).opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
                .frame(height: total)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .tint(Theme.gold)
        .onOpenURL { url in
            // مشغّل مقفل: الملف المُرسل يُحفظ بصمت، وأي رابط آخر لا يغلق المشغّل
            if PlayerLockState.active {
                if url.isFileURL { Self.saveIncoming(url) }
                return
            }
            // أي نافذة مفتوحة (صفحة ويدجت، إعدادات…) تُغلق أولًا: الوجهة لا تُفتح مخفية تحتها
            Self.dismissPresented()
            // ملف مُرسل من تطبيق آخر («مشاركة» ← رفيقي أو «فتح باستخدام»): يُحفظ في «الواردة»
            if url.isFileURL {
                let inbox = Self.saveIncoming(url)
                FilesRouter.shared.page = .files
                FilesRouter.shared.path = [inbox]
                tab = 5
                return
            }
            // miqat://edit/<kind> — الضغط على ويدجت يفتح صفحة تصميمها
            if url.host == "media" { tab = 4; return }
            // miqat://open/<الهدف> — أزرار ويدجت الأدوات (الماسح، القبلة، الملفات، المساحة)
            if url.host == "open" {
                let t = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
                if !t.isEmpty { route(t) }
                return
            }
            // miqat://download?url=… (من الاختصارات أو أي تطبيق): يُسأل المستخدم أولًا،
            // لأن أي موقع أو تطبيق يستطيع فتح هذا الرابط
            if url.host == "download", let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value {
                pendingLink = link
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
        .alert(L("تنزيل من رابط خارجي؟"), isPresented: Binding(get: { pendingLink != nil }, set: { if !$0 { pendingLink = nil } })) {
            Button(L("تنزيل")) {
                let ok = pendingLink.map { DownloadManager.shared.add($0) } ?? false
                pendingLink = nil
                if ok {
                    FilesRouter.shared.page = .downloads
                    tab = 5
                } else {
                    linkError = true
                }
            }
            Button(L("إلغاء"), role: .cancel) { pendingLink = nil }
        } message: {
            Text(verbatim: (URL(string: pendingLink ?? "")?.host).map { LF("طلب تطبيق أو موقع تنزيل ملف من %@", $0) } ?? (pendingLink ?? ""))
        }
        .alert(L("الرابط غير صالح للتنزيل."), isPresented: $linkError) { Button(L("حسنًا"), role: .cancel) {} }
        // تغيّر توقيت الجوال (سفر) أو تعديل الوقت: الويدجت تُعاد حسابها فورًا بدل انتظار تحديثها التالي
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            // النظام يخزّن منطقته الزمنية؛ نمسحها حتى يقرأ التطبيق المنطقة الجديدة فورًا
            NSTimeZone.resetSystemTimeZone()
            reloadWidgets()
            // نصوص التنبيهات وأوقاتها تُعاد بتوقيت المكان الجديد
            if Notify.enabled { Task { await Notify.reschedule() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in reloadWidgets() }
        // طلب فتح صفحة وصل والتطبيق نشط أصلًا
        .onReceive(NotificationCenter.default.publisher(for: .rafiqiOpenTarget).receive(on: DispatchQueue.main)) { _ in
            if phase == .active { openPendingTarget() }
        }
        .onChange(of: phase) { _, p in
            // لقطة «آخر الملفات» و«المساحة» لويدجت الأدوات
            if p == .background { FilesWidgetSnapshot.write() }
            // غطاء الخصوصية: الملفات المقفلة لا تظهر في مبدّل التطبيقات
            if p != .active, tab == 5, FilePrefs.lockTab || !FileStore.shared.unlocked.isEmpty { PrivacyCover.show() }
            if p == .active { PrivacyCover.hide() }
            guard p == .active else { return }
            tvRouter.checkPending()
            openPendingTarget()
            Task { await PrayerActivity.refreshIfEnabled() }
        }
        .task {
            TVBridge.open = { id in TVRouter.shared.show(id: id) }
            // ترويسات القنوات المضافة (توكنات) تنتقل من الإعدادات إلى سلسلة المفاتيح — مرة واحدة وبأمان
            TVChannels.migrateSecrets()
            // إعادة ربط التنزيلات الجارية بالخلفية
            _ = DownloadManager.shared
            // وضع الفحص فقط: نغمة ٩٠ ثانية في «إدارة الملفات» وتُفتح عليها أداة «تقسيم المقطع»
            if ProcessInfo.processInfo.arguments.contains("-splitTest") {
                let u = FileStore.shared.root.appendingPathComponent("اختبار التقسيم.m4a")
                Task.detached {
                    try? FileManager.default.removeItem(at: u)
                    let rate = 44_100.0, frames = AVAudioFrameCount(rate * 90)
                    if let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
                       let file = try? AVAudioFile(forWriting: u, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1]),
                       let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames), let p = buf.floatChannelData?[0] {
                        buf.frameLength = frames
                        for i in 0..<Int(frames) { p[i] = 0.2 * sinf(2 * .pi * 440 * Float(i) / Float(rate)) }
                        try? file.write(from: buf)
                    }
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await MainActor.run { FileStore.shared.touch(); ToolRunner.run(.split, on: u, toast: { _ in }) }
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-sepTest") {
                Task.detached {
                    let r = await Separator.selfTest()
                    NSLog("%@", r)
                    // نتيجة اختبار الفصل (وضع الفحص فقط): تنبيه نظامي يقرؤه الفحص الآلي بثبات
                    await MainActor.run {
                        SepTestResult.shared.text = r
                        let a = UIAlertController(title: r, message: nil, preferredStyle: .alert)
                        a.addAction(UIAlertAction(title: "OK", style: .default))
                        FileOpener.top()?.present(a, animated: true)
                    }
                }
            }
            tvRouter.checkPending()
            // تشغيل بارد من زر مركز التحكم (القبلة/الماسح): قد لا يمر التطبيق بتغيّر إلى «نشط»
            openPendingTarget()
            Backdrop.ensureCrops()
            // إذن الإشعارات: يُطلب عند أول تشغيل (التنبيهات مفعّلة افتراضيًا فلم يكن يُطلب أبدًا)
            if SHOT.isEmpty, Notify.enabled { await Notify.askIfNeeded() }
            // أصوات التنبيهات في مجلد مشترك: حين تُعيد الويدجت الجدولة (التطبيق مغلق) يبقى صوت المؤذن لا النغمة العادية
            await Task.detached(priority: .utility) { Notify.shareSounds() }.value
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
    @State private var showIcons = SHOT == "appicon"
    @State private var iconPreview = AppIcons.currentPreview
    @State private var mode = Settings.mode
    @State private var place = Settings.placeName
    @State private var medina = Settings.isMedina
    @State private var hasBG = Backdrop.hasWallpaper
    @State private var use24 = Settings.use24h
    @State private var offset = Settings.hijriOffset
    @State private var shami = Settings.shamiMonths
    @State private var western = Settings.westernDigits
    @State private var lockFont = Styles.lockFont
    @State private var liveCountdown = PrayerActivity.enabled
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
                generalSection
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
            .navigationDestination(isPresented: $showIcons) { AppIconPicker() }
            .navigationDestination(isPresented: $showCities) {
                CityPicker { c in
                    Settings.setCity(name: c.name, lat: c.lat, lng: c.lng, tz: c.tz)
                    reloadWidgets(); medina = Settings.isMedina; place = c.name
                    // تنبيهات الصلاة بأوقات المدينة الجديدة فورًا
                    Task { await Notify.reschedule() }
                }
            }
          }
            .hiddenNavBar()
            .onAppear { hasBG = Backdrop.hasWallpaper; place = Settings.placeName; iconPreview = AppIcons.currentPreview }
            .onReceive(loc.objectWillChange) { _ in DispatchQueue.main.async { medina = Settings.isMedina; place = Settings.placeName } }
        }
    }

    // ── الأقسام ──

    var header: some View {
        Section {
            HStack(spacing: 14) {
                // شعار رفيقي ثابت هنا (الأيقونة الأصلية) مهما تغيّرت أيقونة الشاشة الرئيسية
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

    /// الإشعارات وأيقونة التطبيق في قسم واحد (القبلة والتقويم في أعلى الرئيسية)
    var generalSection: some View {
        Section {
            Button { showNotify = true } label: {
                HStack {
                    TileRow(title: "الإشعارات", icon: "bell.badge.fill", color: .red,
                            subtitle: "تنبيهات الصلاة وأصواتها")
                    RowChevron()
                }
            }
            .buttonStyle(.plain)
            Button { showIcons = true } label: {
                HStack {
                    TileRow(title: "أيقونة التطبيق", icon: "apps.iphone", color: .blue,
                            subtitle: "غيّر شكل رفيقي على الشاشة الرئيسية")
                    Image(iconPreview).resizable().scaledToFit().frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    RowChevron()
                }
            }
            .buttonStyle(.plain)
            // عدّاد الصلاة القادمة في الجزيرة الديناميكية وشاشة القفل (Live Activity)
            Toggle(isOn: Binding(get: { liveCountdown }, set: { v in
                liveCountdown = v; PrayerActivity.enabled = v
                Task { if v { await PrayerActivity.start() } else { await PrayerActivity.stop() } }
            })) {
                TileRow(title: "عدّاد الصلاة في شاشة القفل والجزيرة الديناميكية", icon: "timer", color: Theme.gold,
                        subtitle: "على شاشة القفل أيضًا؛ يُحدَّث كلما فتحت رفيقي")
            }
            .tint(Theme.gold)
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
                TileRow(title: "نظام ٢٤ ساعة", icon: "clock.fill", color: .indigo,
                        subtitle: LF("مثال: %@", use24 ? ar("17:30") : ar("5:30") + (Lang.isEN ? " PM" : " م")))
            }
            .tint(Theme.gold)
            Stepper(value: Binding(get: { offset }, set: { v in
                offset = v; Settings.hijriOffset = v; reloadWidgets()
                Task { await Notify.reschedule() }
            }), in: -2...2) {
                TileRow(title: "تعديل التاريخ الهجري", icon: "moon.fill", color: .teal,
                        subtitle: hijriToday + offsetText)
            }
            // بالإنجليزية الأشهر والأرقام إنجليزية دائمًا: الخياران بلا أثر فلا يُعرضان
            if !Lang.isEN {
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
            }
        } header: {
            Text("التاريخ والوقت").id("date")
        } footer: {
            Text("التقويم الهجري وفق أم القرى. عدّل التاريخ إن اختلف عن رؤية الهلال في بلدك.")
        }
    }

    var offsetText: String {
        if offset == 0 { return "" }
        // «+يوم واحد» / «−يومان»
        let sign = offset > 0 ? "+" : "−"
        return "  (" + sign + daysText(abs(offset)) + ")"
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
            Text("لتغيير لغة التطبيق، افتح «الإعدادات» في الجوال ← «رفيقي» ← «اللغة المفضلة» (تظهر إذا أضفت أكثر من لغة للجوال).")
        }
        // الإصدار ظاهر في بطاقة رفيقي أعلى الصفحة
        Section("حول التطبيق") {
            NavigationLink { FontsAbout() } label: {
                TileRow(title: "الخطوط", icon: "textformat", color: .brown, subtitle: LF("%@ خطوط عربية مجانية", ar(WFont.allCases.count)))
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
            Text(verbatim: mode == "auto"
                 ? L("تُحسب أوقات الصلاة والطقس من موقعك الفعلي، وتُحدَّث عند انتقالك إلى مدينة أخرى. يتطلّب ذلك السماح بالموقع «أثناء استخدام التطبيق أو الأدوات».")
                 : LF("%@ مدينة وقرية في جميع مناطق المملكة، ويمكنك البحث عن أي مدينة في العالم. تُعرض الأوقات بتوقيت جوالك.", ar(4581)))
        }
    }
}

// MARK: - طريقة حساب أوقات الصلاة

/// سهم الصف مثل صفوف التنقّل (للصفوف التي تفتح صفحتها بزر)
struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(uiColor: .tertiaryLabel))
            .accessibilityHidden(true)
    }
}

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
        .navigationBarTitleDisplayMode(.large)
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
        .navigationBarTitleDisplayMode(.large)
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
            msg = LF("تم ضبط %@.", placesText(found.count))
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
                        if let img { use(img) } else { msg = "لم نجد لقطة شاشة حديثة. التقط لقطة جديدة، وتأكّد من السماح بالوصول إلى كل الصور (أو اخترها من «الصور»)."; busy = false }
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
                    "التقط صورة للشاشة بالضغط على الزر الجانبي وزر رفع الصوت معًا (أو الزر الجانبي وزر الشاشة الرئيسية في الأجهزة ذات الزر).",
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
