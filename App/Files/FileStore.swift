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
        try? fm.createDirectory(at: trash, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: metaURL), let m = try? JSONDecoder().decode(FileMeta.self, from: d) { meta = m }
        // مجلدات العرض التجريبي (للمراجعة الآلية فقط)
        if SHOT == "files" || ProcessInfo.processInfo.arguments.contains("-seedFiles") { seedDemo() }
    }

    func touch() { rev += 1 }

    private func saveMeta() {
        if let d = try? JSONEncoder().encode(meta) { try? d.write(to: metaURL, options: .atomic) }
        touch()
    }

    // MARK: المسارات

    func key(_ url: URL) -> String {
        let r = root.standardizedFileURL.path, p = url.standardizedFileURL.path
        return p.hasPrefix(r) ? String(p.dropFirst(r.count)) : p
    }

    func isTrash(_ url: URL) -> Bool { url.standardizedFileURL.path.hasPrefix(trash.standardizedFileURL.path) }

    func displayName(_ dir: URL) -> String {
        if dir.standardizedFileURL == root.standardizedFileURL { return L("ملفاتي") }
        if dir.standardizedFileURL == trash.standardizedFileURL { return L("سلة المحذوفات") }
        return dir.lastPathComponent
    }

    // MARK: القراءة

    func item(_ url: URL) -> FileItem? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .totalFileAllocatedSizeKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
        let dir = v.isDirectory ?? false
        return FileItem(url: url, name: url.lastPathComponent, isDir: dir,
                        size: Int64(v.fileSize ?? 0),
                        modified: v.contentModificationDate ?? Date.distantPast,
                        created: v.creationDate ?? v.contentModificationDate ?? Date.distantPast,
                        kind: FileKind.of(url, isDir: dir))
    }

    func list(_ dir: URL) -> [FileItem] {
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { item($0) }
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
        ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }.count
    }

    // MARK: إنشاء وتعديل

    /// اسم غير مكرر داخل المجلد: «ملف (٢).pdf»
    func unique(_ name: String, in dir: URL) -> URL {
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
        return t.hasPrefix(".") ? "_" + t.dropFirst() : t
    }

    /// إعادة التسمية مع الحفاظ على الامتداد إن لم يكتبه المستخدم
    @discardableResult
    func rename(_ url: URL, to newName: String) -> URL? {
        var n = sanitize(newName)
        guard !n.isEmpty else { return nil }
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if !isDir, (n as NSString).pathExtension.isEmpty, !url.pathExtension.isEmpty { n += "." + url.pathExtension }
        guard n != url.lastPathComponent else { return url }
        let dest = unique(n, in: url.deletingLastPathComponent())
        do {
            try fm.moveItem(at: url, to: dest)
            moveMeta(from: url, to: dest)
            touch()
            return dest
        } catch { return nil }
    }

    private func moveMeta(from a: URL, to b: URL) {
        let ka = key(a), kb = key(b)
        if meta.pins.remove(ka) != nil { meta.pins.insert(kb) }
        if let c = meta.colors.removeValue(forKey: ka) { meta.colors[kb] = c }
        if meta.locked.remove(ka) != nil { meta.locked.insert(kb) }
        saveMeta()
    }

    /// نقل إلى مجلد (يتجاهل نقل المجلد داخل نفسه)
    func move(_ urls: [URL], to dir: URL) -> Int {
        var n = 0
        for u in urls {
            if dir.standardizedFileURL.path.hasPrefix(u.standardizedFileURL.path + "/") || dir.standardizedFileURL == u.standardizedFileURL { continue }
            if u.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL { continue }
            let dest = unique(u.lastPathComponent, in: dir)
            if (try? fm.moveItem(at: u, to: dest)) != nil { moveMeta(from: u, to: dest); n += 1 }
        }
        touch()
        return n
    }

    /// نسخ (إنشاء نسخة)
    @discardableResult
    func copy(_ urls: [URL], to dir: URL? = nil) -> [URL] {
        var out: [URL] = []
        for u in urls {
            let d = dir ?? u.deletingLastPathComponent()
            let base = (u.lastPathComponent as NSString).deletingPathExtension, ext = u.pathExtension
            let name = dir == nil ? (ext.isEmpty ? LF("%@ - نسخة", base) : LF("%@ - نسخة", base) + "." + ext) : u.lastPathComponent
            let dest = unique(name, in: d)
            if (try? fm.copyItem(at: u, to: dest)) != nil { out.append(dest) }
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
                // نسخ عبر القراءة (بعض المزوّدات لا تسمح بالنسخ المباشر)
                if let d = try? Data(contentsOf: u), (try? d.write(to: dest)) != nil { out.append(dest) }
            }
        }
        touch()
        return out
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

    func moveToTrash(_ urls: [URL]) {
        for u in urls {
            if isTrash(u) { try? fm.removeItem(at: u); continue }
            let dest = unique(u.lastPathComponent, in: trash)
            if (try? fm.moveItem(at: u, to: dest)) != nil {
                meta.trashOrigin[dest.lastPathComponent] = key(u.deletingLastPathComponent())
                meta.trashDate[dest.lastPathComponent] = Date().timeIntervalSince1970
                meta.pins.remove(key(u))
            }
        }
        saveMeta()
    }

    func restore(_ urls: [URL]) {
        for u in urls {
            let origin = meta.trashOrigin[u.lastPathComponent].map { root.appendingPathComponent($0) } ?? root
            try? fm.createDirectory(at: origin, withIntermediateDirectories: true)
            let dest = unique(u.lastPathComponent, in: origin)
            if (try? fm.moveItem(at: u, to: dest)) != nil {
                meta.trashOrigin.removeValue(forKey: u.lastPathComponent)
                meta.trashDate.removeValue(forKey: u.lastPathComponent)
            }
        }
        saveMeta()
    }

    func deleteForever(_ urls: [URL]) {
        for u in urls {
            try? fm.removeItem(at: u)
            meta.trashOrigin.removeValue(forKey: u.lastPathComponent)
            meta.trashDate.removeValue(forKey: u.lastPathComponent)
        }
        saveMeta()
    }

    func emptyTrash() { deleteForever(list(trash).map(\.url)) }

    /// تُحذف ملفات السلة نهائيًا بعد ٣٠ يومًا
    func purgeOldTrash() {
        let cutoff = Date().addingTimeInterval(-30 * 86400).timeIntervalSince1970
        let old = list(trash).filter { (meta.trashDate[$0.name] ?? Date().timeIntervalSince1970) < cutoff }.map(\.url)
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

    func isLocked(_ u: URL) -> Bool { meta.locked.contains(key(u)) }
    func needsUnlock(_ u: URL) -> Bool { isLocked(u) && !unlocked.contains(key(u)) }
    func setLocked(_ u: URL, _ on: Bool) {
        if on { meta.locked.insert(key(u)) } else { meta.locked.remove(key(u)); unlocked.remove(key(u)) }
        saveMeta()
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

    func relockAll() { unlocked.removeAll() }

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
                            for case let f as URL in e {
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
        let files = folderSize(root) - folderSize(trash)
        let tmp = folderSize(fm.temporaryDirectory) + folderSize(fm.urls(for: .cachesDirectory, in: .userDomainMask)[0])
        let free = (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        return (files, folderSize(trash), tmp, free ?? 0)
    }

    /// حذف الملفات المؤقتة (لا تتأثر ملفاتك ولا تنزيلاتك)
    func clearTemp() {
        for d in [fm.temporaryDirectory, fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]] {
            for u in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [] {
                // لا نحذف ذاكرة القرآن ولا صور الويدجت
                if u.lastPathComponent.hasPrefix("com.apple") { continue }
                try? fm.removeItem(at: u)
            }
        }
        touch()
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
