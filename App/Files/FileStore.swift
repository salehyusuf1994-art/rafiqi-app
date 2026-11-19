import Foundation
import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication
import Photos
import ZIPFoundation

// MARK: - إدارة الملفات: التخزين
// الملفات في مجلد «المستندات» للتطبيق، فتظهر أيضًا في تطبيق «الملفات» ← «على الـiPhone» ← «رفيقي».
// سلة المحذوفات مجلد مخفي (.Trash) داخل المستندات.

enum FileKind: String, CaseIterable, Identifiable {
    case folder, image, video, audio, document, archive, other
    var id: String { rawValue }

    static func of(_ url: URL, isDir: Bool) -> FileKind {
        if isDir { return .folder }
        let ext = url.pathExtension.lowercased()
        if ["zip", "rar", "7z", "tar", "gz", "tgz"].contains(ext) { return .archive }
        if ["amr", "opus", "ogg", "oga", "flac", "wma"].contains(ext) { return .audio }
        if ["mkv", "webm", "flv", "avi", "wmv", "3gp", "ts"].contains(ext) { return .video }
        guard let t = UTType(filenameExtension: ext) else { return .other }
        if t.conforms(to: .image) { return .image }
        if t.conforms(to: .movie) || t.conforms(to: .video) || t.conforms(to: .audiovisualContent) && !t.conforms(to: .audio) { return .video }
        if t.conforms(to: .audio) { return .audio }
        if t.conforms(to: .archive) { return .archive }
        if t.conforms(to: .pdf) || t.conforms(to: .text) || t.conforms(to: .presentation) || t.conforms(to: .spreadsheet)
            || t.conforms(to: .rtf) || ["doc", "docx", "pages", "numbers", "key", "epub", "xls", "xlsx", "ppt", "pptx", "csv", "srt", "vtt"].contains(ext) {
            return .document
        }
        return .other
    }

    var title: String {
        switch self {
        case .folder: return L("مجلدات")
        case .image: return L("صور")
        case .video: return L("فيديو")
        case .audio: return L("صوت")
        case .document: return L("مستندات")
        case .archive: return L("ملفات مضغوطة")
        case .other: return L("أخرى")
        }
    }

    /// اسم مجلد الترتيب التلقائي
    var folderName: String {
        switch self {
        case .image: return L("الصور")
        case .video: return L("الفيديو")
        case .audio: return L("الصوتيات")
        case .document: return L("المستندات")
        case .archive: return L("الملفات المضغوطة")
        default: return L("أخرى")
        }
    }

    var icon: String {
        switch self {
        case .folder: return "folder.fill"
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .audio: return "waveform"
        case .document: return "doc.text"
        case .archive: return "doc.zipper"
        case .other: return "doc"
        }
    }
}

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDir: Bool
    let size: Int64
    let modified: Date
    let created: Date
    let kind: FileKind
    var id: URL { url }
    var ext: String { url.pathExtension.lowercased() }
    /// الاسم بدون الامتداد
    var base: String { isDir ? name : url.deletingPathExtension().lastPathComponent }
}

enum FileSort: String, CaseIterable, Identifiable {
    case date, name, size, type, manual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .date: return L("التاريخ")
        case .name: return L("الاسم")
        case .size: return L("الحجم")
        case .type: return L("النوع")
        case .manual: return L("يدوي")
        }
    }
}

/// إعدادات إدارة الملفات
enum FilePrefs {
    private static var d: UserDefaults { .standard }
    static var sort: FileSort {
        get { FileSort(rawValue: d.string(forKey: "files.sort") ?? "") ?? .date }
        set { d.set(newValue.rawValue, forKey: "files.sort") }
    }
    static var ascending: Bool {
        get { d.object(forKey: "files.asc") as? Bool ?? false }
        set { d.set(newValue, forKey: "files.asc") }
    }
    static var grid: Bool {
        get { d.object(forKey: "files.grid") as? Bool ?? true }
        set { d.set(newValue, forKey: "files.grid") }
    }
    /// حفظ الصور والفيديو في «الصور» بعد اكتمال التنزيل
    static var autoPhotos: Bool {
        get { d.bool(forKey: "files.autoPhotos") }
        set { d.set(newValue, forKey: "files.autoPhotos") }
    }
    /// ترتيب التنزيلات في مجلدات: ٠ بلا، ١ حسب النوع، ٢ حسب المصدر (الموقع)
    static var folderMode: Int {
        get { d.object(forKey: "files.folderMode") as? Int ?? 1 }
        set { d.set(newValue, forKey: "files.folderMode") }
    }
    /// قفل «إدارة الملفات» ببصمة الوجه أو رمز الجوال
    static var lockTab: Bool {
        get { d.bool(forKey: "files.lock") }
        set { d.set(newValue, forKey: "files.lock") }
    }
    /// مدة التقديم والترجيع في المشغّل
    static var skip: Int {
        get { d.object(forKey: "files.skip") as? Int ?? 10 }
        set { d.set(newValue, forKey: "files.skip") }
    }
    /// تشغيل الملف التالي تلقائيًا
    static var autoNext: Bool {
        get { d.object(forKey: "files.autoNext") as? Bool ?? true }
        set { d.set(newValue, forKey: "files.autoNext") }
    }
    /// مشغّل الفيديو: التشغيل العشوائي
    static var videoShuffle: Bool {
        get { d.bool(forKey: "files.video.shuffle") }
        set { d.set(newValue, forKey: "files.video.shuffle") }
    }
    /// مشغّل الفيديو: ٠ بلا تكرار، ١ تكرار القائمة، ٢ تكرار الفيديو
    static var videoRepeat: Int {
        get { d.integer(forKey: "files.video.repeat") }
        set { d.set(newValue, forKey: "files.video.repeat") }
    }
}

/// بيانات إضافية: التثبيت، ألوان المجلدات، المجلدات المقفلة، الترتيب اليدوي، وأصل الملفات في السلة
struct FileMeta: Codable {
    var pins: Set<String> = []
    var colors: [String: String] = [:]
    var locked: Set<String> = []
    var order: [String: [String]] = [:]
    var trashOrigin: [String: String] = [:]
    var trashDate: [String: Double] = [:]
}

@MainActor
final class FileStore: ObservableObject {
    static let shared = FileStore()

    let root: URL
    let trash: URL
    /// الخزنة: المجلدات المقفلة تُحفظ هنا (Application Support) فلا تظهر في تطبيق «الملفات» ولا Finder ولا الواي فاي
    let vault: URL
    /// المحذوفات من داخل الخزنة
    let vaultTrash: URL
    /// محتوى الخزنة التابع لمجلد عادي حُذف (يرجع معه إن استُعيد، ويُحذف معه نهائيًا)
    let trashTwins: URL
    @Published private(set) var meta = FileMeta()
    /// يتغيّر مع كل تعديل لتتحدّث الصفحات
    @Published private(set) var rev = 0
    /// المجلدات المفتوحة بعد التحقق (تبقى مفتوحة حتى يُغلق التطبيق أو يذهب للخلفية)
    @Published var unlocked: Set<String> = []

    private let fm = FileManager.default
    private var metaURL: URL

    private init() {
        root = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        trash = root.appendingPathComponent(".Trash", isDirectory: true)
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        metaURL = support.appendingPathComponent("files_meta.json")
        vault = support.appendingPathComponent("LockedVault", isDirectory: true)
        vaultTrash = vault.appendingPathComponent(".Trash", isDirectory: true)
        trashTwins = vault.appendingPathComponent(".TrashTwins", isDirectory: true)
        try? fm.createDirectory(at: trash, withIntermediateDirectories: true)
        for d in [vault, vaultTrash, trashTwins] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
        if let d = try? Data(contentsOf: metaURL), let m = try? JSONDecoder().decode(FileMeta.self, from: d) { meta = m }
        migrateLocked()
        // مرة واحدة: نقل المجلدات المقفلة القديمة من «ملفاتي» إلى الخزنة
        if !UserDefaults.standard.bool(forKey: "files_vault_v1") {
            migrateToVault()
            UserDefaults.standard.set(true, forKey: "files_vault_v1")
        }
        reconcileVault()
        // مجلدات العرض التجريبي (للمراجعة الآلية فقط)
        if SHOT.hasPrefix("files") || SHOT == "scanner" || ProcessInfo.processInfo.arguments.contains("-seedFiles") { seedDemo() }
    }

    func touch() { rev += 1 }

    private func saveMeta() {
        if let d = try? JSONEncoder().encode(meta) { try? d.write(to: metaURL, options: .atomic) }
        touch()
    }

    // MARK: المسارات

    /// المفتاح المنطقي للمسار: نفسه للمجلد في «ملفاتي» ولتوأمه في الخزنة
    func key(_ url: URL) -> String {
        let p = url.standardizedFileURL.path
        for base in [root, vault] {
            let r = base.standardizedFileURL.path
            if p == r { return "" }
            if p.hasPrefix(r + "/") { return String(p.dropFirst(r.count)) }
        }
        return p
    }

    /// مقارنة بالمسار (الروابط قد تختلف بشرطة في آخرها)
    nonisolated static func same(_ a: URL, _ b: URL) -> Bool { a.standardizedFileURL.path == b.standardizedFileURL.path }
    nonisolated static func isInside(_ u: URL, _ base: URL) -> Bool {
        let p = u.standardizedFileURL.path, r = base.standardizedFileURL.path
        return p == r || p.hasPrefix(r + "/")
    }
    func isUnderRoot(_ u: URL) -> Bool { Self.isInside(u, root) }
    func inVault(_ u: URL) -> Bool { Self.isInside(u, vault) }
    func isTrash(_ url: URL) -> Bool { Self.isInside(url, trash) || Self.isInside(url, vaultTrash) }
    /// هل المسار داخل مجلد مقفل (أحد أجزائه مقفل)؟
    func insideLocked(_ u: URL) -> Bool { key(u).split(separator: "/").contains { $0.hasPrefix(Self.lockPrefix) } }
    /// الرابط الفعلي لمفتاح محفوظ (قوائم التشغيل، التنزيلات، التذكيرات)
    func url(forKey k: String) -> URL {
        let rel = k.hasPrefix("/") ? String(k.dropFirst()) : k
        let isLockedPath = rel.split(separator: "/").contains { $0.hasPrefix(Self.lockPrefix) }
        return (isLockedPath ? vault : root).appendingPathComponent(rel)
    }
    /// المجلد الفعلي الذي يُحفظ فيه عنصر داخل مجلد منطقي: المجلد المقفل يذهب لتوأم المجلد في الخزنة
    func physicalDir(forName name: String, in dir: URL) -> URL {
        guard name.hasPrefix(Self.lockPrefix), isUnderRoot(dir), !isTrash(dir) else { return dir }
        let d = vault.appendingPathComponent(key(dir), isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func displayName(_ dir: URL) -> String {
        if dir.standardizedFileURL == root.standardizedFileURL { return L("ملفاتي") }
        if dir.standardizedFileURL == trash.standardizedFileURL { return L("سلة المحذوفات") }
        return Self.plainName(dir)
    }

    // MARK: القراءة

    func item(_ url: URL) -> FileItem? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .totalFileAllocatedSizeKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
        let dir = v.isDirectory ?? false
        return FileItem(url: url, name: FileStore.plainName(url), isDir: dir,
                        size: Int64(v.fileSize ?? 0),
                        modified: v.contentModificationDate ?? Date.distantPast,
                        created: v.creationDate ?? v.contentModificationDate ?? Date.distantPast,
                        kind: FileKind.of(url, isDir: dir))
    }

    func list(_ dir: URL) -> [FileItem] {
        // المجلدات المقفلة محفوظة في الخزنة (خارج «ملفاتي»)، وتظهر هنا فقط داخل التطبيق
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        var out = names.filter { !$0.hasPrefix(".") || $0.hasPrefix(Self.lockPrefix) }
            .compactMap { item(dir.appendingPathComponent($0)) }
        if let twin = vaultTwin(of: dir) {
            let all = Self.same(twin, vaultTrash)
            let extra = ((try? fm.contentsOfDirectory(atPath: twin.path)) ?? [])
                .filter { $0.hasPrefix(Self.lockPrefix) || (all && !$0.hasPrefix(".")) }
            out += extra.compactMap { item(twin.appendingPathComponent($0)) }
        }
        return out
    }

    /// توأم المجلد في الخزنة (لمجلدات «ملفاتي» فقط)
    private func vaultTwin(of dir: URL) -> URL? {
        guard isUnderRoot(dir) else { return nil }
        if Self.same(dir, trash) { return vaultTrash }
        if isTrash(dir) { return nil }
        let t = vault.appendingPathComponent(key(dir), isDirectory: true)
        return fm.fileExists(atPath: t.path) ? t : nil
    }

    // MARK: القفل الحقيقي للمجلدات
    /// المجلد المقفل يُعاد تسميته باسم مخفي (يبدأ بنقطة)؛ فلا يظهر في تطبيق «الملفات» ولا Finder ولا الواي فاي ولا البحث
    nonisolated static let lockPrefix = ".rafiqi-locked-"
    nonisolated static func plainName(_ u: URL) -> String {
        let n = u.lastPathComponent
        return n.hasPrefix(lockPrefix) ? String(n.dropFirst(lockPrefix.count)) : n
    }

    /// ينقل مفاتيح البيانات الإضافية للمجلد وكل ما تحته
    private func moveMetaTree(from a: URL, to b: URL) {
        let ka = key(a), kb = key(b)
        func map(_ k: String) -> String? {
            if k == ka { return kb }
            if k.hasPrefix(ka + "/") { return kb + k.dropFirst(ka.count) }
            return nil
        }
        meta.pins = Set(meta.pins.map { map($0) ?? $0 })
        meta.locked = Set(meta.locked.map { map($0) ?? $0 })
        meta.colors = Dictionary(meta.colors.map { (map($0.key) ?? $0.key, $0.value) }, uniquingKeysWith: { a, _ in a })
        meta.order = Dictionary(meta.order.map { (map($0.key) ?? $0.key, $0.value) }, uniquingKeysWith: { a, _ in a })
        unlocked = Set(unlocked.map { map($0) ?? $0 })
        saveMeta()
    }

    /// المجلدات التي قُفلت في نسخ سابقة (القفل كان داخل التطبيق فقط): نخفيها فعليًا
    private func migrateLocked() {
        for k in meta.locked {
            let u = root.appendingPathComponent(k)
            guard !u.lastPathComponent.hasPrefix(Self.lockPrefix), fm.fileExists(atPath: u.path) else { continue }
            let dest = unique(Self.lockPrefix + u.lastPathComponent, in: u.deletingLastPathComponent())
            if (try? fm.moveItem(at: u, to: dest)) != nil {
                moveMetaTree(from: u, to: dest)
                migrateToVault(in: u.deletingLastPathComponent())
            }
        }
    }

    /// النسخ السابقة: المجلدات المقفلة كانت باسم مخفي داخل «ملفاتي» — تُنقل للخزنة بنفس المفتاح
    private func migrateToVault(in base: URL? = nil) {
        guard let e = fm.enumerator(at: base ?? root, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        var found: [URL] = []
        for case let u as URL in e {
            let n = u.lastPathComponent
            if n.hasPrefix(".") && !n.hasPrefix(Self.lockPrefix) && !Self.isInside(u, trash) { e.skipDescendants(); continue }
            guard n.hasPrefix(Self.lockPrefix) else { continue }
            e.skipDescendants()
            found.append(u)
        }
        for u in found {
            let parent = u.deletingLastPathComponent()
            let destDir: URL
            if Self.same(parent, trash) { destDir = vaultTrash }
            else if isTrash(parent) { continue }   // داخل مجلد محذوف: يبقى مع المحذوفات حتى تُفرغ
            else { destDir = vault.appendingPathComponent(key(parent), isDirectory: true) }
            try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            // لا نكتب فوق شيء أبدًا: عند تشابه الاسم يأخذ اسمًا جديدًا وتنتقل بياناته الإضافية معه
            let dest = unique(u.lastPathComponent, in: destDir)
            if (try? fm.moveItem(at: u, to: dest)) != nil, key(dest) != key(u) { moveMetaTree(from: u, to: dest) }
        }
    }

    /// مجلد مقفل في الخزنة اختفى مجلده الأب من «ملفاتي» (حُذف أو غُيّر اسمه من تطبيق «الملفات»):
    /// يُعاد إنشاء الأب فارغًا حتى لا يضيع المجلد المقفل
    func reconcileVault() {
        guard let e = fm.enumerator(at: vault, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let u as URL in e {
            let n = u.lastPathComponent
            if n == ".Trash" || n == ".TrashTwins" { e.skipDescendants(); continue }
            guard n.hasPrefix(Self.lockPrefix) else { continue }
            e.skipDescendants()
            let parent = u.deletingLastPathComponent()
            guard !insideLocked(parent) else { continue }
            let docParent = root.appendingPathComponent(key(parent), isDirectory: true)
            if !fm.fileExists(atPath: docParent.path) { try? fm.createDirectory(at: docParent, withIntermediateDirectories: true) }
        }
    }

    /// يحذف مجلدات الخزنة الوسيطة الفارغة بعد نقل أو فتح مجلد
    private func pruneVault(_ dir: URL) {
        var d = dir.standardizedFileURL
        // داخل مجلد مقفل المجلدات للمستخدم (ولو فارغة)؛ الوسيطة فقط هي التي تُنظَّف
        while inVault(d), !Self.same(d, vault), !Self.same(d, vaultTrash), !Self.same(d, trashTwins),
              !d.lastPathComponent.hasPrefix(Self.lockPrefix), !insideLocked(d),
              ((try? fm.contentsOfDirectory(atPath: d.path)) ?? ["x"]).isEmpty {
            try? fm.removeItem(at: d)
            d = d.deletingLastPathComponent()
        }
    }

    /// إعادة تسمية أو نقل مجلد عادي: ينتقل توأمه في الخزنة معه
    private func moveTwin(from a: URL, to b: URL) {
        guard isUnderRoot(a) else { return }
        let ta = vault.appendingPathComponent(key(a), isDirectory: true)
        guard fm.fileExists(atPath: ta.path) else { return }
        // نُقل المجلد إلى داخل مجلد مقفل: مجلداته المقفلة تصبح داخله مباشرة (كلها في الخزنة)
        let tb = inVault(b) ? b : vault.appendingPathComponent(key(b), isDirectory: true)
        try? fm.createDirectory(at: tb.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: tb.path) {
            try? fm.moveItem(at: ta, to: tb)
        } else {
            for n in (try? fm.contentsOfDirectory(atPath: ta.path)) ?? [] {
                try? fm.moveItem(at: ta.appendingPathComponent(n), to: unique(n, in: tb))
            }
        }
        pruneVault(ta.deletingLastPathComponent())
        pruneVault(ta)
    }

    /// كل الملفات داخل مجلد وما تحته (للبحث والتصنيفات)
    func deepList(_ dir: URL) -> [FileItem] {
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var out: [FileItem] = []
        for case let u as URL in e { if let i = item(u) { out.append(i) } }
        return out
    }

    func sorted(_ items: [FileItem], in dir: URL, by s: FileSort = FilePrefs.sort, ascending: Bool = FilePrefs.ascending) -> [FileItem] {
        var a: [FileItem]
        switch s {
        case .date: a = items.sorted { $0.modified > $1.modified }
        case .name: a = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size: a = items.sorted { $0.size > $1.size }
        case .type: a = items.sorted { ($0.kind.rawValue, $0.ext, $0.name) < ($1.kind.rawValue, $1.ext, $1.name) }
        case .manual:
            let order = meta.order[key(dir)] ?? []
            a = items.sorted {
                let i = order.firstIndex(of: $0.name) ?? Int.max, j = order.firstIndex(of: $1.name) ?? Int.max
                return i == j ? $0.modified > $1.modified : i < j
            }
        }
        // التصاعدي/التنازلي (الاسم تصاعدي افتراضيًا، والباقي تنازلي)
        if s != .manual && ascending != (s == .name) { a.reverse() }
        // المثبّتة أولًا ثم المجلدات
        let pinned = a.filter { isPinned($0.url) }
        let rest = a.filter { !isPinned($0.url) }
        return pinned + rest.filter(\.isDir) + rest.filter { !$0.isDir }
    }

    func setManualOrder(_ names: [String], in dir: URL) {
        meta.order[key(dir)] = names
        FilePrefs.sort = .manual
        saveMeta()
    }

    func folderSize(_ url: URL) -> Int64 {
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in e {
            let v = try? u.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(v?.fileSize ?? 0)
        }
        return total
    }

    func count(_ dir: URL) -> Int {
        var n = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") || $0.hasPrefix(Self.lockPrefix) }.count
        if let twin = vaultTwin(of: dir) {
            let all = Self.same(twin, vaultTrash)
            n += ((try? fm.contentsOfDirectory(atPath: twin.path)) ?? []).filter { $0.hasPrefix(Self.lockPrefix) || (all && !$0.hasPrefix(".")) }.count
        }
        return n
    }

    // MARK: إنشاء وتعديل

    /// اسم غير مكرر داخل المجلد: «ملف (٢).pdf»
    func unique(_ name: String, in dir: URL) -> URL { uniqueFileURL(name, in: dir) }

    @discardableResult
    func createFolder(_ name: String, in dir: URL) -> URL? {
        let clean = sanitize(name.isEmpty ? L("مجلد جديد") : name)
        let u = unique(clean, in: dir)
        do { try fm.createDirectory(at: u, withIntermediateDirectories: true); touch(); return u } catch { return nil }
    }

    @discardableResult
    func createText(_ name: String, text: String = "", in dir: URL) -> URL? {
        var n = sanitize(name.isEmpty ? L("ملاحظة") : name)
        if (n as NSString).pathExtension.isEmpty { n += ".txt" }
        let u = unique(n, in: dir)
        do { try text.write(to: u, atomically: true, encoding: .utf8); touch(); return u } catch { return nil }
    }

    func sanitize(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\")
        let t = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.capName(t.hasPrefix(".") ? "_" + t.dropFirst() : t)
    }

    /// النظام لا يقبل اسمًا فوق ٢٥٥ بايت (الحرف العربي بايتان): نقصّ إلى ٢٠٠ بايت مع الحفاظ على الامتداد،
    /// فيبقى هامش لـ«(٢)» ولامتداد يُضاف بعدها (مثل .pdf)
    static func capName(_ name: String, maxBytes: Int = 200) -> String {
        guard name.utf8.count > maxBytes else { return name }
        let ext = (name as NSString).pathExtension
        let keepExt = !ext.isEmpty && ext.utf8.count <= 10
        var base = keepExt ? (name as NSString).deletingPathExtension : name
        let budget = maxBytes - (keepExt ? ext.utf8.count + 1 : 0)
        while base.utf8.count > budget { base.removeLast() }   // يحذف حرفًا كاملًا (لا يقطع حرفًا عربيًا من نصفه)
        base = base.trimmingCharacters(in: .whitespaces)
        return keepExt ? base + "." + ext : base
    }

    /// إعادة التسمية مع الحفاظ على الامتداد إن لم يكتبه المستخدم
    @discardableResult
    func rename(_ url: URL, to newName: String) -> URL? {
        var n = sanitize(newName)
        guard !n.isEmpty else { return nil }
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if !isDir, (n as NSString).pathExtension.isEmpty, !url.pathExtension.isEmpty { n += "." + url.pathExtension }
        if url.lastPathComponent.hasPrefix(Self.lockPrefix) { n = Self.lockPrefix + n }
        guard n != url.lastPathComponent else { return url }
        let dest = unique(n, in: url.deletingLastPathComponent())
        do {
            try fm.moveItem(at: url, to: dest)
            if isDir { moveTwin(from: url, to: dest) }
            moveMetaTree(from: url, to: dest)
            touch()
            return dest
        } catch { return nil }
    }

    /// نقل إلى مجلد (يتجاهل نقل المجلد داخل نفسه)
    func move(_ urls: [URL], to dir: URL) -> Int {
        var n = 0
        for u in urls {
            // المقارنة بالمفتاح المنطقي (المجلد وتوأمه في الخزنة مكان واحد)
            let ku = key(u), kd = key(dir)
            if kd == ku || kd.hasPrefix(ku + "/") { continue }
            if key(u.deletingLastPathComponent()) == kd { continue }
            let target = physicalDir(forName: u.lastPathComponent, in: dir)
            let dest = unique(u.lastPathComponent, in: target)
            let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if (try? fm.moveItem(at: u, to: dest)) != nil {
                if isDir { moveTwin(from: u, to: dest) }
                moveMetaTree(from: u, to: dest)
                if inVault(u) { pruneVault(u.deletingLastPathComponent()) }
                if isDir, isUnderRoot(dest) { migrateToVault(in: dest) }
                n += 1
            }
        }
        touch()
        return n
    }

    /// نسخ (إنشاء نسخة)
    @discardableResult
    func copy(_ urls: [URL], to dir: URL? = nil) -> [URL] {
        var out: [URL] = []
        for u in urls {
            let d = dir.map { physicalDir(forName: u.lastPathComponent, in: $0) } ?? u.deletingLastPathComponent()
            let base = (u.lastPathComponent as NSString).deletingPathExtension, ext = u.pathExtension
            let name = dir == nil ? (ext.isEmpty ? LF("%@ - نسخة", base) : LF("%@ - نسخة", base) + "." + ext) : u.lastPathComponent
            let dest = unique(name, in: d)
            if (try? fm.copyItem(at: u, to: dest)) != nil {
                out.append(dest)
                if isUnderRoot(dest) { migrateToVault(in: dest) }
            }
        }
        touch()
        return out
    }

    /// استيراد ملفات من خارج التطبيق (تطبيق الملفات، المشاركة، الصور)
    @discardableResult
    func importFiles(_ urls: [URL], to dir: URL, move: Bool = false) -> [URL] {
        var out: [URL] = []
        for u in urls {
            let scoped = u.startAccessingSecurityScopedResource()
            defer { if scoped { u.stopAccessingSecurityScopedResource() } }
            let dest = unique(u.lastPathComponent, in: dir)
            do {
                if move { try fm.moveItem(at: u, to: dest) } else { try fm.copyItem(at: u, to: dest) }
                out.append(dest)
            } catch {
                // نسخ عبر القراءة على دفعات (بعض المزوّدات لا تسمح بالنسخ المباشر) — لا يُحمَّل الملف كله في الذاكرة
                if Self.streamCopy(u, to: dest) { out.append(dest) }
            }
        }
        touch()
        return out
    }

    /// نسخ بقطع ٤ م.ب؛ يحذف الناتج الناقص إن فشل
    nonisolated static func streamCopy(_ src: URL, to dest: URL) -> Bool {
        guard let input = try? FileHandle(forReadingFrom: src) else { return false }
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: dest.path, contents: nil),
              let output = try? FileHandle(forWritingTo: dest) else { return false }
        defer { try? output.close() }
        do {
            while true {
                let chunk = try autoreleasepool { try input.read(upToCount: 4 << 20) ?? Data() }
                if chunk.isEmpty { break }
                try output.write(contentsOf: chunk)
            }
            return true
        } catch {
            try? FileManager.default.removeItem(at: dest)
            return false
        }
    }

    @discardableResult
    func importData(_ data: Data, name: String, to dir: URL) -> URL? {
        let dest = unique(sanitize(name), in: dir)
        do { try data.write(to: dest); touch(); return dest } catch { return nil }
    }

    /// المجلد المناسب للملف عند تفعيل «الترتيب التلقائي»
    func destination(for name: String, base: URL? = nil, source: String? = nil) -> URL {
        let b = base ?? root
        let folder: String
        switch FilePrefs.folderMode {
        case 1: folder = FileKind.of(URL(fileURLWithPath: name), isDir: false).folderName
        case 2:
            var h = source ?? ""
            if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
            folder = h.isEmpty ? L("أخرى") : sanitize(h)
        default: return b
        }
        let d = b.appendingPathComponent(folder, isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: السلة

    /// اسم غير مكرر في السلتين معًا (بيانات السلة مفهرسة بالاسم)
    private func trashName(_ name: String) -> String {
        var n = name, i = 2
        let ext = (name as NSString).pathExtension, base = (name as NSString).deletingPathExtension
        while fm.fileExists(atPath: trash.appendingPathComponent(n).path) || fm.fileExists(atPath: vaultTrash.appendingPathComponent(n).path)
                || fm.fileExists(atPath: trashTwins.appendingPathComponent(n).path) {
            n = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"; i += 1
        }
        return n
    }

    func moveToTrash(_ urls: [URL]) {
        let gone = urls.map { key($0) }
        Task.detached(priority: .utility) { ScanProjects.forget(keys: gone) }
        for u in urls {
            if isTrash(u) { deleteForever([u]); continue }
            // ما في الخزنة يبقى في سلة الخزنة (لا يظهر في تطبيق «الملفات»)
            let name = trashName(u.lastPathComponent)
            let dest = (inVault(u) ? vaultTrash : trash).appendingPathComponent(name)
            let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let twin = vault.appendingPathComponent(key(u), isDirectory: true)
            if (try? fm.moveItem(at: u, to: dest)) != nil {
                // مجلد عادي فيه مجلدات مقفلة: تُحفظ مقفلة مع المحذوفات وترجع معه
                if isDir, isUnderRoot(u), fm.fileExists(atPath: twin.path) {
                    try? fm.moveItem(at: twin, to: trashTwins.appendingPathComponent(name))
                    pruneVault(twin.deletingLastPathComponent())
                }
                if inVault(u) { pruneVault(u.deletingLastPathComponent()) }
                meta.trashOrigin[name] = key(u.deletingLastPathComponent())
                meta.trashDate[name] = Date().timeIntervalSince1970
                meta.pins.remove(key(u))
            }
        }
        saveMeta()
    }

    /// عنصر في أعلى السلة مباشرة (لا داخل مجلد محذوف) — وحده له أصل وتوأم مسجّلان باسمه
    private func isTopOfTrash(_ u: URL) -> Bool {
        let parent = u.deletingLastPathComponent()
        return Self.same(parent, trash) || Self.same(parent, vaultTrash)
    }

    func restore(_ urls: [URL]) {
        for u in urls {
            let name = u.lastPathComponent
            let top = isTopOfTrash(u)
            let logical = (top ? meta.trashOrigin[name].map { url(forKey: $0) } : nil) ?? root
            // داخل الخزنة: يرجع لمجلده المقفل؛ ومجلد مقفل يرجع لتوأم مجلده في الخزنة
            let origin = physicalDir(forName: name, in: logical)
            try? fm.createDirectory(at: origin, withIntermediateDirectories: true)
            if isUnderRoot(origin) { try? fm.createDirectory(at: logical, withIntermediateDirectories: true) }
            let dest = unique(name, in: origin)
            if (try? fm.moveItem(at: u, to: dest)) != nil {
                let twin = trashTwins.appendingPathComponent(name)
                if top, fm.fileExists(atPath: twin.path) {
                    let t = vault.appendingPathComponent(key(dest), isDirectory: true)
                    try? fm.createDirectory(at: t.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if (try? fm.moveItem(at: twin, to: t)) == nil {
                        for n in (try? fm.contentsOfDirectory(atPath: twin.path)) ?? [] { try? fm.moveItem(at: twin.appendingPathComponent(n), to: unique(n, in: t)) }
                    }
                }
                if isUnderRoot(dest) { migrateToVault(in: dest) }
                if top {
                    meta.trashOrigin.removeValue(forKey: name)
                    meta.trashDate.removeValue(forKey: name)
                }
            }
        }
        reconcileVault()
        saveMeta()
    }

    func deleteForever(_ urls: [URL]) {
        for u in urls {
            let top = isTopOfTrash(u)
            try? fm.removeItem(at: u)
            // التوأم والسجل باسم العنصر الأعلى فقط: حذف عنصر داخل مجلد محذوف لا يمس توأم مجلد آخر بنفس الاسم
            guard top else { continue }
            try? fm.removeItem(at: trashTwins.appendingPathComponent(u.lastPathComponent))
            meta.trashOrigin.removeValue(forKey: u.lastPathComponent)
            meta.trashDate.removeValue(forKey: u.lastPathComponent)
        }
        saveMeta()
    }

    /// تُحذف ملفات السلة نهائيًا بعد ٣٠ يومًا
    func purgeOldTrash() {
        let cutoff = Date().addingTimeInterval(-30 * 86400).timeIntervalSince1970
        let items = ((try? fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? [])
            + ((try? fm.contentsOfDirectory(at: vaultTrash, includingPropertiesForKeys: nil)) ?? [])
        let old = items.filter { (meta.trashDate[$0.lastPathComponent] ?? Date().timeIntervalSince1970) < cutoff }
        if !old.isEmpty { deleteForever(old) }
    }

    // MARK: التثبيت واللون والقفل

    func isPinned(_ u: URL) -> Bool { meta.pins.contains(key(u)) }
    func togglePin(_ u: URL) {
        let k = key(u)
        if meta.pins.contains(k) { meta.pins.remove(k) } else { meta.pins.insert(k) }
        saveMeta()
    }

    static let folderColors: [(String, Color)] = [
        ("default", Theme.gold), ("teal", Color(red: 0.36, green: 0.66, blue: 0.66)), ("blue", Color(red: 0.36, green: 0.55, blue: 0.85)),
        ("green", Color(red: 0.40, green: 0.70, blue: 0.48)), ("red", Color(red: 0.86, green: 0.40, blue: 0.40)),
        ("purple", Color(red: 0.62, green: 0.48, blue: 0.86)), ("gray", Color(white: 0.62)),
    ]
    func color(_ u: URL) -> Color {
        let c = meta.colors[key(u)] ?? "default"
        return Self.folderColors.first { $0.0 == c }?.1 ?? Theme.gold
    }
    func setColor(_ u: URL, _ c: String) {
        if c == "default" { meta.colors.removeValue(forKey: key(u)) } else { meta.colors[key(u)] = c }
        saveMeta()
    }

    func isLocked(_ u: URL) -> Bool { u.lastPathComponent.hasPrefix(Self.lockPrefix) || meta.locked.contains(key(u)) }
    func needsUnlock(_ u: URL) -> Bool { isLocked(u) && !unlocked.contains(key(u)) }
    /// قفل/فتح المجلد: يُخفى فعليًا باسم مخفي، ويرجع رابطه الجديد
    @discardableResult
    func setLocked(_ u: URL, _ on: Bool) -> URL {
        let parent = u.deletingLastPathComponent()
        let plain = Self.plainName(u)
        // القفل: من «ملفاتي» إلى توأم المجلد في الخزنة. الفتح: يرجع لـ«ملفاتي» إن لم يكن داخل مجلد مقفل آخر
        var target = parent
        if on, isUnderRoot(u) { target = vault.appendingPathComponent(key(parent), isDirectory: true) }
        if !on, inVault(u), !insideLocked(parent) { target = root.appendingPathComponent(key(parent), isDirectory: true) }
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        let dest = unique(on ? Self.lockPrefix + plain : plain, in: target)
        var out = u
        if !Self.same(dest, u), (try? fm.moveItem(at: u, to: dest)) != nil {
            // مجلدات مقفلة كانت داخله (توأمه) تنتقل معه
            if on, isUnderRoot(u) {
                let twin = vault.appendingPathComponent(key(u), isDirectory: true)
                if fm.fileExists(atPath: twin.path) {
                    for n in (try? fm.contentsOfDirectory(atPath: twin.path)) ?? [] { try? fm.moveItem(at: twin.appendingPathComponent(n), to: unique(n, in: dest)) }
                    pruneVault(twin)
                }
            }
            moveMetaTree(from: u, to: dest)
            if inVault(u) { pruneVault(parent) }
            // فتح مجلد فيه مجلدات مقفلة: تبقى المقفلة في الخزنة
            if !on, isUnderRoot(dest) { migrateToVault(in: dest) }
            out = dest
        }
        if on { meta.locked.insert(key(out)) } else { meta.locked.remove(key(out)); unlocked.remove(key(out)) }
        saveMeta()
        return out
    }

    /// التحقق ببصمة الوجه أو رمز الجوال
    static func authenticate(_ reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    func unlock(_ u: URL) async -> Bool {
        guard needsUnlock(u) else { return true }
        if await Self.authenticate(L("افتح المجلد المقفل")) { unlocked.insert(key(u)); return true }
        return false
    }

    func relockAll() { unlocked.removeAll(); reconcileVault() }

    /// أول مجلد مقفل (من الأعلى) في مسار هذا الرابط يحتاج تحققًا — nil إن كان المسار كله مفتوحًا
    func lockedAncestor(_ u: URL) -> URL? {
        let base = inVault(u) ? vault : root
        let rel = key(u).split(separator: "/").map(String.init)
        var cur = base
        for part in rel {
            cur = cur.appendingPathComponent(part)
            if needsUnlock(cur) { return cur }
        }
        return nil
    }

    /// هل يمكن حماية الملفات؟ (يحتاج رمز قفل للجوال؛ بدونه لا يمكن طلب التحقق)
    static var canProtect: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
    }

    // MARK: الضغط

    /// ضغط ملف أو عدة ملفات في ملف ZIP بجانبها
    func zip(_ urls: [URL], name: String? = nil) async -> URL? {
        guard let first = urls.first else { return nil }
        let dir = first.deletingLastPathComponent()
        let zipName = (name ?? (urls.count == 1 ? first.deletingPathExtension().lastPathComponent : L("ملفات مضغوطة"))) + ".zip"
        let dest = unique(zipName, in: dir)
        let fm = self.fm
        let ok: Bool = await Task.detached {
            do {
                let archive = try Archive(url: dest, accessMode: .create)
                for u in urls {
                    let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if isDir {
                        let base = u.deletingLastPathComponent()
                        if let e = fm.enumerator(at: u, includingPropertiesForKeys: [.isDirectoryKey]) {
                            try archive.addEntry(with: u.lastPathComponent + "/", type: .directory, uncompressedSize: Int64(0), provider: { _, _ in Data() })
                            while let f = e.nextObject() as? URL {
                                let rel = String(f.standardizedFileURL.path.dropFirst(base.standardizedFileURL.path.count + 1))
                                let d = (try? f.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                                if d { try archive.addEntry(with: rel + "/", type: .directory, uncompressedSize: Int64(0), provider: { _, _ in Data() }) }
                                else { try archive.addEntry(with: rel, relativeTo: base, compressionMethod: .deflate) }
                            }
                        }
                    } else {
                        try archive.addEntry(with: u.lastPathComponent, relativeTo: dir, compressionMethod: .deflate)
                    }
                }
                return true
            } catch {
                try? fm.removeItem(at: dest)
                return false
            }
        }.value
        touch()
        return ok ? dest : nil
    }

    /// فك الضغط في مجلد باسم الملف
    func unzip(_ url: URL) async -> URL? {
        let dir = unique(url.deletingPathExtension().lastPathComponent, in: url.deletingLastPathComponent())
        let fm = self.fm
        let ok: Bool = await Task.detached {
            do {
                // ملف مضغوط «قنبلة» (حجمه بعد الفك أكبر من مساحة الجوال أو ملايين الملفات): يُرفض قبل أن يملأ الجوال
                let archive = try Archive(url: url, accessMode: .read, pathEncoding: .utf8)
                var total: Int64 = 0, count = 0
                for e in archive { total += Int64(clamping: e.uncompressedSize); count += 1 }
                let free = (try? dir.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? .max
                guard count <= 50_000, total < free - 200_000_000 else { return false }
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try fm.unzipItem(at: url, to: dir, pathEncoding: .utf8)
                return true
            } catch {
                try? fm.removeItem(at: dir)
                return false
            }
        }.value
        touch()
        return ok ? dir : nil
    }

    // MARK: الصور

    /// حفظ الصور والفيديو في تطبيق «الصور»
    func saveToPhotos(_ urls: [URL]) async -> Int {
        let st = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard st == .authorized || st == .limited else { return -1 }
        var n = 0
        for u in urls {
            let k = FileKind.of(u, isDir: false)
            guard k == .image || k == .video else { continue }
            let ok = (try? await PHPhotoLibrary.shared().performChanges {
                if k == .image { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: u) }
                else { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: u) }
            }) != nil
            if ok { n += 1 }
        }
        return n
    }

    // MARK: المساحة

    func usage() -> (files: Int64, trash: Int64, temp: Int64, free: Int64) {
        let files = folderSize(root) - folderSize(trash) + folderSize(vault) - folderSize(vaultTrash) - folderSize(trashTwins)
        let tmp = folderSize(fm.temporaryDirectory) + folderSize(fm.urls(for: .cachesDirectory, in: .userDomainMask)[0])
        let free = (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        return (files, folderSize(trash) + folderSize(vaultTrash) + folderSize(trashTwins), tmp, free)
    }

    /// حذف الملفات المؤقتة (لا تتأثر ملفاتك ولا تنزيلاتك)
    func clearTemp() {
        for d in [fm.temporaryDirectory, fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]] {
            for u in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [] {
                // لا نحذف ذاكرة القرآن ولا صور الويدجت
                if u.lastPathComponent.hasPrefix("com.apple") { continue }
                // صفحات المسح الحالية تبقى يومًا، وغيرها ساعة: لا يُحذف ملف تستخدمه عملية جارية
                // (تحويل، تنزيل وصل للتو، صفحات مسح لم تُحفظ بعد)
                purgeTemp(u, olderThan: u.lastPathComponent == "scan-pages" ? 86400 : 3600)
            }
        }
        touch()
    }

    /// يحذف الملف (أو محتويات المجلد ملفًا ملفًا) إن لم يُعدَّل منذ المدة المحددة
    private func purgeTemp(_ u: URL, olderThan age: TimeInterval) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        let v = try? u.resourceValues(forKeys: keys)
        if v?.isDirectory == true {
            for c in (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: Array(keys))) ?? [] { purgeTemp(c, olderThan: age) }
            if ((try? fm.contentsOfDirectory(atPath: u.path)) ?? ["x"]).isEmpty { try? fm.removeItem(at: u) }
            return
        }
        let modified = v?.contentModificationDate ?? .distantPast
        if Date().timeIntervalSince(modified) > age { try? fm.removeItem(at: u) }
    }

    // MARK: عرض تجريبي

    private func seedDemo() {
        guard list(root).isEmpty else { return }
        createFolder(L("قرآن"), in: root)
        createFolder(L("شعر"), in: root)
        createText(L("ملاحظة"), text: "رفيقي", in: root)
        let r = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400))
        let img = r.pngData { c in
            UIColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
            ("رفيقي 123" as NSString).draw(at: CGPoint(x: 160, y: 170), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48), .foregroundColor: UIColor.white])
        }
        importData(img, name: "صورة.png", to: root)
        // نغمة قصيرة (٣ ثوانٍ) لتجربة أدوات الصوت
        var wav = Data()
        let rate = 22050, n = rate * 3
        func u32(_ v: UInt32) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: 2)) }
        wav.append(Data("RIFF".utf8)); u32(UInt32(36 + n * 2)); wav.append(Data("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        wav.append(Data("data".utf8)); u32(UInt32(n * 2))
        for i in 0..<n { u16(UInt16(bitPattern: Int16(sin(Double(i) * 2 * .pi * 440 / Double(rate)) * 8000))) }
        importData(wav, name: "نغمة.wav", to: root)
        // ملف PDF من صفحتين
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { c in
            for t in ["صفحة ١", "صفحة ٢"] { c.beginPage(); (t as NSString).draw(at: CGPoint(x: 100, y: 180), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28)]) }
        }
        importData(pdf, name: "مستند.pdf", to: root)
    }
}

/// اسم غير مكرر داخل المجلد: «ملف (٢).pdf» — دالة واحدة لكل التطبيق (تعمل من أي خيط)
func uniqueFileURL(_ name: String, in dir: URL) -> URL {
    let fm = FileManager.default
    var u = dir.appendingPathComponent(name)
    guard fm.fileExists(atPath: u.path) else { return u }
    let ext = (name as NSString).pathExtension
    let base = (name as NSString).deletingPathExtension
    var n = 2
    repeat {
        u = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
        n += 1
    } while fm.fileExists(atPath: u.path)
    return u
}

/// حجم مقروء: «٣٫٤ م.ب»
func sizeText(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowedUnits = [.useKB, .useMB, .useGB]
    var s = f.string(fromByteCount: bytes)
    if !Lang.isEN {
        s = s.replacingOccurrences(of: "GB", with: "غ.ب").replacingOccurrences(of: "MB", with: "م.ب")
            .replacingOccurrences(of: "KB", with: "ك.ب").replacingOccurrences(of: "kB", with: "ك.ب")
            .replacingOccurrences(of: "bytes", with: "بايت").replacingOccurrences(of: "Zero", with: "٠")
    }
    return ar(s)
}

/// مدة «١:٢٣:٥٦» أو «٠٤:١٩»
func durationText(_ s: Double) -> String {
    guard s.isFinite, s > 0 else { return ar("00:00") }
    let t = Int(s.rounded())
    let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
    let str = h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    return ar(str)
}
