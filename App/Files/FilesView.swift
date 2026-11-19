import SwiftUI
import PhotosUI
import QuickLookThumbnailing
import AVFoundation
import UniformTypeIdentifiers
import VisionKit
import PDFKit

// MARK: - تبويب «إدارة الملفات»

enum FilesPage: String, CaseIterable, Identifiable {
    case files, downloads, browser
    var id: String { rawValue }
    var title: String {
        switch self {
        case .files: return L("ملفاتي")
        case .downloads: return L("التنزيلات")
        case .browser: return L("المتصفح")
        }
    }
}

/// يفتح التبويب على صفحة معيّنة (من الاستيراد أو الرابط)
@MainActor
final class FilesRouter: ObservableObject {
    static let shared = FilesRouter()
    @Published var page: FilesPage = SHOT == "filesdl" ? .downloads : SHOT == "filesweb" ? .browser : .files
    @Published var path: [URL] = []
    /// طلب التبديل إلى تبويب «إدارة الملفات»
    @Published var openTab = false
    /// طلب فتح الماسح (من زر مركز التحكم)
    @Published var openScanner = false
    /// وضع الماسح المطلوب (QR أو الهوية) من ويدجت الأدوات
    var scanMode: ScanMode? = nil
    /// طلب فتح «تحليل المساحة» أو ملف معيّن من ويدجت الملفات — يُنفّذ بعد فتح القفل فقط
    @Published var openStorage = false
    @Published var openFile: URL? = nil
    func takeScanMode() -> ScanMode { defer { scanMode = nil }; return scanMode ?? .document }
}

struct FilesTab: View {
    @ObservedObject private var store = FileStore.shared
    @ObservedObject private var router = FilesRouter.shared
    @Environment(\.scenePhase) private var phase
    @State private var locked = FilePrefs.lockTab
    @State private var showSettings = SHOT == "filesset"
    @State private var showWiFi = SHOT == "fileswifi"
    @State private var showStorage = SHOT == "filesstore"

    var body: some View {
        Group {
            // القفل فوق كل شيء: لا تُبنى صفحات المجلدات أصلًا قبل التحقق، مهما كان طريق الوصول (مشاركة ملف، رابط، ويدجت)
            if locked {
                lockScreen.background(AppBackground())
            } else {
                NavigationStack(path: $router.path) {
                    home
                        .background(AppBackground())
                        .hiddenNavBar()
                        .navigationDestination(for: URL.self) { dir in FolderScreen(dir: dir) }
                }
            }
        }
        .sheet(isPresented: $showSettings) { FilesSettingsView() }
        .sheet(isPresented: $showWiFi) { WiFiTransferView() }
        .sheet(isPresented: $showStorage) { StorageView() }
        .onChange(of: router.openStorage, initial: true) { _, _ in runPending() }
        .onChange(of: router.openFile, initial: true) { _, _ in runPending() }
        .onChange(of: locked) { _, _ in runPending() }
        .onChange(of: phase) { _, p in
            if p == .background {
                let hadUnlocked = !store.unlocked.isEmpty
                store.relockAll()
                if FilePrefs.lockTab { locked = true }
                // المجلدات المفتوحة فوق الجذر تُغلق أيضًا: لا يبقى محتوى مقفل ظاهرًا عند الرجوع للتطبيق
                if FilePrefs.lockTab || router.path.contains(where: { store.inVault($0) || store.insideLocked($0) }) {
                    router.path = []
                }
                // وما كان معروضًا فوق التبويب (معاينة ملف، أداة، تحليل المساحة…) يُغلق كذلك
                if FilePrefs.lockTab || hadUnlocked {
                    showSettings = false; showWiFi = false; showStorage = false
                    FileOpener.closeForLock(all: FilePrefs.lockTab)
                }
            }
        }
        .onAppear { store.purgeOldTrash() }
    }

    private var home: some View {
        VStack(spacing: 12) {
            PageHeader(title: "إدارة الملفات", subtitle: L("ملفاتك وتنزيلاتك في مكان واحد")) {
                // أدوات قليلة الاستخدام في قائمة واحدة بدل ثلاث دوائر
                Menu {
                    Button { showWiFi = true } label: { Label("النقل عبر الواي فاي", systemImage: "wifi") }
                    Button { showStorage = true } label: { Label("تحليل المساحة", systemImage: "chart.pie") }
                    Button { showSettings = true } label: { Label("إعدادات الملفات", systemImage: "gearshape") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Circle().fill(Theme.cardHi))
                        .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                }
                .accessibilityLabel(L("أدوات الملفات"))
            }
            .padding(.horizontal, 16)
            Picker("", selection: $router.page) {
                ForEach(FilesPage.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            switch router.page {
            case .files:
                ScrollView { FolderContent(dir: store.root, isRoot: true).padding(.horizontal, 16).padding(.bottom, 12) }
                    .scrollIndicators(.hidden)
                    .safeAreaInset(edge: .bottom, spacing: 0) { bottomStack }
            case .downloads:
                ScrollView {
                    DownloadsView { url in
                        FileOpener.open(url, siblings: FileStore.shared.list(url.deletingLastPathComponent()).filter { !$0.isDir }.map(\.url))
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomStack }
            case .browser:
                BrowserView()
                    .safeAreaInset(edge: .bottom, spacing: 0) { BarSpacer() }
            }
        }
    }

    private var bottomStack: some View {
        BarSpacer()
    }

    /// طلبات ويدجت الملفات: لا تتجاوز قفل «إدارة الملفات» أبدًا
    private func runPending() {
        guard !locked else { return }
        if router.openStorage { router.openStorage = false; showStorage = true }
        if let u = router.openFile {
            router.openFile = nil
            guard FileManager.default.fileExists(atPath: u.path) else { return }
            let open = { FileOpener.open(u, siblings: FileStore.shared.list(u.deletingLastPathComponent()).filter { !$0.isDir }.map(\.url)) }
            // ملف داخل مجلد مقفل (من تذكير أو رابط): يُطلب التحقق أولًا لكل مجلد مقفل في طريقه
            if let l = store.lockedAncestor(u.deletingLastPathComponent()) {
                Task {
                    guard await FileStore.authenticate(L("افتح المجلد المقفل")) else { return }
                    var cur: URL? = l
                    while let c = cur { store.unlocked.insert(store.key(c)); cur = store.lockedAncestor(u.deletingLastPathComponent()) }
                    open()
                }
            } else {
                open()
            }
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            Badge(name: "lock.fill", size: 72, active: true)
            Text("إدارة الملفات مقفلة").font(Theme.f(.title3, .bold)).foregroundStyle(.white)
            if !FileStore.canProtect { noPasscodeNote }
            Button {
                Task { if await FileStore.authenticate(L("افتح إدارة الملفات")) { locked = false } }
            } label: {
                Label("فتح", systemImage: Biometry.icon).font(Theme.f(.headline))
                    .foregroundStyle(.black).padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Capsule().fill(Theme.gold))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .task { if await FileStore.authenticate(L("افتح إدارة الملفات")) { locked = false } }
    }
}

/// مجلد فرعي
struct FolderScreen: View {
    let dir: URL
    @ObservedObject private var store = FileStore.shared
    /// أول مجلد مقفل في المسار لم يُفتح بعد
    private var lockedPart: URL? { store.lockedAncestor(dir) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                BackRow()
                PageHeader(title: store.displayName(dir), subtitle: lockedPart != nil ? nil : (store.count(dir) == 0 ? L("فارغ") : itemsText(store.count(dir))))
                // لا يُعرض محتوى مجلد مقفل (أو داخل مجلد مقفل) قبل التحقق، مهما كان طريق الوصول إليه
                if let l = lockedPart {
                    VStack(spacing: 14) {
                        Badge(name: "lock.fill", size: 64, active: true)
                        Text("المجلد مقفل").font(Theme.f(.headline)).foregroundStyle(.white)
                        if !FileStore.canProtect { noPasscodeNote }
                        Button {
                            Task { _ = await store.unlock(l) }
                        } label: {
                            Label("فتح", systemImage: Biometry.icon).font(Theme.f(.headline))
                                .foregroundStyle(.black).padding(.horizontal, 28).padding(.vertical, 12)
                                .background(Capsule().fill(Theme.gold))
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                    .task { _ = await store.unlock(l) }
                } else {
                    FolderContent(dir: dir, isRoot: false)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BarSpacer()
        }
        .background(AppBackground())
        .hiddenNavBar()
    }
}

/// يظهر إن أُزيل رمز قفل الجوال بعد قفل المحتوى: لا يُفتح المقفل إلا بالتحقق
var noPasscodeNote: some View {
    Text("لفتح المحتوى المقفل اضبط رمز قفل للجوال من الإعدادات أولًا.")
        .font(Theme.f(.footnote)).foregroundStyle(Theme.sub).multilineTextAlignment(.center).padding(.horizontal, 30)
}

// MARK: - محتوى المجلد

struct FolderContent: View {
    let dir: URL
    let isRoot: Bool
    @ObservedObject private var store = FileStore.shared
    @ObservedObject private var router = FilesRouter.shared
    @State private var query = ""
    @State private var filter: FileKind? = nil
    @State private var sort = FilePrefs.sort
    @State private var ascending = FilePrefs.ascending
    @State private var grid = FilePrefs.grid
    @State private var selecting = false
    @State private var selection: Set<URL> = []
    @State private var actionItem: FileItem?
    @State private var renaming: FileItem?
    @State private var newName = ""
    @State private var askNewFolder = false
    @State private var askNewNote = false
    @State private var moving: [URL]? = nil
    @State private var copying: [URL]? = nil
    @State private var importingFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var showScannerHome = SHOT == "scanner"
    @State private var addingToPlaylist: [URL]? = nil
    @State private var reminding: FileItem?
    @State private var toast: String?
    @State private var busy = false
    @State private var confirmDelete: [URL]? = nil
    @State private var reordering = false

    private var isTrash: Bool { store.isTrash(dir) }
    /// كل ملفات «ملفاتي» للبحث والتصنيفات (من الخلفية)
    @State private var deepCache: [FileItem]? = nil
    private var needsDeep: Bool { isRoot && (!query.trimmingCharacters(in: .whitespaces).isEmpty || (filter != nil && filter != .folder)) }

    private var items: [FileItem] {
        _ = store.rev
        var a: [FileItem]
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty || (filter != nil && filter != .folder && isRoot) {
            // البحث والتصنيفات في الجذر تشمل كل المجلدات (تُقرأ في الخلفية مرة لكل تغيير، لا مع كل حرف)
            a = isRoot ? (deepCache ?? []) : store.list(dir)
            a = a.filter { !store.isTrash($0.url) }
        } else {
            a = store.list(dir)
        }
        if !q.isEmpty { a = a.filter { $0.name.localizedCaseInsensitiveContains(q) } }
        if let filter { a = a.filter { $0.kind == filter } }
        return store.sorted(a, in: dir, by: sort, ascending: ascending)
    }

    var body: some View {
        let list = items
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                searchBar
                if !isTrash { actionsRow }
            }
            filterBar
            if isTrash && !list.isEmpty {
                HStack {
                    Text("تُحذف الملفات نهائيًا بعد ٣٠ يومًا من نقلها إلى السلة.").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                    Spacer()
                    Button(L("إفراغ السلة"), role: .destructive) { confirmDelete = list.map(\.url) }
                        .font(Theme.f(.subheadline, .bold)).foregroundStyle(.red)
                }
            }
            if list.isEmpty {
                empty
            } else if reordering {
                reorderList(list)
            } else if grid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 14)], spacing: 18) {
                    ForEach(list) { it in cell(it, list) }
                }
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(list) { it in cell(it, list) }
                }
            }
            if isRoot && query.isEmpty && filter == nil {
                NavigationLink { PlaylistsView() } label: { navRow("music.note.list", L("قوائم التشغيل"), itemsText(FilePlaylists.shared.all.count)) }
                    .buttonStyle(.plain)
                NavigationLink { ServersView() } label: { navRow("server.rack", L("الخوادم والمجلدات المشاركة"), L("كمبيوتر، جهاز تخزين، WebDAV")) }
                    .buttonStyle(.plain)
                trashRow
            }
            if selecting { Color.clear.frame(height: 70) }
        }
        .overlay(alignment: .bottom) { if selecting { selectionBar.offset(y: 0) } }
        .overlay(alignment: .top) { toastView }
        .task(id: needsDeep ? store.rev : -1) {
            guard needsDeep else { deepCache = nil; return }
            let d = dir
            deepCache = await Task.detached(priority: .userInitiated) { FileStore.deepListSync(d) }.value
        }
        .task {
            // لقطات المراجعة: قائمة إجراءات ملف صوتي، وأدوات ملف فيديو/صوت
            guard isRoot, SHOT == "filesact" || SHOT == "filestools" else { return }
            try? await Task.sleep(for: .seconds(1.2))
            let all = store.deepList(dir).filter { !$0.isDir }
            actionItem = all.first { $0.kind == .audio } ?? all.first
        }
        .sheet(item: $actionItem) { it in
            FileActionsSheet(item: it, inTrash: isTrash) { action in handle(action, it) }
                .presentationDetents(SHOT == "filestools" ? [.large] : [.medium, .large])
        }
        .sheet(isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } })) {
            FolderPicker(title: L("نقل إلى")) { dest in
                let n = store.move(moving ?? [], to: dest)
                show(n > 0 ? LF("نُقل %@", itemsText(n)) : L("لم يُنقل شيء"))
                moving = nil; endSelection()
            }
        }
        .sheet(isPresented: Binding(get: { copying != nil }, set: { if !$0 { copying = nil } })) {
            FolderPicker(title: L("نسخ إلى")) { dest in
                let n = store.copy(copying ?? [], to: dest).count
                show(n > 0 ? LF("نُسخ %@", itemsText(n)) : L("لم يُنسخ شيء"))
                copying = nil; endSelection()
            }
        }
        .alert(L("إعادة التسمية"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("الاسم"), text: $newName)
            Button(L("حفظ")) { if let r = renaming { store.rename(r.url, to: newName) }; renaming = nil }
            Button(L("إلغاء"), role: .cancel) { renaming = nil }
        }
        .alert(L("مجلد جديد"), isPresented: $askNewFolder) {
            TextField(L("اسم المجلد"), text: $newName)
            Button(L("إنشاء")) { store.createFolder(newName, in: dir) }
            Button(L("إلغاء"), role: .cancel) {}
        }
        .alert(L("ملاحظة نصية جديدة"), isPresented: $askNewNote) {
            TextField(L("اسم الملاحظة"), text: $newName)
            Button(L("إنشاء")) { if let u = store.createText(newName, in: dir) { FileOpener.open(u) } }
            Button(L("إلغاء"), role: .cancel) {}
        }
        .confirmationDialog(L("حذف نهائي؟"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button(L("حذف نهائي"), role: .destructive) { store.deleteForever(confirmDelete ?? []); confirmDelete = nil; endSelection() }
        } message: {
            Text("لا يمكن استرجاع الملفات بعد الحذف النهائي.")
        }
        .fileImporter(isPresented: $importingFiles, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r {
                let n = store.importFiles(urls, to: dir).count
                show(n > 0 ? LF("استُورد %@", itemsText(n)) : L("لم يُستورد شيء"))
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 50, matching: .any(of: [.images, .videos]))
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items); photoItems = [] }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { url in
                if let url { _ = store.importFiles([url], to: dir, move: true); show(L("حُفظ في ملفاتي")) }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(get: { addingToPlaylist != nil }, set: { if !$0 { addingToPlaylist = nil } })) {
            AddToPlaylistSheet(urls: addingToPlaylist ?? [])
        }
        .sheet(item: $reminding) { it in ReminderSheet(item: it) { msg in show(msg) } }
        .fullScreenCover(isPresented: $showScannerHome) { ScannerHome() }
        .onChange(of: router.openScanner, initial: true) { _, on in
            guard on, isRoot else { return }
            router.openScanner = false
            // أُغلق الماسح للتو من رابط (مركز التحكم) وحالته باقية: نصفّرها ثم نفتحه من جديد
            if showScannerHome {
                showScannerHome = false
                DispatchQueue.main.async { showScannerHome = true }
            } else {
                showScannerHome = true
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocScanner { pdf in
                if let pdf, let u = store.importData(pdf, name: L("مستند ممسوح") + ".pdf", to: dir) { show(LF("حُفظ «%@»", u.lastPathComponent)) }
                showScanner = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: sort) { _, v in FilePrefs.sort = v }
        .onChange(of: ascending) { _, v in FilePrefs.ascending = v }
        .onChange(of: grid) { _, v in FilePrefs.grid = v }
    }

    // MARK: الأجزاء

    /// بجانب البحث: الماسح، وقائمة «+» (إنشاء واستيراد)، والتحديد — بدل بطاقة من خمسة أزرار كبيرة
    private var actionsRow: some View {
        HStack(spacing: 8) {
            circle("doc.viewfinder", L("الماسح")) { showScannerHome = true }
            Menu {
                Section {
                    Button { newName = ""; askNewFolder = true } label: { Label("مجلد جديد", systemImage: "folder.badge.plus") }
                    Button { newName = ""; askNewNote = true } label: { Label("ملاحظة نصية", systemImage: "note.text.badge.plus") }
                }
                Section {
                    Button { showPhotos = true } label: { Label("استيراد من الصور", systemImage: "photo.on.rectangle") }
                    Button { importingFiles = true } label: { Label("استيراد من الملفات", systemImage: "folder.badge.plus") }
                    Button { showCamera = UIImagePickerController.isSourceTypeAvailable(.camera); if !showCamera { show(L("الكاميرا غير متاحة")) } } label: {
                        Label("التقاط صورة أو فيديو", systemImage: "camera")
                    }
                    if VNDocumentCameraViewController.isSupported {
                        Button { showScanner = true } label: { Label("مسح سريع إلى PDF", systemImage: "doc.viewfinder") }
                    }
                }
            } label: {
                Image(systemName: "plus").font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 44, height: 44).background(Circle().fill(Theme.gold))
            }
            .accessibilityLabel(L("إنشاء"))
            circle(selecting ? "xmark" : "checkmark.circle", selecting ? L("إلغاء") : L("تحديد")) {
                if selecting { endSelection() } else { selecting = true }
            }
        }
    }

    private func circle(_ icon: String, _ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(Circle().fill(Theme.cardHi))
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.sub)
            TextField(isRoot ? L("ابحث في كل ملفاتك") : L("ابحث في هذا المجلد"), text: $query)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.sub) }
            }
            sortMenu
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
    }

    private var sortMenu: some View {
        Menu {
            Section(L("الترتيب حسب")) {
                ForEach(FileSort.allCases) { s in
                    Button { sort = s; reordering = false } label: {
                        if sort == s { Label(s.title, systemImage: "checkmark") } else { Text(s.title) }
                    }
                }
            }
            if sort != .manual {
                Button { ascending.toggle() } label: {
                    Label(ascending ? L("تصاعدي") : L("تنازلي"), systemImage: ascending ? "arrow.up" : "arrow.down")
                }
            } else {
                Button { reordering.toggle() } label: { Label(reordering ? L("إنهاء الترتيب") : L("ترتيب يدوي بالسحب"), systemImage: "arrow.up.arrow.down") }
            }
            Section(L("العرض")) {
                Button { grid = true } label: { Label("شبكة", systemImage: grid ? "checkmark" : "square.grid.2x2") }
                Button { grid = false } label: { Label("قائمة", systemImage: !grid ? "checkmark" : "list.bullet") }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 20)).foregroundStyle(Theme.gold)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(L("الكل"), nil)
                ForEach([FileKind.folder, .image, .video, .audio, .document, .archive], id: \.self) { k in chip(k.title, k) }
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(_ title: String, _ k: FileKind?) -> some View {
        let on = filter == k
        return Button { withAnimation(.snappy) { filter = k } } label: {
            Text(verbatim: title).font(Theme.f(.subheadline, on ? .bold : .medium))
                .foregroundStyle(on ? Color.black : .white.opacity(0.85))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(on ? Theme.gold : Theme.card))
                .overlay(Capsule().strokeBorder(on ? Color.clear : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: isTrash ? "trash" : (query.isEmpty ? "folder" : "magnifyingglass"))
                .font(.system(size: 40, weight: .light)).foregroundStyle(Theme.gold.opacity(0.8))
            Text(isTrash ? L("السلة فارغة") : (query.isEmpty ? L("لا توجد ملفات هنا") : L("لا توجد نتائج")))
                .font(Theme.f(.headline)).foregroundStyle(.white)
            if !isTrash && query.isEmpty {
                Text("استورد من الصور أو تطبيق الملفات، أو نزّل من رابط. ملفاتك تظهر أيضًا في تطبيق «الملفات» ← «على الـiPhone» ← «رفيقي».")
                    .font(Theme.f(.footnote)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 30).padding(.horizontal, 16)
        .glassCard(padding: 10)
    }

    private func navRow(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Badge(name: icon, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(Theme.f(.subheadline, .bold)).foregroundStyle(.white)
                Text(verbatim: sub).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            }
            Spacer()
            Image(systemName: "chevron.forward").font(Theme.f(.footnote, .bold)).foregroundStyle(Theme.sub)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
    }

    private var trashRow: some View {
        NavigationLink(value: store.trash) {
            HStack(spacing: 12) {
                Badge(name: "trash", size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("سلة المحذوفات").font(Theme.f(.subheadline, .bold)).foregroundStyle(.white)
                    Text(itemsText(store.count(store.trash))).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                }
                Spacer()
                Image(systemName: "chevron.forward").font(Theme.f(.footnote, .bold)).foregroundStyle(Theme.sub)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func reorderList(_ list: [FileItem]) -> some View {
        List {
            ForEach(list) { it in
                HStack(spacing: 12) {
                    FileThumb(item: it, size: 40)
                    Text(verbatim: it.name).font(Theme.f(.subheadline)).foregroundStyle(.white).lineLimit(1)
                }
                .listRowBackground(Theme.card)
            }
            .onMove { from, to in
                var names = list.map(\.name)
                names.move(fromOffsets: from, toOffset: to)
                store.setManualOrder(names, in: dir)
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .frame(height: CGFloat(list.count) * 62 + 20)
    }

    @ViewBuilder private func cell(_ it: FileItem, _ all: [FileItem]) -> some View {
        let selected = selection.contains(it.url)
        let content = Group {
            if grid { GridCell(item: it, selected: selecting ? selected : nil) { actionItem = it } }
            else { ListCell(item: it, selected: selecting ? selected : nil) { actionItem = it } }
        }
        Button {
            if selecting {
                if selected { selection.remove(it.url) } else { selection.insert(it.url) }
            } else {
                open(it, all)
            }
        } label: { content }
        .buttonStyle(PressStyle())
        .contextMenu {
            if !isTrash {
                Button { open(it, all) } label: { Label("فتح", systemImage: "arrow.up.forward.app") }
                Button { newName = it.base; renaming = it } label: { Label("إعادة التسمية", systemImage: "pencil") }
                Button { moving = [it.url] } label: { Label("نقل", systemImage: "folder") }
                Button { store.copy([it.url]) } label: { Label("إنشاء نسخة", systemImage: "plus.square.on.square") }
                Button { store.togglePin(it.url) } label: {
                    Label(store.isPinned(it.url) ? L("إلغاء التثبيت") : L("تثبيت"), systemImage: store.isPinned(it.url) ? "pin.slash" : "pin")
                }
                if !it.isDir { Button { FileOpener.share([it.url]) } label: { Label("مشاركة", systemImage: "square.and.arrow.up") } }
                Button { actionItem = it } label: { Label("كل الإجراءات…", systemImage: "ellipsis.circle") }
                Button(role: .destructive) { store.moveToTrash([it.url]) } label: { Label("حذف", systemImage: "trash") }
            } else {
                Button { store.restore([it.url]) } label: { Label("استرجاع", systemImage: "arrow.uturn.backward") }
                Button(role: .destructive) { confirmDelete = [it.url] } label: { Label("حذف نهائي", systemImage: "trash") }
            }
        }
    }

    private var selectionBar: some View {
        let urls = Array(selection)
        let none = urls.isEmpty
        return HStack(spacing: 0) {
            if isTrash {
                barButton("arrow.uturn.backward", L("استرجاع"), none) { store.restore(urls); endSelection() }
                barButton("trash", L("حذف نهائي"), none) { confirmDelete = urls }
            } else {
                barButton("folder", L("نقل"), none) { moving = urls }
                Menu {
                    Button { copying = urls } label: { Label("نسخ إلى", systemImage: "plus.square.on.square") }
                    let kinds = Set(urls.map { FileKind.of($0, isDir: store.item($0)?.isDir ?? false) })
                    if urls.count >= 2, kinds == [.video] || kinds == [.audio] {
                        Button { runMulti { try await MediaTools.merge(sortedSel(urls), progress: { _ in }) } } label: { Label("دمج بالترتيب", systemImage: "rectangle.stack.badge.plus") }
                    }
                    if kinds == [.audio] {
                        Button { AudioPlayer.shared.playFiles(sortedSel(urls), start: 0); endSelection() } label: { Label("تشغيل المحدد", systemImage: "play.fill") }
                        Button { addingToPlaylist = sortedSel(urls) } label: { Label("إضافة إلى قائمة تشغيل", systemImage: "music.note.list") }
                    }
                    if urls.count >= 2, urls.allSatisfy({ $0.pathExtension.lowercased() == "pdf" }) {
                        Button { let list = sortedSel(urls); runMulti { try await Task.detached(priority: .userInitiated) { try MediaTools.mergePDFs(list) }.value } } label: { Label("دمج ملفات PDF", systemImage: "doc.on.doc") }
                    }
                    if kinds == [.image] {
                        Button { let list = sortedSel(urls); runMulti { try await Task.detached(priority: .userInitiated) { try MediaTools.imagesToPDF(list) }.value } } label: { Label("تحويل الصور إلى PDF", systemImage: "doc.richtext") }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "ellipsis.circle").font(.system(size: 18, weight: .medium))
                        Text("المزيد").font(Theme.f(.caption2, .medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(none ? Color.white.opacity(0.3) : .white)
                }
                .disabled(none)
                barButton("square.and.arrow.up", L("مشاركة"), none) { FileOpener.share(urls.filter { !(store.item($0)?.isDir ?? true) }) }
                barButton("square.and.arrow.down", L("إلى الصور"), none) {
                    Task {
                        let n = await store.saveToPhotos(urls)
                        show(n < 0 ? L("اسمح لرفيقي بإضافة الصور من الإعدادات") : (n == 0 ? L("لم يُحفظ شيء في الصور") : LF("حُفظ %@ في الصور", itemsText(n))))
                        endSelection()
                    }
                }
                barButton("doc.zipper", L("ضغط"), none) {
                    Task { busy = true; let z = await store.zip(urls); busy = false; show(z == nil ? L("تعذّر الضغط") : L("تم الضغط")); endSelection() }
                }
                barButton("trash", L("حذف"), none) { store.moveToTrash(urls); show(LF("نُقل %@ إلى السلة", itemsText(urls.count))); endSelection() }
            }
        }
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .topLeading) {
            Text(LF("المحدد: %@", ar(selection.count))).font(Theme.f(.caption, .bold)).foregroundStyle(.black)
                .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Theme.gold)).offset(x: 12, y: -14)
        }
    }

    private func barButton(_ icon: String, _ title: String, _ disabled: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Text(verbatim: title).font(Theme.f(.caption2, .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(disabled ? Color.white.opacity(0.3) : .white)
        }
        .disabled(disabled)
    }

    @ViewBuilder private var toastView: some View {
        if busy {
            ProgressView().tint(Theme.gold).padding(14).background(Circle().fill(.ultraThinMaterial))
        } else if let t = toast {
            Text(verbatim: t).font(Theme.f(.footnote, .medium)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(.ultraThinMaterial)).environment(\.colorScheme, .dark)
                .task(id: t) { try? await Task.sleep(for: .seconds(2.5)); toast = nil }
        }
    }

    // MARK: الإجراءات

    /// المحدد بترتيب ظهوره في الصفحة
    private func sortedSel(_ urls: [URL]) -> [URL] {
        let order = items.map(\.url)
        return urls.sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
    }

    private func runMulti(_ work: @escaping () async throws -> URL) {
        Task {
            busy = true
            do { let u = try await work(); show(LF("أُنشئ «%@»", u.lastPathComponent)) }
            catch { show(error.localizedDescription) }
            busy = false
            store.touch()
            endSelection()
        }
    }

    private func show(_ s: String) { withAnimation { toast = s } }
    private func endSelection() { selecting = false; selection = [] }

    private func open(_ it: FileItem, _ all: [FileItem]) {
        if it.isDir {
            Task {
                if await store.unlock(it.url) { router.path.append(it.url) }
            }
            return
        }
        if it.kind == .archive && it.ext == "zip" {
            // فُكّ من قبل: يُفتح مجلده بدل نسخة جديدة مكررة مع كل ضغطة
            let prev = it.url.deletingPathExtension()
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: prev.path, isDirectory: &isDir), isDir.boolValue {
                router.path.append(prev)
                return
            }
            Task {
                busy = true
                let d = await store.unzip(it.url)
                busy = false
                show(d == nil ? L("تعذّر فك الضغط") : L("فُكّ الضغط في مجلد بالاسم نفسه"))
            }
            return
        }
        FileOpener.open(it.url, siblings: all.filter { !$0.isDir }.map(\.url))
    }

    private func handle(_ a: FileAction, _ it: FileItem) {
        actionItem = nil
        switch a {
        case .move: moving = [it.url]
        case .copyTo: copying = [it.url]
        case .share: FileOpener.share([it.url])
        case .rename: newName = it.base; renaming = it
        case .delete: store.moveToTrash([it.url]); show(L("نُقل إلى السلة"))
        case .openIn: FileOpener.openIn(it.url)
        case .pin: store.togglePin(it.url)
        case .duplicate: store.copy([it.url]); show(L("أُنشئت نسخة"))
        case .zip: Task { busy = true; let z = await store.zip([it.url]); busy = false; show(z == nil ? L("تعذّر الضغط") : L("تم الضغط")) }
        case .unzip: Task { busy = true; let d = await store.unzip(it.url); busy = false; show(d == nil ? L("تعذّر فك الضغط") : L("فُكّ الضغط")) }
        case .photos:
            Task {
                let n = await store.saveToPhotos([it.url])
                show(n < 0 ? L("اسمح لرفيقي بإضافة الصور من الإعدادات") : (n > 0 ? L("حُفظ في الصور") : L("هذا النوع لا يُحفظ في الصور")))
            }
        case .restore: store.restore([it.url]); show(L("استُرجع"))
        case .deleteForever: confirmDelete = [it.url]
        case .color(let c): store.setColor(it.url, c)
        case .lock(let on):
            // بلا رمز قفل للجوال لا يمكن طلب التحقق، فالقفل لن يحمي شيئًا — نخبر المستخدم بدل قفل وهمي
            if on && !FileStore.canProtect { show(Biometry.text(face: "القفل يحتاج رمز قفل للجوال. فعّله من إعدادات الجوال ← بصمة الوجه ورمز الدخول.", touch: "القفل يحتاج رمز قفل للجوال. فعّله من إعدادات الجوال ← بصمة الإصبع ورمز الدخول.")); return }
            Task {
                if await FileStore.authenticate(on ? L("قفل المجلد") : L("إلغاء قفل المجلد")) {
                    store.setLocked(it.url, on)
                    show(on ? L("قُفل المجلد") : L("أُلغي قفل المجلد"))
                }
            }
        case .open: open(it, items)
        case .playlist: addingToPlaylist = [it.url]
        case .remind: reminding = it
        case .tool(let t): ToolRunner.run(t, on: it.url) { msg in show(msg) }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        busy = true
        defer { busy = false }
        var n = 0
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd_HHmmss"
        for (i, item) in items.enumerated() {
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let isMovie = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            let base = (isMovie ? "VID_" : "IMG_") + f.string(from: Date()) + (items.count > 1 ? "_\(i + 1)" : "")
            if isMovie, let m = try? await item.loadTransferable(type: PickedMovie.self) {
                if !store.importFiles([m.url], to: dir, move: true).isEmpty { n += 1 }
            } else if let d = try? await item.loadTransferable(type: Data.self) {
                if store.importData(d, name: base + "." + ext, to: dir) != nil { n += 1 }
            }
        }
        show(n > 0 ? LF("استُورد %@", itemsText(n)) : L("لم يُستورد شيء"))
    }
}

/// «عنصر واحد، عنصران، ٥ عناصر، ١٢ عنصرًا»
func itemsText(_ n: Int) -> String {
    if n == 0 { return L("لا شيء") }
    return countText(n, one: "عنصر واحد", two: "عنصران", few: "عناصر", many: "عنصرًا", en: n == 1 ? "item" : "items")
}

struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { r in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(r.file.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: r.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

// MARK: - الخلايا

struct GridCell: View {
    let item: FileItem
    let selected: Bool?
    let more: () -> Void
    @ObservedObject private var store = FileStore.shared

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                FileThumb(item: item, size: 96)
                if store.isPinned(item.url) {
                    Image(systemName: "pin.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                        .padding(5).background(Circle().fill(Theme.gold)).offset(x: -4, y: -4)
                }
                if let selected {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22)).foregroundStyle(selected ? Theme.gold : .white)
                        .background(Circle().fill(Color.black.opacity(0.35)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(4)
                }
            }
            .frame(width: 100, height: 100)
            Text(verbatim: item.isDir ? item.name : item.base)
                .font(Theme.f(.footnote, .medium)).foregroundStyle(.white)
                .lineLimit(2).multilineTextAlignment(.center).frame(height: 36, alignment: .center)
            FileSubtitle(item: item).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            // الإجراءات بالضغط المطوّل (بدل زر «…» تحت كل ملف)
        }
    }
}

struct ListCell: View {
    let item: FileItem
    let selected: Bool?
    let more: () -> Void
    @ObservedObject private var store = FileStore.shared

    var body: some View {
        HStack(spacing: 12) {
            if let selected {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                    .foregroundStyle(selected ? Theme.gold : .white.opacity(0.6))
            }
            FileThumb(item: item, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if store.isPinned(item.url) { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Theme.gold) }
                    if item.isDir && store.isLocked(item.url) { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.gold) }
                    Text(verbatim: item.name).font(Theme.f(.subheadline, .medium)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    FileSubtitle(item: item)
                    Text(verbatim: "·")
                    Text(item.modified, format: .dateTime.day().month(.abbreviated).year())
                }
                .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 0)
            if selected == nil {
                Button(action: more) {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.gold)
                        .frame(width: 36, height: 36).background(Circle().fill(Theme.card))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

/// السطر الثاني: حجم الملف أو مدة المقطع أو عدد عناصر المجلد
struct FileSubtitle: View {
    let item: FileItem
    @State private var text = ""
    var body: some View {
        Text(verbatim: text.isEmpty ? quick : text)
            .lineLimit(1).minimumScaleFactor(0.8)
            .task(id: item.url) {
                // المجلد المقفل: لا يُكشف عدد عناصره ولا حجمها قبل التحقق
                if item.isDir && FileStore.shared.needsUnlock(item.url) { text = L("مقفل"); return }
                if item.kind == .audio || item.kind == .video {
                    let d = try? await AVURLAsset(url: item.url).load(.duration)
                    if let s = d?.seconds, s.isFinite, s > 0 { text = durationText(s) }
                } else if item.isDir {
                    // المجلد: عدد عناصره وحجمها، و«فارغ» إن لم يكن فيه شيء
                    let u = item.url
                    let n = FileStore.shared.count(u)
                    let size = await Task.detached { FileStore.folderSizeSync(u) }.value
                    text = n == 0 ? L("فارغ") : itemsText(n) + (size > 0 ? " · " + sizeText(size) : "")
                }
            }
    }
    private var quick: String {
        guard item.isDir else { return sizeText(item.size) }
        if FileStore.shared.needsUnlock(item.url) { return L("مقفل") }
        let n = FileStore.shared.count(item.url)
        return n == 0 ? L("فارغ") : itemsText(n)
    }
}

extension FileStore {
    /// حساب حجم المجلد خارج الخيط الرئيسي
    nonisolated static func folderSizeSync(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var t: Int64 = 0
        for case let u as URL in e { t += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return t
    }
}

/// صورة مصغّرة حقيقية (صورة، فيديو، PDF…) أو أيقونة النوع
struct FileThumb: View {
    let item: FileItem
    let size: CGFloat
    @State private var image: UIImage?
    @ObservedObject private var store = FileStore.shared

    var body: some View {
        ZStack {
            if item.isDir {
                folder
            } else if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if item.kind == .video {
                            Image(systemName: "play.fill").font(.system(size: size * 0.16)).foregroundStyle(.white)
                                .padding(size * 0.06).background(Circle().fill(Color.black.opacity(0.5))).padding(size * 0.06)
                        }
                    }
            } else {
                typeIcon
            }
        }
        .frame(width: size, height: size)
        .task(id: item.url) { await load() }
    }

    private var folder: some View {
        ZStack {
            Image(systemName: "folder.fill").resizable().scaledToFit()
                .foregroundStyle(LinearGradient(colors: [store.color(item.url).opacity(0.95), store.color(item.url).opacity(0.65)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.92)
            if store.isLocked(item.url) {
                Image(systemName: "lock.fill").font(.system(size: size * 0.2, weight: .bold)).foregroundStyle(.black.opacity(0.55)).offset(y: size * 0.06)
            }
        }
    }

    private var typeIcon: some View {
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .overlay {
                VStack(spacing: size * 0.04) {
                    Image(systemName: item.kind.icon).font(.system(size: size * 0.32, weight: .light)).foregroundStyle(Theme.gold)
                    if size >= 60 && !item.ext.isEmpty {
                        Text(verbatim: item.ext.uppercased()).font(.system(size: size * 0.11, weight: .bold, design: .rounded)).foregroundStyle(Theme.sub)
                    }
                }
            }
    }

    private func load() async {
        guard !item.isDir, [.image, .video, .document].contains(item.kind) else { return }
        let scale = UIScreen.main.scale
        let req = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: size, height: size), scale: scale, representationTypes: .thumbnail)
        if let r = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { image = r.uiImage }
    }
}

// MARK: - اختيار مجلد (للنقل والنسخ)

struct FolderPicker: View {
    let title: String
    let pick: (URL) -> Void
    @ObservedObject private var store = FileStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var askNew = false
    @State private var name = ""
    @State private var base: URL?

    var body: some View {
        NavigationStack {
            List {
                Button { pick(store.root); dismiss() } label: { row(L("ملفاتي"), "house", 0) }
                ForEach(tree(), id: \.0) { (u, depth) in
                    Button { pick(u); dismiss() } label: { row(FileStore.plainName(u), store.isLocked(u) ? "lock.fill" : "folder", depth) }
                        .swipeActions { Button { base = u; name = ""; askNew = true } label: { Label("مجلد داخله", systemImage: "folder.badge.plus") }.tint(Theme.goldDeep) }
                }
                .listRowBackground(Theme.card)
            }
            .glassList()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { base = store.root; name = ""; askNew = true } label: { Image(systemName: "folder.badge.plus") }
                }
            }
            .alert(L("مجلد جديد"), isPresented: $askNew) {
                TextField(L("اسم المجلد"), text: $name)
                Button(L("إنشاء")) { store.createFolder(name, in: base ?? store.root) }
                Button(L("إلغاء"), role: .cancel) {}
            }
        }
    }

    private func row(_ name: String, _ icon: String, _ depth: Int) -> some View {
        HStack(spacing: 10) {
            Badge(name: icon, size: 30)
            Text(verbatim: name).foregroundStyle(.white)
            Spacer()
        }
        .padding(.leading, CGFloat(depth) * 18)
    }

    private func tree() -> [(URL, Int)] {
        _ = store.rev
        var out: [(URL, Int)] = []
        func walk(_ d: URL, _ depth: Int) {
            guard depth < 6 else { return }
            for f in store.sorted(store.list(d).filter(\.isDir), in: d, by: .name, ascending: true) {
                out.append((f.url, depth + 1))
                // ما داخل مجلد مقفل لا يُكشف قبل التحقق (ولا حتى أسماء مجلداته)
                if !store.needsUnlock(f.url) { walk(f.url, depth + 1) }
            }
        }
        walk(store.root, 0)
        return out
    }
}

// MARK: - الكاميرا

struct CameraPicker: UIViewControllerRepresentable {
    let done: (URL?) -> Void
    func makeCoordinator() -> Coord { Coord(done: done) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        c.videoQuality = .typeHigh
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (URL?) -> Void
        init(done: @escaping (URL?) -> Void) { self.done = done }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd_HHmmss"
            let stamp = f.string(from: Date())
            if let v = info[.mediaURL] as? URL {
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("VID_\(stamp).\(v.pathExtension)")
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: v, to: dest)
                done(dest)
            } else if let img = info[.originalImage] as? UIImage, let d = img.jpegData(compressionQuality: 0.92) {
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("IMG_\(stamp).jpg")
                try? d.write(to: dest)
                done(dest)
            } else { done(nil) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}

// MARK: - مسح المستندات بالكاميرا ← PDF

struct DocScanner: UIViewControllerRepresentable {
    let done: (Data?) -> Void
    func makeCoordinator() -> Coord { Coord(done: done) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let c = VNDocumentCameraViewController()
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coord: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: (Data?) -> Void
        init(done: @escaping (Data?) -> Void) { self.done = done }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pdf = PDFDocument()
            for i in 0..<scan.pageCount {
                if let p = PDFPage(image: scan.imageOfPage(at: i)) { pdf.insert(p, at: pdf.pageCount) }
            }
            done(pdf.dataRepresentation())
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { done(nil) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { done(nil) }
    }
}
