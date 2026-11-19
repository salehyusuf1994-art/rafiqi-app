import SwiftUI
import UserNotifications

// MARK: - قوائم تشغيل مخصّصة للملفات الصوتية

struct FilePlaylist: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var items: [String] = []   // مسارات نسبية داخل «ملفاتي»
}

@MainActor
final class FilePlaylists: ObservableObject {
    static let shared = FilePlaylists()
    @Published private(set) var all: [FilePlaylist] = []
    private let url: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = support.appendingPathComponent("file_playlists.json")
        if let d = try? Data(contentsOf: url), let a = try? JSONDecoder().decode([FilePlaylist].self, from: d) { all = a }
    }

    private func save() { if let d = try? JSONEncoder().encode(all) { try? d.write(to: url, options: .atomic) } }

    @discardableResult
    func create(_ name: String) -> UUID {
        let p = FilePlaylist(name: name.isEmpty ? L("قائمتي") : name)
        all.append(p); save(); return p.id
    }
    func delete(_ id: UUID) { all.removeAll { $0.id == id }; save() }
    func rename(_ id: UUID, _ name: String) { if let i = all.firstIndex(where: { $0.id == id }) { all[i].name = name; save() } }
    func add(_ urls: [URL], to id: UUID) {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        for u in urls { let k = FileStore.shared.key(u); if !all[i].items.contains(k) { all[i].items.append(k) } }
        save()
    }
    func move(_ id: UUID, from: IndexSet, to: Int) { if let i = all.firstIndex(where: { $0.id == id }) { all[i].items.move(fromOffsets: from, toOffset: to); save() } }
    func remove(_ id: UUID, at: IndexSet) { if let i = all.firstIndex(where: { $0.id == id }) { all[i].items.remove(atOffsets: at); save() } }

    /// يزيل من القائمة ما لم يعد موجودًا (فتطابق أرقام الصفوف عناصر القائمة عند الحذف والترتيب)
    func prune(_ id: UUID) {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        let keep = all[i].items.filter { FileManager.default.fileExists(atPath: FileStore.shared.url(forKey: $0).path) }
        if keep != all[i].items { all[i].items = keep; save() }
    }

    /// الملفات الموجودة فعلًا (المحذوفة أو المنقولة تُتجاهل)
    func urls(_ p: FilePlaylist) -> [URL] {
        p.items.map { FileStore.shared.url(forKey: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// اختيار قائمة لإضافة ملفات إليها
struct AddToPlaylistSheet: View {
    let urls: [URL]
    @ObservedObject private var lists = FilePlaylists.shared
    @Environment(\.dismiss) private var dismiss
    @State private var askNew = false
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                Button { name = ""; askNew = true } label: { Label("قائمة جديدة…", systemImage: "plus").foregroundStyle(Theme.gold) }
                ForEach(lists.all) { p in
                    Button { lists.add(urls, to: p.id); dismiss() } label: {
                        HStack { Badge(name: "music.note.list", size: 32); Text(verbatim: p.name).foregroundStyle(.white); Spacer()
                            Text(verbatim: itemsText(p.items.count)).font(Theme.f(.caption)).foregroundStyle(Theme.sub) }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .glassList()
            .navigationTitle("إضافة إلى قائمة تشغيل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
            .alert(L("قائمة تشغيل جديدة"), isPresented: $askNew) {
                TextField(L("اسم القائمة"), text: $name)
                Button(L("إنشاء")) { let id = lists.create(name); lists.add(urls, to: id); dismiss() }
                Button(L("إلغاء"), role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// قوائم التشغيل
struct PlaylistsView: View {
    @ObservedObject private var lists = FilePlaylists.shared
    @State private var askNew = false
    @State private var name = ""

    var body: some View {
        List {
            if lists.all.isEmpty {
                Text("لا توجد قوائم بعد. حدّد ملفات صوتية في «ملفاتي» ثم «المزيد» ← «إضافة إلى قائمة تشغيل».")
                    .font(Theme.f(.footnote)).foregroundStyle(Theme.sub).listRowBackground(Color.clear)
            }
            ForEach(lists.all) { p in
                NavigationLink { PlaylistDetail(id: p.id) } label: {
                    HStack(spacing: 12) {
                        Badge(name: "music.note.list", size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: p.name).foregroundStyle(.white)
                            Text(verbatim: itemsText(lists.urls(p).count)).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                        }
                    }
                }
                .swipeActions { Button(L("حذف"), role: .destructive) { lists.delete(p.id) } }
            }
            .listRowBackground(Theme.card)
        }
        .glassList()
        .navigationTitle("قوائم التشغيل")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { name = ""; askNew = true } label: { Image(systemName: "plus") } } }
        .alert(L("قائمة تشغيل جديدة"), isPresented: $askNew) {
            TextField(L("اسم القائمة"), text: $name)
            Button(L("إنشاء")) { lists.create(name) }
            Button(L("إلغاء"), role: .cancel) {}
        }
    }
}

struct PlaylistDetail: View {
    let id: UUID
    @ObservedObject private var lists = FilePlaylists.shared

    /// ملف داخل مجلد مقفل لم يُفتح بعد
    private func isLocked(_ u: URL) -> Bool { FileStore.shared.lockedAncestor(u.deletingLastPathComponent()) != nil }

    /// التشغيل: إن كان في القائمة ملفات من مجلدات مقفلة يُطلب التحقق مرة واحدة أولًا
    private func play(_ list: [URL], start: Int) {
        guard list.contains(where: isLocked) else { return AudioPlayer.shared.playFiles(list, start: start) }
        Task {
            guard await FileStore.authenticate(L("افتح المجلد المقفل")) else { return }
            let store = FileStore.shared
            for u in list {
                while let l = store.lockedAncestor(u.deletingLastPathComponent()) { store.unlocked.insert(store.key(l)) }
            }
            AudioPlayer.shared.playFiles(list, start: start)
        }
    }

    var body: some View {
        let p = lists.all.first { $0.id == id }
        let urls = p.map { lists.urls($0) } ?? []
        List {
            if !urls.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        Button { play(urls, start: 0) } label: {
                            Label("تشغيل", systemImage: "play.fill").font(Theme.f(.headline)).foregroundStyle(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 10).background(Capsule().fill(Theme.gold))
                        }
                        Button {
                            play(urls.shuffled(), start: 0)
                        } label: {
                            Label("عشوائي", systemImage: "shuffle").font(Theme.f(.headline)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 10).background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(Array(urls.enumerated()), id: \.offset) { i, u in
                    Button { play(urls, start: i) } label: {
                        HStack(spacing: 10) {
                            Text(verbatim: ar(i + 1)).font(Theme.f(.caption, .bold)).foregroundStyle(Theme.sub).frame(width: 24)
                            // اسم ملف المجلد المقفل لا يظهر قبل التحقق
                            if isLocked(u) {
                                Label("ملف في مجلد مقفل", systemImage: "lock.fill").foregroundStyle(Theme.sub).lineLimit(1)
                            } else {
                                Text(verbatim: u.deletingPathExtension().lastPathComponent).foregroundStyle(.white).lineLimit(1)
                            }
                        }
                    }
                }
                .onMove { lists.move(id, from: $0, to: $1) }
                .onDelete { lists.remove(id, at: $0) }
            } footer: {
                Text("اسحب للحذف من القائمة (يبقى الملف في «ملفاتي»)، أو اضغط «تعديل» لإعادة الترتيب.")
            }
            .listRowBackground(Theme.card)
        }
        .glassList()
        .navigationTitle(p?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { EditButton().tint(Theme.gold) }
        .onAppear { lists.prune(id) }
    }
}

// MARK: - تذكير بملف في وقت محدد

struct ReminderSheet: View {
    let item: FileItem
    let done: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date().addingTimeInterval(3600)
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: item.name).foregroundStyle(.white)
                    DatePicker(L("الوقت"), selection: $date, in: Date()...).tint(Theme.gold)
                    TextField(L("ملاحظة (اختياري)"), text: $note)
                }
                .listRowBackground(Theme.card)
            }
            .glassList()
            .navigationTitle("تذكير بالملف")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        Task {
                            // الإشعارات غير مسموحة: لا نعد بتذكير لن يصل
                            guard await Notify.askIfNeeded() else {
                                done(L("فعّل إشعارات رفيقي من إعدادات الجوال ليصلك التذكير."))
                                dismiss(); return
                            }
                            let c = UNMutableNotificationContent()
                            // ملف مقفل (أو «إدارة الملفات» مقفلة): لا يظهر اسمه ولا ملاحظته على شاشة القفل
                            let hidden = FileStore.shared.inVault(item.url) || FilePrefs.lockTab
                            c.title = hidden ? L("تذكير بملف") : LF("تذكير: %@", item.name)
                            c.body = hidden || note.isEmpty ? L("اضغط لفتح الملف في رفيقي.") : note
                            c.sound = .default
                            c.userInfo = ["file": FileStore.shared.key(item.url)]
                            let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: date)
                            let req = UNNotificationRequest(identifier: "file." + UUID().uuidString, content: c,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                            try? await UNUserNotificationCenter.current().add(req)
                            done(L("سيصلك التذكير في الوقت المحدد"))
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
