import SwiftUI
import Security
import AMSMB2

// MARK: - الاتصال بالخوادم: مجلد مشارك في الكمبيوتر أو جهاز تخزين (SMB)، أو WebDAV

struct ServerInfo: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable { case smb, webdav }
    var id = UUID()
    var kind: Kind = .smb
    var name: String = ""
    var host: String = ""      // smb: 192.168.1.5 — webdav: https://example.com/dav
    var user: String = ""

    var title: String { name.isEmpty ? host : name }
}

enum Keychain {
    static func set(_ v: String, for id: UUID) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "rafiqi.servers", kSecAttrAccount as String: id.uuidString]
        SecItemDelete(q as CFDictionary)
        var a = q; a[kSecValueData as String] = Data(v.utf8); a[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(a as CFDictionary, nil)
    }
    static func get(_ id: UUID) -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "rafiqi.servers",
                                kSecAttrAccount as String: id.uuidString, kSecReturnData as String: true]
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return "" }
        return String(decoding: d, as: UTF8.self)
    }
    static func delete(_ id: UUID) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "rafiqi.servers", kSecAttrAccount as String: id.uuidString] as CFDictionary)
    }
}

@MainActor
final class ServerStore: ObservableObject {
    static let shared = ServerStore()
    @Published var all: [ServerInfo] = []
    private init() {
        all = (UserDefaults.standard.data(forKey: "servers")).flatMap { try? JSONDecoder().decode([ServerInfo].self, from: $0) } ?? []
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: "servers") }
    func upsert(_ s: ServerInfo, password: String) {
        if let i = all.firstIndex(where: { $0.id == s.id }) { all[i] = s } else { all.append(s) }
        Keychain.set(password, for: s.id)
        save()
    }
    func remove(_ s: ServerInfo) { all.removeAll { $0.id == s.id }; Keychain.delete(s.id); save() }
}

struct RemoteItem: Identifiable, Hashable {
    let path: String
    let name: String
    let isDir: Bool
    let size: Int64
    let date: Date?
    var id: String { path }
}

/// واجهة موحّدة للنوعين
protocol RemoteClient: AnyObject {
    func list(_ path: String) async throws -> [RemoteItem]
    func download(_ path: String, to: URL, progress: @escaping (Double) -> Void) async throws
    func upload(_ file: URL, to path: String) async throws
    func mkdir(_ path: String) async throws
    func delete(_ path: String) async throws
}

// MARK: SMB (مشاركة ويندوز/ماك/NAS)

final class SMBClient: RemoteClient {
    let mgr: SMB2Manager
    /// المسار الأول «/الاسم» هو المجلد المشارك
    private var share: String?

    init(_ s: ServerInfo, password: String) throws {
        var host = s.host.trimmingCharacters(in: .whitespaces)
        if !host.lowercased().hasPrefix("smb://") { host = "smb://" + host }
        guard let u = URL(string: host),
              let m = SMB2Manager(url: u, credential: URLCredential(user: s.user.isEmpty ? "guest" : s.user, password: password, persistence: .forSession)) else {
            throw ToolError.failed(L("عنوان الخادم غير صحيح."))
        }
        mgr = m
    }

    private func split(_ path: String) -> (String, String) {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let s = parts.first else { return ("", "/") }
        return (String(s), "/" + parts.dropFirst().joined(separator: "/"))
    }

    private func use(_ name: String) async throws {
        if share != name {
            if share != nil { try? await mgr.disconnectShare() }
            try await mgr.connectShare(name: name)
            share = name
        }
    }

    func list(_ path: String) async throws -> [RemoteItem] {
        let (s, inner) = split(path)
        if s.isEmpty {
            return try await mgr.listShares().map { RemoteItem(path: "/" + $0.name, name: $0.name, isDir: true, size: 0, date: nil) }
        }
        try await use(s)
        let items = try await mgr.contentsOfDirectory(atPath: inner)
        return items.compactMap { d in
            guard let name = d[.nameKey] as? String, !name.hasPrefix(".") else { return nil }
            let isDir = (d[.fileResourceTypeKey] as? URLFileResourceType) == .directory
            let size = (d[.fileSizeKey] as? NSNumber)?.int64Value ?? 0
            return RemoteItem(path: "/" + s + (inner == "/" ? "/" : inner + "/") + name, name: name, isDir: isDir, size: size,
                              date: d[.contentModificationDateKey] as? Date)
        }
    }

    func download(_ path: String, to: URL, progress: @escaping (Double) -> Void) async throws {
        let (s, inner) = split(path)
        try await use(s)
        try await mgr.downloadItem(atPath: inner, to: to, progress: { b, t in progress(t > 0 ? Double(b) / Double(t) : 0); return true })
    }

    func upload(_ file: URL, to path: String) async throws {
        let (s, inner) = split(path)
        try await use(s)
        try await mgr.uploadItem(at: file, toPath: inner, progress: { _ in true })
    }

    func mkdir(_ path: String) async throws { let (s, i) = split(path); try await use(s); try await mgr.createDirectory(atPath: i) }
    func delete(_ path: String) async throws { let (s, i) = split(path); try await use(s); try await mgr.removeItem(atPath: i) }
}

// MARK: WebDAV

final class DAVClient: NSObject, RemoteClient, XMLParserDelegate {
    let base: URL
    let auth: String

    init(_ s: ServerInfo, password: String) throws {
        var h = s.host.trimmingCharacters(in: .whitespaces)
        if !h.lowercased().hasPrefix("http") { h = "https://" + h }
        guard let u = URL(string: h.hasSuffix("/") ? h : h + "/") else { throw ToolError.failed(L("عنوان الخادم غير صحيح.")) }
        base = u
        auth = "Basic " + Data("\(s.user):\(password)".utf8).base64EncodedString()
    }

    private func url(_ path: String) -> URL {
        let p = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        return URL(string: p, relativeTo: base) ?? base
    }

    private func req(_ path: String, _ method: String) -> URLRequest {
        var r = URLRequest(url: url(path))
        r.httpMethod = method
        r.setValue(auth, forHTTPHeaderField: "Authorization")
        return r
    }

    private func check(_ resp: URLResponse) throws {
        guard let h = resp as? HTTPURLResponse else { return }
        if h.statusCode == 401 { throw ToolError.failed(L("اسم المستخدم أو كلمة المرور غير صحيحة.")) }
        if h.statusCode >= 400 { throw ToolError.failed(LF("رفض الخادم الطلب (%@).", ar(h.statusCode))) }
    }

    // تحليل ردّ PROPFIND
    private var cur: [String: String] = [:], text = "", rows: [[String: String]] = [], isCollection = false

    func list(_ path: String) async throws -> [RemoteItem] {
        var r = req(path.hasSuffix("/") ? path : path + "/", "PROPFIND")
        r.setValue("1", forHTTPHeaderField: "Depth")
        r.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        r.httpBody = Data(#"<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>"#.utf8)
        let (d, resp) = try await URLSession.shared.data(for: r)
        try check(resp)
        rows = []
        let p = XMLParser(data: d); p.shouldProcessNamespaces = true; p.delegate = self; p.parse()
        let selfPath = url(path).path
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return rows.compactMap { row in
            guard let href = row["href"], let full = URL(string: href, relativeTo: base) else { return nil }
            let p = (full.path as NSString).standardizingPath
            if p == (selfPath as NSString).standardizingPath { return nil }
            let name = (p as NSString).lastPathComponent
            guard !name.hasPrefix(".") else { return nil }
            let rel = String(p.dropFirst((base.path as NSString).standardizingPath.count))
            return RemoteItem(path: rel.hasPrefix("/") ? rel : "/" + rel, name: name, isDir: row["collection"] == "1",
                              size: Int64(row["getcontentlength"] ?? "") ?? 0, date: row["getlastmodified"].flatMap { df.date(from: $0) })
        }
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if e == "response" { cur = [:] }
        if e == "collection" { cur["collection"] = "1" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        if ["href", "getcontentlength", "getlastmodified"].contains(e) { cur[e] = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if e == "response" { rows.append(cur) }
    }

    func download(_ path: String, to: URL, progress: @escaping (Double) -> Void) async throws {
        let (tmp, resp) = try await URLSession.shared.download(for: req(path, "GET"))
        try check(resp)
        try? FileManager.default.removeItem(at: to)
        try FileManager.default.moveItem(at: tmp, to: to)
        progress(1)
    }

    func upload(_ file: URL, to path: String) async throws {
        let (_, resp) = try await URLSession.shared.upload(for: req(path, "PUT"), fromFile: file)
        try check(resp)
    }
    func mkdir(_ path: String) async throws { let (_, r) = try await URLSession.shared.data(for: req(path, "MKCOL")); try check(r) }
    func delete(_ path: String) async throws { let (_, r) = try await URLSession.shared.data(for: req(path, "DELETE")); try check(r) }
}

// MARK: - الواجهة

struct ServersView: View {
    @ObservedObject private var store = ServerStore.shared
    @State private var editing: ServerInfo?

    var body: some View {
        List {
            Section {
                ForEach(store.all) { s in
                    NavigationLink { RemoteBrowser(server: s, path: "/") } label: {
                        HStack(spacing: 12) {
                            Badge(name: s.kind == .smb ? "server.rack" : "globe", size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: s.title).foregroundStyle(.white)
                                Text(verbatim: (s.kind == .smb ? "SMB · " : "WebDAV · ") + s.host).font(Theme.f(.caption)).foregroundStyle(Theme.sub).lineLimit(1)
                            }
                        }
                    }
                    .swipeActions {
                        Button(L("حذف"), role: .destructive) { store.remove(s) }
                        Button(L("تعديل")) { editing = s }.tint(Theme.goldDeep)
                    }
                }
                Button { editing = ServerInfo() } label: { Label("إضافة خادم", systemImage: "plus.circle.fill").foregroundStyle(Theme.gold) }
            } footer: {
                Text("SMB: مجلد مشارك في كمبيوتر ويندوز أو ماك، أو جهاز تخزين شبكي (NAS) على نفس الواي فاي — اكتب عنوانه مثل 192.168.1.5. WebDAV: رابط الخادم كاملًا. تُحفظ كلمة المرور في سلسلة المفاتيح على جهازك فقط.")
            }
            .listRowBackground(Theme.card)
        }
        .glassList()
        .navigationTitle("الخوادم")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $editing) { s in ServerEditor(server: s) }
    }
}

struct ServerEditor: View {
    @State var server: ServerInfo
    @State private var password = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker(L("النوع"), selection: $server.kind) {
                    Text(verbatim: "SMB").tag(ServerInfo.Kind.smb)
                    Text(verbatim: "WebDAV").tag(ServerInfo.Kind.webdav)
                }
                .pickerStyle(.segmented)
                TextField(L("الاسم (اختياري)"), text: $server.name)
                TextField(server.kind == .smb ? L("العنوان، مثل 192.168.1.5") : L("رابط الخادم"), text: $server.host)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField(L("اسم المستخدم"), text: $server.user).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(L("كلمة المرور"), text: $password)
            }
            .glassList()
            .navigationTitle("خادم")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { ServerStore.shared.upsert(server, password: password); dismiss() }
                        .disabled(server.host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { password = Keychain.get(server.id) }
        }
    }
}

struct RemoteBrowser: View {
    let server: ServerInfo
    let path: String
    @State private var items: [RemoteItem] = []
    @State private var loading = true
    @State private var error: String?
    @State private var status: String?
    @State private var uploading = false
    @State private var askFolder = false
    @State private var folderName = ""
    @State private var client: RemoteClient?

    var body: some View {
        List {
            if let error {
                Text(verbatim: error).foregroundStyle(.orange).listRowBackground(Theme.card)
            }
            if let status {
                Text(verbatim: status).font(Theme.f(.footnote)).foregroundStyle(Theme.gold).listRowBackground(Color.clear)
            }
            ForEach(items) { it in
                if it.isDir {
                    NavigationLink { RemoteBrowser(server: server, path: it.path) } label: { row(it) }
                } else {
                    Button { Task { await fetch(it, open: true) } } label: { row(it) }
                        .swipeActions {
                            Button(L("تنزيل")) { Task { await fetch(it, open: false) } }.tint(Theme.goldDeep)
                            Button(L("حذف"), role: .destructive) { Task { try? await client?.delete(it.path); await load() } }
                        }
                }
            }
            .listRowBackground(Theme.card)
        }
        .overlay { if loading { ProgressView().tint(Theme.gold) } }
        .glassList()
        .navigationTitle(path == "/" ? server.title : (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if path != "/" || server.kind == .webdav {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { uploading = true } label: { Label("رفع ملفات إلى هنا", systemImage: "square.and.arrow.up") }
                        Button { folderName = ""; askFolder = true } label: { Label("مجلد جديد", systemImage: "folder.badge.plus") }
                    } label: { Image(systemName: "plus") }
                }
            }
        }
        .fileImporter(isPresented: $uploading, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r else { return }
            Task {
                for u in urls {
                    let ok = u.startAccessingSecurityScopedResource()
                    status = LF("يرفع «%@»…", u.lastPathComponent)
                    do { try await client?.upload(u, to: (path == "/" ? "" : path) + "/" + u.lastPathComponent) } catch { self.error = error.localizedDescription }
                    if ok { u.stopAccessingSecurityScopedResource() }
                }
                status = L("اكتمل الرفع")
                await load()
            }
        }
        .alert(L("مجلد جديد"), isPresented: $askFolder) {
            TextField(L("اسم المجلد"), text: $folderName)
            Button(L("إنشاء")) { Task { try? await client?.mkdir((path == "/" ? "" : path) + "/" + folderName); await load() } }
            Button(L("إلغاء"), role: .cancel) {}
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ it: RemoteItem) -> some View {
        HStack(spacing: 12) {
            Badge(name: it.isDir ? "folder" : FileKind.of(URL(fileURLWithPath: it.name), isDir: false).icon, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: it.name).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                if !it.isDir { Text(verbatim: sizeText(it.size)).font(Theme.f(.caption)).foregroundStyle(Theme.sub) }
            }
        }
    }

    private func connect() throws -> RemoteClient {
        if let client { return client }
        let pw = Keychain.get(server.id)
        let c: RemoteClient = server.kind == .smb ? try SMBClient(server, password: pw) : try DAVClient(server, password: pw)
        client = c
        return c
    }

    private func load() async {
        loading = true; error = nil
        do { items = try await connect().list(path).sorted { ($0.isDir ? 0 : 1, $0.name) < ($1.isDir ? 0 : 1, $1.name) } }
        catch { self.error = L("تعذّر الاتصال: ") + error.localizedDescription }
        loading = false
    }

    /// تنزيل إلى «ملفاتي ← من الخوادم ← اسم الخادم»
    private func fetch(_ it: RemoteItem, open: Bool) async {
        let store = FileStore.shared
        let dir = store.root.appendingPathComponent(L("من الخوادم"), isDirectory: true).appendingPathComponent(store.sanitize(server.title), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = store.unique(store.sanitize(it.name), in: dir)
        status = LF("ينزّل «%@»…", it.name)
        do {
            try await connect().download(it.path, to: dest) { p in Task { @MainActor in status = LF("ينزّل «%@»… %@٪", it.name, ar(Int(p * 100))) } }
            status = LF("حُفظ في «ملفاتي ← من الخوادم ← %@»", server.title)
            store.touch()
            if open { FileOpener.open(dest) }
        } catch {
            self.error = error.localizedDescription
            status = nil
        }
    }
}
