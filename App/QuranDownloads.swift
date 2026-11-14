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

    private var fullTask: Task<Void, Never>?
    private var tasks: [String: Task<Void, Never>] = [:]

    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("quran", isDirectory: true)
    }

    private static func folder(_ r: Reciter) -> URL { root.appendingPathComponent(String(r.id), isDirectory: true) }

    /// مسار السورة المنزّلة (موجودة أو لا)
    nonisolated static func file(_ r: Reciter, _ surah: Int) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("quran/\(r.id)/" + String(format: "%03d.mp3", surah))
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

    // ── تنزيل سورة ──
    func download(_ r: Reciter, _ s: Int) {
        let k = key(r, s)
        guard tasks[k] == nil, progress[k] == nil, Self.local(r, s) == nil else { return }
        progress[k] = 0
        tasks[k] = Task { [weak self] in
            await self?.fetch(r, s)
            self?.tasks[k] = nil
        }
    }

    func cancel(_ r: Reciter, _ s: Int) {
        // إيقاف سورة أثناء تنزيل المصحف كاملًا = إيقاف التنزيل الكامل
        if fullFor == r.id && tasks[key(r, s)] == nil { cancelAll(); return }
        let k = key(r, s)
        tasks[k]?.cancel(); tasks[k] = nil
        progress[k] = nil
    }

    /// ينزّل ملفًا واحدًا مع التقدّم، ويحفظه بعيدًا عن نسخ iCloud الاحتياطي
    @discardableResult
    private func fetch(_ r: Reciter, _ s: Int) async -> Bool {
        let k = key(r, s)
        guard let url = r.url(s) else { progress[k] = nil; return false }
        // يكمل قليلًا في الخلفية إن خرجت من التطبيق
        final class BG: @unchecked Sendable { var id = UIBackgroundTaskIdentifier.invalid }
        let bg = BG()
        bg.id = UIApplication.shared.beginBackgroundTask(withName: "quran-\(k)") {
            MainActor.assumeIsolated {
                if bg.id != .invalid { UIApplication.shared.endBackgroundTask(bg.id); bg.id = .invalid }
            }
        }
        defer { if bg.id != .invalid { UIApplication.shared.endBackgroundTask(bg.id); bg.id = .invalid } }
        let dest = Self.file(r, s)
        progress[k] = progress[k] ?? 0
        do {
            var dir = dest.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var rv = URLResourceValues(); rv.isExcludedFromBackup = true
            try? dir.setResourceValues(rv)
            try await Self.transfer(url, to: dest) { [weak self] v in
                Task { @MainActor in if self?.progress[k] != nil { self?.progress[k] = v } }
            }
            progress[k] = nil
            version += 1
            return true
        } catch {
            progress[k] = nil
            try? FileManager.default.removeItem(at: dest)
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                lastError = Lang.isEN ? "Download failed. Check your connection." : "تعذّر التنزيل، تحقّق من الاتصال."
            }
            return false
        }
    }

    /// تنزيل إلى ملف مؤقت ثم نقله (لا يُحمَّل الملف كله في الذاكرة)، مع التقدّم والإلغاء
    private nonisolated static func transfer(_ url: URL, to dest: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        final class Box: @unchecked Sendable { var task: URLSessionDownloadTask?; var obs: NSKeyValueObservation?; var last = -1.0 }
        let box = Box()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                let t = URLSession.shared.downloadTask(with: url) { tmp, response, error in
                    box.obs = nil
                    if let error { c.resume(throwing: error); return }
                    guard let tmp, ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400 else {
                        c.resume(throwing: URLError(.badServerResponse)); return
                    }
                    do {
                        try? FileManager.default.removeItem(at: dest)
                        try FileManager.default.moveItem(at: tmp, to: dest)
                        c.resume()
                    } catch { c.resume(throwing: error) }
                }
                box.obs = t.progress.observe(\.fractionCompleted) { pr, _ in
                    let v = pr.fractionCompleted
                    if v - box.last >= 0.01 { box.last = v; progress(v) }
                }
                box.task = t
                t.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    // ── تنزيل المصحف كاملًا ──
    func downloadAll(_ r: Reciter) {
        guard fullTask == nil else { return }
        let todo = available(r).filter { Self.local(r, $0) == nil }
        fullFor = r.id; fullTotal = available(r).count; fullDone = fullTotal - todo.count
        lastError = nil
        fullTask = Task { [weak self] in
            for s in todo {
                guard let self, !Task.isCancelled else { break }
                // محاولتان لكل سورة
                var ok = await self.fetch(r, s)
                if !ok && !Task.isCancelled { ok = await self.fetch(r, s) }
                if ok { self.fullDone += 1 }
            }
            self?.fullTask = nil
            self?.fullFor = nil
        }
    }

    func cancelAll() {
        fullTask?.cancel(); fullTask = nil; fullFor = nil
        for t in tasks.values { t.cancel() }
        tasks = [:]; progress = [:]
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

// MARK: - صفحة السور: تشغيل، وتنزيل سورة أو المصحف كاملًا

struct SurahsView: View {
    let reciter: Reciter
    @ObservedObject private var p = AudioPlayer.shared
    @ObservedObject private var dl = QuranDownloads.shared
    @State private var q = ""
    @State private var onlyDownloaded = false
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
                                .font(.caption).foregroundStyle(Theme.sub)
                        }
                        Spacer(minLength: 0)
                    }
                    if dl.fullFor == reciter.id {
                        ProgressView(value: Double(dl.fullDone), total: Double(max(1, dl.fullTotal))).tint(Theme.gold)
                        HStack {
                            Text(verbatim: LF("جارٍ تنزيل المصحف: %@ من %@", ar(dl.fullDone), ar(dl.fullTotal)))
                                .font(.caption).foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            Button("إيقاف") { dl.cancelAll() }.font(.caption.bold()).foregroundStyle(Theme.gold)
                        }
                    } else if st.count < avail.count {
                        Button { dl.downloadAll(reciter) } label: {
                            Label("تنزيل المصحف كاملًا للاستماع بدون إنترنت", systemImage: "square.and.arrow.down.on.square")
                                .font(.subheadline.bold()).foregroundStyle(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Capsule().fill(Theme.gold))
                        }
                        .buttonStyle(.plain)
                        .disabled(dl.fullFor != nil)
                    } else {
                        Label("المصحف كاملًا منزّل لهذا القارئ", systemImage: "checkmark.seal.fill")
                            .font(.subheadline).foregroundStyle(.green)
                    }
                    if st.count > 0 && dl.fullFor == nil {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("حذف تنزيلات هذا القارئ", systemImage: "trash").font(.caption)
                        }
                        .buttonStyle(.plain).foregroundStyle(.red.opacity(0.9))
                    }
                    if let e = dl.lastError { Text(verbatim: e).font(.caption).foregroundStyle(.orange) }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("التنزيل يحفظ التلاوة في جوالك فتعمل بدون إنترنت، ويُستخدم الملف المنزّل تلقائيًا عند التشغيل.")
            }

            Section {
                Toggle("المنزّلة فقط", isOn: $onlyDownloaded).tint(Theme.gold)
                ForEach(list(avail), id: \.self) { n in row(n) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .searchable(text: $q, prompt: "ابحث عن سورة")
        .navigationTitle("القرآن الكريم")
        .navigationBarTitleDisplayMode(.inline)
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
                    Text(ar(n)).font(.footnote.monospacedDigit()).foregroundStyle(Theme.sub).frame(width: 30)
                    Text(Surahs.name(n)).foregroundStyle(playing ? Theme.gold : .white)
                    if playing && p.state.playing {
                        Image(systemName: "waveform").symbolEffect(.variableColor.iterative, options: .repeating)
                            .font(.caption).foregroundStyle(Theme.gold)
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
