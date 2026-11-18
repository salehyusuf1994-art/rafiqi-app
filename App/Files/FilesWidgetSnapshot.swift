import SwiftUI
import WidgetKit
import QuickLookThumbnailing

private struct Found: Sendable { let url: URL; let name: String; let kind: String; let rel: String; let date: Double }

/// لقطة «آخر الملفات» و«المساحة» لويدجت الأدوات.
/// الويدجت لا تقرأ مجلد التطبيق، فيكتب التطبيق عند ذهابه للخلفية قائمة صغيرة وصورًا مصغّرة في المجلد المشترك.
/// الخصوصية: إذا كانت «إدارة الملفات» مقفلة لا تُكتب أسماء ولا صور، والمجلدات المقفلة ومحتواها لا تدخل أبدًا.
@MainActor
enum FilesWidgetSnapshot {
    private static var running = false

    static func write() {
        guard !running else { return }
        running = true
        // مهلة خلفية من النظام حتى تكتمل الكتابة بعد الخروج من التطبيق
        let bg = KeepAwake.Background("rafiqi.files.snapshot")
        let store = FileStore.shared
        let root = store.root, trash = store.trash
        let lockedKeys = store.meta.locked
        let tabLocked = FilePrefs.lockTab
        Task.detached(priority: .utility) {
            var snap = WFilesSnap()
            snap.locked = tabLocked
            snap.t = Date().timeIntervalSince1970
            let (files, bytes) = scan(root: root, trash: trash, lockedKeys: lockedKeys)
            snap.rafiqiBytes = bytes
            if !tabLocked {
                var out: [WFile] = []
                for (i, f) in files.prefix(4).enumerated() {
                    var w = WFile(name: f.name, kind: f.kind, rel: f.rel, date: f.date, thumb: nil)
                    if f.kind == "image" || f.kind == "video" || f.kind == "document" {
                        w.thumb = await thumbnail(f.url, index: i)
                    }
                    out.append(w)
                }
                snap.files = out
            }
            // الصور القديمة تُحذف إذا قُفل التبويب
            if tabLocked, let dir = WFilesStore.dir { try? FileManager.default.removeItem(at: dir) }
            let final = snap
            await MainActor.run {
                WFilesStore.save(final)
                RafiqiKinds.reload()
                running = false
                bg.finish()
            }
        }
    }

    /// أحدث الملفات (بدون المجلدات المخفية والمقفلة والسلة) ومجموع حجم «ملفاتي»
    nonisolated private static func scan(root: URL, trash: URL, lockedKeys: Set<String>) -> ([Found], Int64) {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return ([], 0) }
        var found: [Found] = [], total: Int64 = 0
        for case let u as URL in en {
            let p = u.standardizedFileURL.path
            let rel = p.hasPrefix(rootPath) ? String(p.dropFirst(rootPath.count)) : p
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isDirectory == true {
                if u.standardizedFileURL == trash.standardizedFileURL || lockedKeys.contains(rel) { en.skipDescendants() }
                continue
            }
            total += Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
            let kind = FileKind.of(u, isDir: false).rawValue
            found.append(Found(url: u, name: u.deletingPathExtension().lastPathComponent, kind: kind,
                               rel: rel.hasPrefix("/") ? String(rel.dropFirst()) : rel,
                               date: (v.contentModificationDate ?? .distantPast).timeIntervalSince1970))
        }
        found.sort { $0.date > $1.date }
        return (found, total)
    }

    /// صورة مصغّرة صغيرة (١٢٠ نقطة) بصيغة JPEG في المجلد المشترك
    nonisolated private static func thumbnail(_ url: URL, index: Int) async -> String? {
        guard let dir = WFilesStore.dir else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 120, height: 120), scale: 2, representationTypes: .thumbnail)
        guard let r = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req),
              let data = r.uiImage.jpegData(compressionQuality: 0.7) else { return nil }
        let name = "t\(index).jpg"
        do { try data.write(to: dir.appendingPathComponent(name), options: .atomic) } catch { return nil }
        return name
    }
}
