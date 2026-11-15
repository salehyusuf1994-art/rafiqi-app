import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - التنزيلات: من رابط مباشر، بالخلفية، مع الإيقاف والاستئناف

struct DLItem: Codable, Identifiable, Equatable {
    enum State: String, Codable { case queued, running, paused, done, failed }
    var id = UUID()
    var url: String
    var name: String
    var state: State = .queued
    var received: Int64 = 0
    var total: Int64 = 0
    var added = Date()
    var file: String? = nil       // المسار النسبي داخل «ملفاتي» بعد الاكتمال
    var error: String? = nil
    var headers: [String: String] = [:]

    var progress: Double { total > 0 ? min(1, Double(received) / Double(total)) : 0 }
}

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    static let sessionID = "app.hilal.widgets.downloads"

    @Published private(set) var items: [DLItem] = []
    /// سرعة كل تنزيل (بايت/ثانية)
    @Published private(set) var speed: [UUID: Double] = [:]
    var backgroundCompletion: (() -> Void)?

    private var session: URLSession!
    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var lastTick: [UUID: (Date, Int64)] = [:]
    private let maxActive = 3
    private let storeURL: URL
    private let resumeDir: URL

    private override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storeURL = support.appendingPathComponent("downloads.json")
        resumeDir = support.appendingPathComponent("resume", isDirectory: true)
        try? FileManager.default.createDirectory(at: resumeDir, withIntermediateDirectories: true)
        super.init()
        if let d = try? Data(contentsOf: storeURL), let a = try? JSONDecoder().decode([DLItem].self, from: d) { items = a }
        let cfg = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        cfg.sessionSendsLaunchEvents = true
        cfg.isDiscretionary = false
        cfg.allowsCellularAccess = true
        cfg.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
        // ربط المهام الجارية بعد إعادة تشغيل التطبيق
        session.getAllTasks { all in
            Task { @MainActor in
                let mgr = DownloadManager.shared
                for t in all {
                    guard let d = t as? URLSessionDownloadTask, let s = t.taskDescription, let id = UUID(uuidString: s) else { continue }
                    if mgr.items.contains(where: { $0.id == id }) { mgr.tasks[id] = d } else { d.cancel() }
                }
                // المهام التي كانت «جارية» ولم تعد موجودة: نكملها من جديد
                for i in mgr.items.indices where mgr.items[i].state == .running && mgr.tasks[mgr.items[i].id] == nil {
                    mgr.items[i].state = .queued
                }
                mgr.pump()
            }
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: storeURL, options: .atomic) }
    }

    private func index(_ id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    // MARK: إضافة

    /// يقبل الرابط مع ترويسات بصيغة «الرابط|Referer=…&User-Agent=…»
    @discardableResult
    func add(_ text: String, name: String? = nil, headers: [String: String] = [:]) -> Bool {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var hdrs = headers
        if let bar = raw.firstIndex(of: "|") {
            let opts = raw[raw.index(after: bar)...]
            raw = String(raw[..<bar])
            for p in opts.split(separator: "&") {
                let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { hdrs[kv[0]] = kv[1] }
            }
        }
        if !raw.lowercased().hasPrefix("http") { raw = "https://" + raw }
        guard let u = URL(string: raw) ?? URL(string: raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""),
              u.host != nil else { return false }
        let guess = name ?? Self.guessName(u)
        items.insert(DLItem(url: u.absoluteString, name: guess, headers: hdrs), at: 0)
        save()
        pump()
        return true
    }

    static func guessName(_ u: URL) -> String {
        let last = u.lastPathComponent.removingPercentEncoding ?? u.lastPathComponent
        if !last.isEmpty, last != "/", (1...5).contains((last as NSString).pathExtension.count) { return last }
        return (u.host ?? "download") + "-" + String(Int(Date().timeIntervalSince1970))
    }

    // MARK: التحكم

    /// يبدأ المهام المنتظرة حتى الحد الأقصى
    private func pump() {
        let active = items.filter { $0.state == .running }.count
        guard active < maxActive else { return }
        for i in items.indices.reversed() where items[i].state == .queued {
            if items.filter({ $0.state == .running }).count >= maxActive { break }
            start(i)
        }
    }

    private func start(_ i: Int) {
        let it = items[i]
        let resumeFile = resumeDir.appendingPathComponent(it.id.uuidString)
        let task: URLSessionDownloadTask
        if let data = try? Data(contentsOf: resumeFile) {
            task = session.downloadTask(withResumeData: data)
            try? FileManager.default.removeItem(at: resumeFile)
        } else if let u = URL(string: it.url) {
            var req = URLRequest(url: u)
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            for (k, v) in it.headers { req.setValue(v, forHTTPHeaderField: k) }
            task = session.downloadTask(with: req)
        } else {
            items[i].state = .failed; items[i].error = L("الرابط غير صالح."); save(); return
        }
        task.taskDescription = it.id.uuidString
        tasks[it.id] = task
        items[i].state = .running
        items[i].error = nil
        task.resume()
        save()
    }

    func pause(_ id: UUID) {
        guard let t = tasks[id] else { return }
        t.cancel(byProducingResumeData: { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                if let data { try? data.write(to: self.resumeDir.appendingPathComponent(id.uuidString)) }
                if let i = self.index(id) { self.items[i].state = .paused }
                self.tasks[id] = nil
                self.speed[id] = nil
                self.save()
                self.pump()
            }
        })
    }

    func resume(_ id: UUID) {
        guard let i = index(id) else { return }
        items[i].state = .queued
        save()
        pump()
    }

    func retry(_ id: UUID) {
        guard let i = index(id) else { return }
        items[i].received = 0
        items[i].state = .queued
        try? FileManager.default.removeItem(at: resumeDir.appendingPathComponent(id.uuidString))
        save()
        pump()
    }

    /// إزالة من القائمة (الملف المكتمل يبقى في «ملفاتي»)
    func remove(_ ids: Set<UUID>) {
        for id in ids {
            tasks[id]?.cancel()
            tasks[id] = nil
            try? FileManager.default.removeItem(at: resumeDir.appendingPathComponent(id.uuidString))
        }
        items.removeAll { ids.contains($0.id) }
        save()
        pump()
    }

    func clearFinished() { remove(Set(items.filter { $0.state == .done }.map(\.id))) }

    func pauseAll() { for it in items where it.state == .running { pause(it.id) } }
    func resumeAll() {
        for i in items.indices where items[i].state == .paused || items[i].state == .failed { items[i].state = .queued }
        save(); pump()
    }

    func fileURL(_ it: DLItem) -> URL? {
        guard let f = it.file else { return nil }
        let u = FileStore.shared.root.appendingPathComponent(f)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    // MARK: تسجيل ملف نُزّل من المتصفح مباشرة

    func recordFinished(name: String, url: String, file: URL) {
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        var it = DLItem(url: url, name: file.lastPathComponent, state: .done, received: size, total: size)
        it.file = FileStore.shared.key(file)
        items.insert(it, at: 0)
        save()
    }

    // MARK: إنهاء

    fileprivate func finished(_ id: UUID, location: URL, response: URLResponse?) {
        guard let i = index(id) else { return }
        // اسم الملف من الخادم إن وُجد
        var name = items[i].name
        if let s = response?.suggestedFilename, !s.isEmpty, s != "Unknown", (s as NSString).pathExtension.count > 0 { name = s }
        if (name as NSString).pathExtension.isEmpty, let mime = response?.mimeType,
           let ext = UTType(mimeType: mime)?.preferredFilenameExtension { name += "." + ext }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            items[i].state = .failed
            items[i].error = LF("رفض الخادم التنزيل (%@).", ar(http.statusCode))
            try? FileManager.default.removeItem(at: location)
            save(); pump(); return
        }
        let store = FileStore.shared
        let downloads = store.root.appendingPathComponent(L("التنزيلات"), isDirectory: true)
        try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let dir = store.destination(for: name, base: downloads, source: URL(string: items[i].url)?.host)
        let dest = store.unique(store.sanitize(name), in: dir)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            items[i].state = .done
            items[i].name = dest.lastPathComponent
            items[i].file = store.key(dest)
            let size = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? items[i].received
            items[i].received = size
            items[i].total = size
            store.touch()
            if FilePrefs.autoPhotos {
                let k = FileKind.of(dest, isDir: false)
                if k == .image || k == .video { Task { _ = await store.saveToPhotos([dest]) } }
            }
        } catch {
            items[i].state = .failed
            items[i].error = L("تعذّر حفظ الملف.")
        }
        tasks[id] = nil
        speed[id] = nil
        save()
        pump()
    }

    fileprivate func progress(_ id: UUID, received: Int64, total: Int64) {
        guard let i = index(id) else { return }
        items[i].received = received
        if total > 0 { items[i].total = total }
        let now = Date()
        if let (t, b) = lastTick[id] {
            let dt = now.timeIntervalSince(t)
            if dt >= 1 { speed[id] = Double(received - b) / dt; lastTick[id] = (now, received) }
        } else { lastTick[id] = (now, received) }
    }

    fileprivate func failed(_ id: UUID, error: Error?) {
        guard let i = index(id) else { return }
        tasks[id] = nil
        speed[id] = nil
        // الإيقاف المؤقت يصل هنا أيضًا بخطأ «أُلغي»: لا نعتبره فشلًا
        if let e = error as NSError?, e.code == NSURLErrorCancelled {
            if items[i].state == .running { items[i].state = .paused }
            if let data = e.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                try? data.write(to: resumeDir.appendingPathComponent(id.uuidString))
            }
        } else if let e = error as NSError? {
            if let data = e.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                try? data.write(to: resumeDir.appendingPathComponent(id.uuidString))
            }
            items[i].state = .failed
            items[i].error = e.code == NSURLErrorNotConnectedToInternet ? L("لا يوجد اتصال بالإنترنت.") : L("انقطع التنزيل. اضغط لإعادة المحاولة.")
        }
        save()
        pump()
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // يجب نقل الملف قبل الخروج من هذه الدالة
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: tmp)
        let resp = downloadTask.response
        guard let s = downloadTask.taskDescription, let id = UUID(uuidString: s) else { return }
        MainActor.assumeIsolated { DownloadManager.shared.finished(id, location: tmp, response: resp) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let s = downloadTask.taskDescription, let id = UUID(uuidString: s) else { return }
        MainActor.assumeIsolated { DownloadManager.shared.progress(id, received: totalBytesWritten, total: totalBytesExpectedToWrite) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let s = task.taskDescription, let id = UUID(uuidString: s) else { return }
        MainActor.assumeIsolated { DownloadManager.shared.failed(id, error: error) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            DownloadManager.shared.backgroundCompletion?()
            DownloadManager.shared.backgroundCompletion = nil
        }
    }
}

// MARK: - صفحة التنزيلات

struct DownloadsView: View {
    @ObservedObject private var dm = DownloadManager.shared
    @State private var link = ""
    @State private var bad = false
    var open: (URL) -> Void

    var body: some View {
        VStack(spacing: 14) {
            linkBar
            if UIPasteboard.general.hasURLs && link.isEmpty {
                Label("لديك رابط منسوخ. اضغط زر اللصق بجانب الخانة لتنزيله مباشرة.", systemImage: "doc.on.clipboard")
                    .font(Theme.f(.footnote)).foregroundStyle(Theme.gold).frame(maxWidth: .infinity, alignment: .leading)
            }
            if bad {
                Text("الرابط غير صالح. الصق رابطًا مباشرًا يبدأ بـ http أو https.")
                    .font(Theme.f(.footnote)).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if dm.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.gold.opacity(0.8))
                    Text("لا توجد تنزيلات").font(Theme.f(.headline)).foregroundStyle(.white)
                    Text("الصق رابط ملف مباشر (فيديو، صوت، صورة، PDF، ملف مضغوط…) واضغط زر التنزيل، أو نزّل من «المتصفح». يستمر التنزيل حتى لو خرجت من التطبيق.")
                        .font(Theme.f(.footnote)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
                }
                .padding(.vertical, 30).padding(.horizontal, 10)
                .glassCard(padding: 16)
            } else {
                HStack {
                    Text(LF("عدد التنزيلات: %@", ar(dm.items.count))).font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
                    Spacer()
                    Menu {
                        Button { dm.pauseAll() } label: { Label("إيقاف الكل مؤقتًا", systemImage: "pause") }
                        Button { dm.resumeAll() } label: { Label("استئناف الكل", systemImage: "play") }
                        Button(role: .destructive) { dm.clearFinished() } label: { Label("إزالة المكتملة من القائمة", systemImage: "checkmark.circle") }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundStyle(Theme.gold)
                    }
                }
                VStack(spacing: 10) {
                    ForEach(dm.items) { it in row(it) }
                }
            }
        }
    }

    private var linkBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "link").foregroundStyle(Theme.sub)
            TextField(L("رابط التحميل"), text: $link)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.URL).submitLabel(.go)
                .onSubmit(go)
            PasteButton(payloadType: String.self) { s in
                if let v = s.first { link = v; go() }
            }
            .labelStyle(.iconOnly).buttonBorderShape(.circle).tint(Theme.gold.opacity(0.25))
            Button(action: go) {
                Image(systemName: "arrow.down").font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 42, height: 42).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.gold))
            }
            .accessibilityLabel(L("تنزيل"))
        }
        .padding(.leading, 12).padding(.trailing, 5).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
    }

    private func go() {
        guard !link.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        bad = !dm.add(link)
        if !bad { link = "" }
    }

    @ViewBuilder private func row(_ it: DLItem) -> some View {
        let kind = FileKind.of(URL(fileURLWithPath: it.name), isDir: false)
        HStack(spacing: 12) {
            Badge(name: kind.icon, size: 40, active: it.state == .running)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: it.name).font(Theme.f(.subheadline, .medium)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                if it.state == .running || it.state == .paused || it.state == .queued {
                    ProgressView(value: it.progress).tint(Theme.gold)
                }
                HStack(spacing: 6) {
                    Text(statusText(it)).font(Theme.f(.caption, .bold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(statusColor(it).opacity(0.22)))
                        .foregroundStyle(statusColor(it))
                    Text(verbatim: sizeLine(it)).font(Theme.f(.caption)).foregroundStyle(Theme.sub).lineLimit(1)
                }
                if let e = it.error, it.state == .failed {
                    Text(verbatim: e).font(Theme.f(.caption)).foregroundStyle(.orange).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            controls(it)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            switch it.state {
            case .done: if let u = dm.fileURL(it) { open(u) }
            case .failed: dm.retry(it.id)
            case .paused: dm.resume(it.id)
            default: break
            }
        }
        .contextMenu {
            if it.state == .done, let u = dm.fileURL(it) {
                Button { open(u) } label: { Label("فتح", systemImage: "doc") }
                ShareLink(item: u) { Label("مشاركة", systemImage: "square.and.arrow.up") }
            }
            Button { UIPasteboard.general.string = it.url } label: { Label("نسخ الرابط", systemImage: "doc.on.doc") }
            Button(role: .destructive) { dm.remove([it.id]) } label: { Label("إزالة من القائمة", systemImage: "xmark") }
        }
    }

    @ViewBuilder private func controls(_ it: DLItem) -> some View {
        switch it.state {
        case .running, .queued:
            circle("pause.fill") { dm.pause(it.id) }
        case .paused:
            circle("play.fill") { dm.resume(it.id) }
        case .failed:
            circle("arrow.clockwise") { dm.retry(it.id) }
        case .done:
            circle("xmark") { dm.remove([it.id]) }
        }
    }

    private func circle(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private func statusText(_ it: DLItem) -> String {
        switch it.state {
        case .queued: return L("بالانتظار")
        case .running: return it.total > 0 ? ar("\(Int(it.progress * 100))%") : L("جارٍ التنزيل")
        case .paused: return L("متوقف")
        case .done: return L("اكتمل")
        case .failed: return L("فشل")
        }
    }

    private func statusColor(_ it: DLItem) -> Color {
        switch it.state {
        case .done: return Color(red: 0.45, green: 0.80, blue: 0.62)
        case .failed: return .orange
        case .running: return Theme.gold
        default: return .white.opacity(0.7)
        }
    }

    private func sizeLine(_ it: DLItem) -> String {
        if it.state == .done { return sizeText(it.total) }
        var s = sizeText(it.received)
        if it.total > 0 { s += " / " + sizeText(it.total) }
        if it.state == .running, let sp = dm.speed[it.id], sp > 0 { s += " · " + sizeText(Int64(sp)) + L("/ث") }
        return s
    }
}
