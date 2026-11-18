import SwiftUI
import CryptoKit

// MARK: - تحليل المساحة: التوزيع حسب النوع، وأكبر الملفات، والملفات المكررة

struct StorageView: View {
    @ObservedObject private var store = FileStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var byKind: [(FileKind, Int64, Int)] = []
    @State private var largest: [FileItem] = []
    @State private var dups: [[FileItem]] = []
    @State private var scanning = true
    @State private var total: Int64 = 0

    var body: some View {
        NavigationStack {
            List {
                if scanning {
                    HStack { Spacer(); ProgressView().tint(Theme.gold); Text("جارٍ التحليل…").foregroundStyle(Theme.sub); Spacer() }
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        bar
                        ForEach(byKind, id: \.0) { e in
                            HStack(spacing: 12) {
                                Badge(name: e.0.icon, size: 32)
                                Circle().fill(e.0.storageColor).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: e.0.title).foregroundStyle(.white)
                                    Text(verbatim: itemsText(e.2)).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                                }
                                Spacer()
                                Text(verbatim: sizeText(e.1)).foregroundStyle(Theme.sub)
                            }
                        }
                    } header: { Text(LF("المجموع: %@", sizeText(total))) }
                    .listRowBackground(Theme.card)

                    if !dups.isEmpty {
                        Section {
                            ForEach(dups, id: \.first!.url) { group in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(LF("%@ نسخ متطابقة · %@", ar(group.count), sizeText(group[0].size))).font(Theme.f(.caption, .bold)).foregroundStyle(Theme.gold)
                                    ForEach(group) { f in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(verbatim: f.name).font(Theme.f(.footnote)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                                                let folder = store.key(f.url.deletingLastPathComponent())
                                                Text(verbatim: folder.isEmpty ? L("ملفاتي") : L("ملفاتي") + " ‹ " + folder.split(separator: "/").joined(separator: " ‹ "))
                                                    .font(Theme.f(.caption)).foregroundStyle(Theme.sub).lineLimit(1).truncationMode(.head)
                                            }
                                            Spacer()
                                            if f.url != group[0].url {
                                                Button(L("حذف")) { store.moveToTrash([f.url]); Task { await scan() } }
                                                    .font(Theme.f(.footnote, .bold)).foregroundStyle(.red).buttonStyle(.borderless)
                                            }
                                        }
                                    }
                                }
                            }
                            Button(L("حذف كل النسخ المكررة (تبقى نسخة واحدة)"), role: .destructive) {
                                store.moveToTrash(dups.flatMap { $0.dropFirst().map(\.url) })
                                Task { await scan() }
                            }
                        } header: { Text("الملفات المكررة") } footer: { Text("تُنقل النسخ المحذوفة إلى السلة، ويمكنك استرجاعها خلال ٣٠ يومًا.") }
                        .listRowBackground(Theme.card)
                    }

                    Section {
                        ForEach(largest) { f in
                            Button {
                                // الصوت يُشغَّل في المشغّل المصغّر أسفل الشاشة، فتُغلق هذه الصفحة ليظهر
                                if FileKind.of(f.url, isDir: false) == .audio {
                                    dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { FileOpener.open(f.url) }
                                } else { FileOpener.open(f.url) }
                            } label: {
                                HStack(spacing: 12) {
                                    FileThumb(item: f, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: f.name).font(Theme.f(.subheadline)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                                        let folder = store.key(f.url.deletingLastPathComponent())
                                        Text(verbatim: folder.isEmpty ? L("ملفاتي") : L("ملفاتي") + " ‹ " + folder.split(separator: "/").joined(separator: " ‹ "))
                                            .font(Theme.f(.caption)).foregroundStyle(Theme.sub).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(verbatim: sizeText(f.size)).font(Theme.f(.footnote, .bold)).foregroundStyle(Theme.gold)
                                }
                            }
                            .swipeActions { Button(L("حذف"), role: .destructive) { store.moveToTrash([f.url]); Task { await scan() } } }
                        }
                    } header: { Text("أكبر الملفات") }
                    .listRowBackground(Theme.card)
                }
            }
            .glassList()
            .navigationTitle("تحليل المساحة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
            .task { await scan() }
        }
    }

    private var bar: some View {
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(Array(byKind.enumerated()), id: \.offset) { i, e in
                    Rectangle().fill(e.0.storageColor)
                        .frame(width: max(2, g.size.width * CGFloat(Double(e.1) / Double(max(1, total)))))
                }
            }
        }
        .frame(height: 10).clipShape(Capsule())
    }

    private func scan() async {
        scanning = true
        let root = store.root, trash = store.trash
        let r = await Task.detached { () -> ([(FileKind, Int64, Int)], [FileItem], [[FileItem]], Int64) in
            let fm = FileManager.default
            var files: [FileItem] = []
            if let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey], options: [.skipsHiddenFiles]) {
                while let u = e.nextObject() as? URL {
                    if FileStore.isInside(u, trash) { continue }
                    let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey])
                    if v?.isDirectory == true { continue }
                    files.append(FileItem(url: u, name: u.lastPathComponent, isDir: false, size: Int64(v?.fileSize ?? 0),
                                          modified: v?.contentModificationDate ?? Date(), created: v?.creationDate ?? Date(),
                                          kind: FileKind.of(u, isDir: false)))
                }
            }
            var kinds: [FileKind: (Int64, Int)] = [:]
            for f in files { let c = kinds[f.kind] ?? (0, 0); kinds[f.kind] = (c.0 + f.size, c.1 + 1) }
            let byKind = kinds.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.1 > $1.1 }
            let largest = Array(files.sorted { $0.size > $1.size }.prefix(30))
            // المكررات: نفس الحجم ثم نفس البصمة
            var bySize: [Int64: [FileItem]] = [:]
            for f in files where f.size > 0 { bySize[f.size, default: []].append(f) }
            var dups: [[FileItem]] = []
            for (_, g) in bySize where g.count > 1 {
                var byHash: [String: [FileItem]] = [:]
                for f in g {
                    guard let h = try? FileHandle(forReadingFrom: f.url) else { continue }
                    var hasher = SHA256()
                    while let d = try? h.read(upToCount: 1 << 20), !d.isEmpty { hasher.update(data: d) }
                    try? h.close()
                    let key = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                    byHash[key, default: []].append(f)
                }
                for (_, same) in byHash where same.count > 1 { dups.append(same.sorted { $0.created < $1.created }) }
            }
            return (byKind, largest, dups, files.reduce(0) { $0 + $1.size })
        }.value
        byKind = r.0; largest = r.1; dups = r.2; total = r.3
        scanning = false
    }
}

extension FileKind {
    /// لون كل نوع في شريط المساحة (مثل إعدادات الجوال)
    var storageColor: Color {
        switch self {
        case .image: return Theme.gold
        case .video: return Theme.teal
        case .audio: return Theme.violet
        case .document: return Color(red: 0.35, green: 0.58, blue: 0.95)
        case .archive: return Color(red: 0.95, green: 0.55, blue: 0.30)
        case .folder, .other: return Color.white.opacity(0.45)
        }
    }
}
