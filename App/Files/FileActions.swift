import SwiftUI
import AVFoundation

// MARK: - قائمة إجراءات الملف (مثل «حمّل»): أزرار كبيرة ثم أقسام الأدوات بحسب نوع الملف

enum FileAction {
    case open, move, copyTo, share, rename, delete, openIn, pin, duplicate, zip, unzip, photos, playlist, remind
    case restore, deleteForever
    case color(String)
    case lock(Bool)
    case tool(ToolKind)
}

struct FileActionsSheet: View {
    let item: FileItem
    let inTrash: Bool
    let run: (FileAction) -> Void
    @ObservedObject private var store = FileStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if inTrash {
                        group([
                            row("arrow.uturn.backward", L("استرجاع")) { run(.restore) },
                            row("trash", L("حذف نهائي"), destructive: true) { run(.deleteForever) },
                        ])
                    } else {
                        bigButtons
                        group(generalRows)
                        if item.isDir { folderSection }
                        ForEach(ToolKind.sections(for: item), id: \.0) { sec in
                            let tools = sec.1
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: sec.0).font(Theme.f(.footnote, .bold)).foregroundStyle(Theme.sub).padding(.horizontal, 6)
                                group(tools.map { t in row(t.icon, t.title) { run(.tool(t)) } })
                            }
                        }
                        group([row("trash", L("حذف"), destructive: true) { run(.delete) }])
                    }
                }
                .padding(16)
            }
            .background(AppBackground())
            .hiddenNavBar()
            .sheet(isPresented: $showInfo) { FileInfoView(item: item).presentationDetents([.medium, .large]) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            FileThumb(item: item, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.name).font(Theme.f(.headline)).foregroundStyle(.white).lineLimit(2)
                FileSubtitle(item: item).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 0)
            CircleButton(icon: "xmark", size: 38) { dismiss() }
        }
    }

    private var bigButtons: some View {
        HStack(spacing: 10) {
            big("arrow.up.and.down.and.arrow.left.and.right", L("نقل")) { run(.move) }
            if !item.isDir { big("square.and.arrow.up", L("مشاركة")) { run(.share) } }
            big("pencil", L("إعادة التسمية")) { run(.rename) }
            big("doc.on.doc", L("نسخ إلى")) { run(.copyTo) }
        }
    }

    private func big(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Badge(name: icon, size: 50)
                Text(verbatim: title).font(Theme.f(.caption, .medium)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressStyle())
    }

    private var generalRows: [AnyView] {
        var r: [AnyView] = []
        if !item.isDir { r.append(row("arrow.up.forward.app", L("فتح باستخدام")) { run(.openIn) }) }
        r.append(row(store.isPinned(item.url) ? "pin.slash" : "pin", store.isPinned(item.url) ? L("إلغاء التثبيت") : L("تثبيت في الأعلى")) { run(.pin) })
        r.append(row("plus.square.on.square", L("إنشاء نسخة")) { run(.duplicate) })
        if item.kind == .archive && item.ext == "zip" { r.append(row("doc.zipper", L("فك الضغط")) { run(.unzip) }) }
        else { r.append(row("doc.zipper", L("ضغط (ZIP)")) { run(.zip) }) }
        if item.kind == .image || item.kind == .video { r.append(row("square.and.arrow.down", L("حفظ في الصور")) { run(.photos) }) }
        if item.kind == .audio { r.append(row("music.note.list", L("إضافة إلى قائمة تشغيل")) { run(.playlist) }) }
        r.append(row("bell", L("تذكير بهذا الملف")) { run(.remind) })
        r.append(row("info.circle", L("معلومات")) { showInfo = true })
        return r
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("المجلد").font(Theme.f(.footnote, .bold)).foregroundStyle(Theme.sub).padding(.horizontal, 6)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Badge(name: "paintpalette", size: 32)
                    Text("لون المجلد").font(Theme.f(.body)).foregroundStyle(.white)
                    Spacer()
                    ForEach(FileStore.folderColors, id: \.0) { c in
                        Button { run(.color(c.0)) } label: {
                            Circle().fill(c.1).frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(.white, lineWidth: store.color(item.url) == c.1 ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                Divider().overlay(Theme.stroke)
                row(store.isLocked(item.url) ? "lock.open" : "lock", store.isLocked(item.url) ? L("إلغاء قفل المجلد") : L("قفل المجلد ببصمة الوجه")) {
                    run(.lock(!store.isLocked(item.url)))
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
        }
    }

    private func row(_ icon: String, _ title: String, destructive: Bool = false, _ action: @escaping () -> Void) -> AnyView {
        AnyView(Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(destructive ? Color.red : Theme.gold).frame(width: 32)
                Text(verbatim: title).font(Theme.f(.body)).foregroundStyle(destructive ? Color.red : .white)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain))
    }

    private func group(_ rows: [AnyView]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                r
                if i < rows.count - 1 { Divider().overlay(Theme.stroke).padding(.leading, 56) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
    }
}

// MARK: - معلومات الملف

struct FileInfoView: View {
    let item: FileItem
    @State private var extra: [(String, String)] = []
    @State private var size: Int64 = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    line(L("الاسم"), item.name)
                    line(L("النوع"), item.isDir ? L("مجلد") : (item.ext.isEmpty ? item.kind.title : item.ext.uppercased()))
                    line(L("الحجم"), sizeText(item.isDir ? size : item.size))
                    if item.isDir { line(L("العناصر"), itemsText(FileStore.shared.count(item.url))) }
                    line(L("تاريخ الإنشاء"), item.created.formatted(date: .long, time: .shortened))
                    line(L("آخر تعديل"), item.modified.formatted(date: .long, time: .shortened))
                    ForEach(extra, id: \.0) { line($0.0, $0.1) }
                    line(L("المكان"), FileStore.shared.key(item.url.deletingLastPathComponent()).isEmpty ? L("ملفاتي") : L("ملفاتي") + FileStore.shared.key(item.url.deletingLastPathComponent()))
                }
                .listRowBackground(Theme.card)
            }
            .glassList()
            .navigationTitle("معلومات")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(verbatim: k).foregroundStyle(Theme.sub)
            Spacer(minLength: 12)
            Text(verbatim: v).foregroundStyle(.white).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(Theme.f(.subheadline))
    }

    private func load() async {
        if item.isDir { let u = item.url; size = await Task.detached { FileStore.folderSizeSync(u) }.value }
        var e: [(String, String)] = []
        if item.kind == .video || item.kind == .audio {
            let a = AVURLAsset(url: item.url)
            if let d = try? await a.load(.duration), d.seconds.isFinite { e.append((L("المدة"), durationText(d.seconds))) }
            if let v = try? await a.loadTracks(withMediaType: .video).first, let n = try? await v.load(.naturalSize), let t = try? await v.load(.preferredTransform) {
                let r = CGRect(origin: .zero, size: n).applying(t)
                e.append((L("الأبعاد"), ar("\(Int(abs(r.width)))×\(Int(abs(r.height)))")))
                if let fps = try? await v.load(.nominalFrameRate), fps > 0 { e.append((L("الإطارات"), ar(String(Int(fps.rounded()))) + " fps")) }
            }
        } else if item.kind == .image, let img = UIImage(contentsOfFile: item.url.path) {
            e.append((L("الأبعاد"), ar("\(Int(img.size.width * img.scale))×\(Int(img.size.height * img.scale))")))
        }
        extra = e
    }
}
