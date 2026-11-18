import SwiftUI
import UIKit

// MARK: - تنزيل التلاوات للاستماع بدون إنترنت (سورة أو المصحف كاملًا لكل قارئ)

@MainActor
final class QuranDownloads: ObservableObject {
    static let shared = QuranDownloads()

    /// تقدّم التنزيل الجاري لكل سورة (٠…١)، بمفتاح «قارئ/سورة»
    @Published private(set) var progress: [String: Double] = [:]
    /// القارئ الذي يُنزَّل مصحفه كاملًا الآن
    @Published private(set) var fullFor: Int? = nil
    @Published private(set) var fullDone = 0
    @Published private(set) var fullTotal = 0
    @Published private(set) var lastError: String? = nil
    /// يتغيّر عند أي إضافة أو حذف (لتحديث العلامات في الواجهة)
    @Published private(set) var version = 0

    /// محاولات إعادة التنزيل لكل سورة (مرة إضافية عند الفشل)
    private var retries: [String: Int] = [:]

    private init() {
        // المصحف الكامل الجاري يبقى معروفًا بعد إغلاق التطبيق (التنزيل يكمل في الخلفية)
        let d = UserDefaults.standard
        if d.object(forKey: "quran.full.for") != nil {
            fullFor = d.integer(forKey: "quran.full.for"); fullTotal = d.integer(forKey: "quran.full.total")
        }
        QuranBG.shared.reattach()
    }

    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("quran", isDirectory: true)
    }

    private static func folder(_ r: Reciter) -> URL { root.appendingPathComponent(String(r.id), isDirectory: true) }

    /// مسار السورة المنزّلة (موجودة أو لا)
    nonisolated static func file(_ r: Reciter, _ surah: Int) -> URL { file(id: r.id, surah) }
    nonisolated static func file(id: Int, _ surah: Int) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("quran/\(id)/" + String(format: "%03d.mp3", surah))
    }

    /// السورة منزّلة لهذا القارئ؟
    nonisolated static func local(_ r: Reciter, _ surah: Int) -> URL? {
        let u = file(r, surah)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    private func key(_ r: Reciter, _ s: Int) -> String { "\(r.id)/\(s)" }

    func isDownloaded(_ r: Reciter, _ s: Int) -> Bool { _ = version; return Self.local(r, s) != nil }
    func downloading(_ r: Reciter, _ s: Int) -> Double? { progress[key(r, s)] }

    /// عدد السور المنزّلة وحجمها لهذا القارئ
    func stats(_ r: Reciter) -> (count: Int, bytes: Int64) {
        _ = version
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.folder(r), includingPropertiesForKeys: [.fileSizeKey]) else { return (0, 0) }
        let mp3 = files.filter { $0.pathExtension == "mp3" }
        let bytes = mp3.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return (mp3.count, bytes)
    }

    /// السور المتوفرة عند القارئ
    func available(_ r: Reciter) -> [Int] { (1...114).filter { r.has($0) } }

    // ── تنزيل سورة (جلسة خلفية: يكمل حتى لو خرجت من التطبيق أو قفلت الجوال) ──
    func download(_ r: Reciter, _ s: Int) {
        let k = key(r, s)
        guard progress[k] == nil, Self.local(r, s) == nil, let url = r.url(s) else { return }
        progress[k] = 0
        lastError = nil
        prepareFolder(r.id)
        QuranBG.shared.start(url, key: k)
    }

    func cancel(_ r: Reciter, _ s: Int) {
        // إيقاف سورة أثناء تنزيل المصحف كاملًا = إيقاف التنزيل الكامل
        if fullFor == r.id { cancelAll(); return }
        let k = key(r, s)
        QuranBG.shared.cancel(key: k)
        progress[k] = nil
    }

    private func prepareFolder(_ id: Int) {
        var dir = Self.file(id: id, 1).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var rv = URLResourceValues(); rv.isExcludedFromBackup = true
        try? dir.setResourceValues(rv)
    }

    // ── أحداث الجلسة الخلفية ──
    func bgProgress(_ k: String, _ v: Double) {
        if progress[k] != nil || v < 1 { progress[k] = v }
    }

    func bgFinished(_ k: String, ok: Bool, url: URL?) {
        progress[k] = nil
        let parts = k.split(separator: "/").compactMap { Int($0) }
        let rid = parts.first ?? -1
        if ok {
            version += 1
            retries[k] = nil
            if fullFor == rid { fullDone = min(fullTotal, fullDone + 1) }
        } else if let url, (retries[k] ?? 0) < 1 {
            // محاولة ثانية
            retries[k, default: 0] += 1
            progress[k] = 0
            QuranBG.shared.start(url, key: k)
            return
        } else {
            retries[k] = nil
            lastError = Lang.isEN ? "Download failed. Check your connection." : "تعذّر التنزيل، تحقّق من الاتصال."
            if fullFor == rid { fullFailed += 1 }
        }
        // انتهى المصحف الكامل (نجاحًا أو بعد محاولة كل السور)
        if fullFor == rid, !progress.keys.contains(where: { $0.hasPrefix("\(rid)/") }) {
            endFull()
        }
    }

    /// المهام الجارية بعد إعادة فتح التطبيق
    func reattached(_ keys: [String]) {
        for k in keys where progress[k] == nil { progress[k] = 0 }
        if let f = fullFor, !keys.contains(where: { $0.hasPrefix("\(f)/") }) {
            // كل سور المصحف انتهت أثناء إغلاق التطبيق
            if let r = Reciters.cached.first(where: { $0.id == f }) { fullDone = fullTotal - available(r).filter { Self.local(r, $0) == nil }.count }
            endFull()
        }
        version += 1
    }

    private var fullFailed = 0
    private func endFull() {
        fullFor = nil
        UserDefaults.standard.removeObject(forKey: "quran.full.for")
        if fullFailed > 0 {
            lastError = Lang.isEN ? "Some surahs failed. Tap download again to retry." : "تعذّر تنزيل بعض السور. اضغط تنزيل مرة أخرى لإكمالها."
        }
        fullFailed = 0
    }

    // ── تنزيل المصحف كاملًا: كل السور تُطلب مرة واحدة في جلسة الخلفية ──
    func downloadAll(_ r: Reciter) {
        guard fullFor == nil else { return }
        let todo = available(r).filter { Self.local(r, $0) == nil }
        guard !todo.isEmpty else { return }
        fullFor = r.id; fullTotal = available(r).count; fullDone = fullTotal - todo.count; fullFailed = 0
        UserDefaults.standard.set(r.id, forKey: "quran.full.for")
        UserDefaults.standard.set(fullTotal, forKey: "quran.full.total")
        lastError = nil
        prepareFolder(r.id)
        for s in todo {
            guard let url = r.url(s) else { continue }
            let k = key(r, s)
            progress[k] = 0
            QuranBG.shared.start(url, key: k)
        }
    }

    func cancelAll() {
        QuranBG.shared.cancelAll()
        progress = [:]; retries = [:]
        fullFor = nil; fullFailed = 0
        UserDefaults.standard.removeObject(forKey: "quran.full.for")
    }

    // ── الحذف ──
    func delete(_ r: Reciter, _ s: Int) {
        try? FileManager.default.removeItem(at: Self.file(r, s))
        version += 1
    }

    func deleteAll(_ r: Reciter) {
        try? FileManager.default.removeItem(at: Self.folder(r))
        version += 1
    }
}

// MARK: - جلسة تنزيل في الخلفية للتلاوات (يكمل النظام التنزيل حتى بعد الخروج من التطبيق)

final class QuranBG: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = QuranBG()
    static let id = "app.rafiqi.quran.bg"
    /// يُستدعى بعد أن يوقظ النظام التطبيق لإنهاء التنزيلات
    var completion: (() -> Void)?

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier: Self.id)
        c.sessionSendsLaunchEvents = true
        c.isDiscretionary = false
        c.allowsCellularAccess = true
        c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    func start(_ url: URL, key: String) {
        let t = session.downloadTask(with: url)
        t.taskDescription = key + "|" + url.absoluteString
        t.resume()
    }

    func cancel(key: String) {
        session.getAllTasks { all in for t in all where t.taskDescription?.hasPrefix(key + "|") == true { t.cancel() } }
    }
    func cancelAll() { session.getAllTasks { all in all.forEach { $0.cancel() } } }

    /// بعد فتح التطبيق: نعرف ما زال يُنزَّل
    func reattach() {
        session.getAllTasks { all in
            let keys = all.filter { $0.state == .running || $0.state == .suspended }.compactMap { $0.taskDescription?.components(separatedBy: "|").first }
            DispatchQueue.main.async { MainActor.assumeIsolated { QuranDownloads.shared.reattached(keys) } }
        }
    }

    private func parse(_ t: URLSessionTask) -> (key: String, rid: Int, surah: Int, url: URL?)? {
        guard let d = t.taskDescription else { return nil }
        let parts = d.components(separatedBy: "|")
        let ks = parts[0].split(separator: "/").compactMap { Int($0) }
        guard ks.count == 2 else { return nil }
        return (parts[0], ks[0], ks[1], parts.count > 1 ? URL(string: parts[1]) : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let p = parse(downloadTask) else { return }
        let ok = ((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200) < 400
        var moved = false
        if ok {
            // يجب نقل الملف قبل الخروج من هذه الدالة
            let dest = QuranDownloads.file(id: p.rid, p.surah)
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            moved = (try? FileManager.default.moveItem(at: location, to: dest)) != nil
        }
        let key = p.key, url = p.url
        DispatchQueue.main.async { MainActor.assumeIsolated { QuranDownloads.shared.bgFinished(key, ok: moved, url: url) } }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0, let p = parse(downloadTask) else { return }
        let v = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let key = p.key
        DispatchQueue.main.async { MainActor.assumeIsolated { QuranDownloads.shared.bgProgress(key, v) } }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let p = parse(task) else { return }
        let cancelled = (error as? URLError)?.code == .cancelled
        let key = p.key, url = p.url
        DispatchQueue.main.async { MainActor.assumeIsolated {
            if cancelled { return }
            QuranDownloads.shared.bgFinished(key, ok: false, url: url)
        } }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            QuranBG.shared.completion?()
            QuranBG.shared.completion = nil
        }
    }
}

// MARK: - صفحة السور: تشغيل، وتنزيل سورة أو المصحف كاملًا

struct SurahsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let reciter: Reciter
    @ObservedObject private var p = AudioPlayer.shared
    @ObservedObject private var dl = QuranDownloads.shared
    @State private var q = ""
    @State private var onlyDownloaded = false
    /// عرض السور مقسّمة على الأجزاء
    @State private var byJuz = false
    @State private var confirmDelete = false

    var body: some View {
        let st = dl.stats(reciter)
        let avail = dl.available(reciter)
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.gold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reciter.name).font(Theme.title(17)).foregroundStyle(.white)
                            Text(verbatim: LF("منزّل %@ من %@ سورة", ar(st.count), ar(avail.count))
                                 + (st.bytes > 0 ? " · " + ByteCountFormatter.string(fromByteCount: st.bytes, countStyle: .file) : ""))
                                .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                        }
                        Spacer(minLength: 0)
                    }
                    if dl.fullFor == reciter.id {
                        ProgressView(value: Double(dl.fullDone), total: Double(max(1, dl.fullTotal))).tint(Theme.gold)
                        HStack {
                            Text(verbatim: LF("جارٍ تنزيل المصحف: %@ من %@", ar(dl.fullDone), ar(dl.fullTotal)))
                                .font(Theme.f(.caption)).foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            Button("إيقاف") { dl.cancelAll() }.font(Theme.f(.caption, .bold)).foregroundStyle(Theme.gold)
                        }
                    } else if st.count < avail.count {
                        Button { dl.downloadAll(reciter) } label: {
                            Label("تنزيل المصحف كاملًا للاستماع بدون إنترنت", systemImage: "square.and.arrow.down.on.square")
                                .font(Theme.f(.subheadline, .bold)).foregroundStyle(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Capsule().fill(Theme.gold))
                        }
                        .buttonStyle(.plain)
                        .disabled(dl.fullFor != nil)
                    } else {
                        Label("المصحف كاملًا منزّل لهذا القارئ", systemImage: "checkmark.seal.fill")
                            .font(Theme.f(.subheadline)).foregroundStyle(.green)
                    }
                    if st.count > 0 && dl.fullFor == nil {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("حذف تنزيلات هذا القارئ", systemImage: "trash").font(Theme.f(.caption))
                        }
                        .buttonStyle(.plain).foregroundStyle(.red.opacity(0.9))
                    }
                    if let e = dl.lastError { Text(verbatim: e).font(Theme.f(.caption)).foregroundStyle(.orange) }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("التنزيل يحفظ التلاوة في جوالك فتعمل بدون إنترنت، ويُستخدم الملف المنزّل تلقائيًا عند التشغيل.")
            }

            Section {
                Picker("", selection: $byJuz) { Text("السور").tag(false); Text("الأجزاء").tag(true) }
                    .pickerStyle(.segmented)
                Toggle("المنزّلة فقط", isOn: $onlyDownloaded).tint(Theme.gold)
                if !byJuz { ForEach(list(avail), id: \.self) { n in row(n) } }
            }
            if byJuz {
                // كل جزء بالسور التي تبدأ فيه
                let shown = list(avail)
                ForEach(1...30, id: \.self) { j in
                    let items = shown.filter { Surahs.juz(of: $0) == j }
                    if !items.isEmpty {
                        Section {
                            ForEach(items, id: \.self) { n in row(n) }
                        } header: {
                            let st = Surahs.juzStart[j - 1]
                            Text(verbatim: LF("الجزء %@", ar(j)) + " · " + LF("يبدأ من %@ آية %@", Surahs.name(st.0), ar(st.1)))
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .searchable(text: $q, prompt: "ابحث عن سورة")
        .navigationTitle("القرآن الكريم")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("حذف كل السور المنزّلة لهذا القارئ؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) { dl.deleteAll(reciter) }
        }
    }

    private func list(_ avail: [Int]) -> [Int] {
        let qq = q.trimmingCharacters(in: .whitespaces)
        return avail.filter { n in
            (qq.isEmpty || Surahs.name(n).contains(qq) || Surahs.ar[n - 1].contains(qq) || String(n) == qq || ar(n) == qq)
                && (!onlyDownloaded || dl.isDownloaded(reciter, n))
        }
    }

    private func row(_ n: Int) -> some View {
        let playing = p.state.source == .quran && p.state.surah == n
        return HStack(spacing: 12) {
            Button { AudioPlayer.shared.playQuran(n, reciter: reciter) } label: {
                HStack(spacing: 12) {
                    Text(ar(n)).font(Theme.f(.footnote).monospacedDigit()).foregroundStyle(Theme.sub).frame(width: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Surahs.name(n)).foregroundStyle(playing ? Theme.gold : .white)
                        Text(verbatim: Surahs.info(n)).font(Theme.f(.caption2)).foregroundStyle(Theme.sub)
                    }
                    if playing && p.state.playing {
                        Image(systemName: "waveform").symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                            .font(Theme.f(.caption)).foregroundStyle(Theme.gold)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            downloadButton(n)
        }
        .swipeActions {
            if dl.isDownloaded(reciter, n) {
                Button(role: .destructive) { dl.delete(reciter, n) } label: { Label("حذف", systemImage: "trash") }
            }
        }
    }

    @ViewBuilder private func downloadButton(_ n: Int) -> some View {
        if dl.isDownloaded(reciter, n) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if let v = dl.downloading(reciter, n) {
            Button { dl.cancel(reciter, n) } label: {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 2.5)
                    Circle().trim(from: 0, to: max(0.03, v)).stroke(Theme.gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "stop.fill").font(.system(size: 7)).foregroundStyle(Theme.gold)
                }
                .frame(width: 22, height: 22)
                .environment(\.layoutDirection, .leftToRight)
            }
            .buttonStyle(.borderless)
        } else {
            Button { dl.download(reciter, n) } label: {
                Image(systemName: "arrow.down.circle").font(.system(size: 20)).foregroundStyle(Theme.gold)
            }
            .buttonStyle(.borderless)
        }
    }
}
