import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - فحص الرابط قبل التنزيل: نوعه وحجمه وجوداته، ثم خيارات التنزيل المناسبة

/// المعالجة بعد اكتمال التنزيل
enum PostProcess: String, Codable {
    case none, videoMedium, videoLow, mp3, m4a, imageCompressed, jpg, png
    var title: String {
        switch self {
        case .none: return L("الأصلي")
        case .videoMedium: return L("جودة متوسطة")
        case .videoLow: return L("جودة منخفضة")
        case .mp3: return L("صوت فقط MP3")
        case .m4a: return L("صوت فقط M4A")
        case .imageCompressed: return L("مضغوطة")
        case .jpg: return "JPG"
        case .png: return "PNG"
        }
    }
}

struct LinkProbe {
    enum Kind { case video, audio, image, document, hls, page, other }
    var url: URL
    var kind: Kind
    var name: String
    var size: Int64?
    var mime: String?
    /// جودات بث HLS: (الوصف، معدل البت، الرابط)
    var variants: [(String, Int, URL)] = []
    /// ملفات وُجدت داخل صفحة الموقع
    var found: [URL] = []
}

enum LinkInspector {
    static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static func normalize(_ text: String) -> URL? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bar = raw.firstIndex(of: "|") { raw = String(raw[..<bar]) }
        if !raw.lowercased().hasPrefix("http") { raw = "https://" + raw }
        return URL(string: raw) ?? URL(string: raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
    }

    static func kind(mime: String?, ext: String) -> LinkProbe.Kind {
        let m = (mime ?? "").lowercased()
        if m.contains("mpegurl") || ext == "m3u8" { return .hls }
        if m.hasPrefix("video/") || ["mp4", "mov", "m4v", "webm", "mkv", "3gp"].contains(ext) { return .video }
        if m.hasPrefix("audio/") || ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "amr"].contains(ext) { return .audio }
        if m.hasPrefix("image/") || ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(ext) { return .image }
        if m.contains("html") { return .page }
        if m.contains("pdf") || m.contains("zip") || m.contains("officedocument") || m.contains("msword") || m.hasPrefix("text/")
            || ["pdf", "zip", "rar", "7z", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "epub", "txt"].contains(ext) { return .document }
        return .other
    }

    static func probe(_ url: URL) async throws -> LinkProbe {
        var req = URLRequest(url: url)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ToolError.failed(L("تعذّر الوصول إلى الرابط.")) }
        if http.statusCode >= 400 { throw ToolError.failed(LF("رفض الخادم الطلب (%@).", ar(http.statusCode))) }
        let final = http.url ?? url
        let mime = http.mimeType
        var name = resp.suggestedFilename ?? DownloadManager.guessName(final)
        if (name as NSString).pathExtension.isEmpty, let m = mime, let e = UTType(mimeType: m)?.preferredFilenameExtension { name += "." + e }
        var size: Int64?
        if let cr = http.value(forHTTPHeaderField: "Content-Range"), let total = cr.split(separator: "/").last, let n = Int64(total) { size = n }
        else if http.statusCode == 200, http.expectedContentLength > 0 { size = http.expectedContentLength }
        let ext = final.pathExtension.lowercased()
        var p = LinkProbe(url: final, kind: kind(mime: mime, ext: ext), name: name, size: size, mime: mime)
        // نص البداية: بعض الخوادم ترسل قائمة HLS أو صفحة بنوع عام
        let head = String(decoding: data.prefix(4096), as: UTF8.self)
        if head.hasPrefix("#EXTM3U") { p.kind = .hls }
        if p.kind == .hls {
            let text = String(decoding: data, as: UTF8.self).count > 20 ? String(decoding: data, as: UTF8.self)
                : ((try? await URLSession.shared.data(from: final).0).map { String(decoding: $0, as: UTF8.self) } ?? "")
            p.variants = parseHLS(text, base: final)
            p.name = (final.deletingPathExtension().lastPathComponent.isEmpty ? (final.host ?? "video") : final.deletingPathExtension().lastPathComponent) + ".mp4"
        } else if p.kind == .page || head.lowercased().contains("<html") {
            p.kind = .page
            var full = data
            if data.count >= 65536, let more = try? await URLSession.shared.data(from: final).0 { full = more }
            p.found = scanPage(String(decoding: full, as: UTF8.self), base: final)
        }
        return p
    }

    /// جودات البث من القائمة الرئيسية
    static func parseHLS(_ text: String, base: URL) -> [(String, Int, URL)] {
        var out: [(String, Int, URL)] = []
        let lines = text.components(separatedBy: .newlines)
        for (i, l) in lines.enumerated() where l.hasPrefix("#EXT-X-STREAM-INF") {
            var bw = 0, res = ""
            for part in l.split(separator: ",") {
                let kv = part.split(separator: "=", maxSplits: 1)
                guard kv.count == 2 else { continue }
                let k = kv[0].replacingOccurrences(of: "#EXT-X-STREAM-INF:", with: "")
                if k == "BANDWIDTH" { bw = Int(kv[1]) ?? 0 }
                if k == "RESOLUTION" { res = String(kv[1]) }
            }
            var j = i + 1
            while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty || lines[j].hasPrefix("#") { j += 1 }
            guard j < lines.count, let u = URL(string: lines[j].trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL else { continue }
            let h = res.split(separator: "x").last.flatMap { Int($0) }
            let label = h.map { "\($0)p" } ?? LF("%@ ك.ب/ث", ar(bw / 1000))
            if !out.contains(where: { $0.0 == label }) { out.append((label, bw, u)) }
        }
        return out.sorted { $0.1 > $1.1 }
    }

    /// روابط الملفات داخل صفحة الموقع (الوسوم og، وعناصر الفيديو والصوت، والروابط المباشرة)
    static func scanPage(_ html: String, base: URL) -> [URL] {
        var found: [String] = []
        let patterns = [
            #"<meta[^>]+property=["']og:(?:video|video:url|video:secure_url|audio|image)["'][^>]+content=["']([^"']+)["']"#,
            #"<(?:video|audio|source)[^>]+src=["']([^"']+)["']"#,
            #"href=["']([^"']+\.(?:mp4|m4v|mov|webm|mp3|m4a|wav|pdf|zip|rar|epub|jpe?g|png|gif|webp|docx?|xlsx?|pptx?)(?:\?[^"']*)?)["']"#,
            #"["'](https?://[^"'\s]+\.(?:mp4|m3u8|mp3|m4a)(?:\?[^"'\s]*)?)["']"#,
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                if let r = Range(m.range(at: 1), in: html) {
                    let s = String(html[r]).replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "\\/", with: "/")
                    if !s.hasPrefix("blob:"), !s.hasPrefix("data:"), !found.contains(s) { found.append(s) }
                }
            }
        }
        return found.compactMap { URL(string: $0, relativeTo: base)?.absoluteURL }.prefix(40).map { $0 }
    }
}

// MARK: - صفحة الخيارات

struct DownloadOptionsSheet: View {
    let link: String
    @Environment(\.dismiss) private var dismiss
    @State private var probe: LinkProbe?
    @State private var error: String?
    @State private var sub: [URL: LinkProbe] = [:]
    var done: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(Theme.f(.subheadline)).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading).glassCard(padding: 14)
                        option("arrow.down", L("تنزيل الرابط كما هو"), nil) { start(link, .none, name: nil) }
                    } else if let p = probe {
                        header(p)
                        options(p)
                    } else {
                        VStack(spacing: 10) {
                            ProgressView().tint(Theme.gold)
                            Text("جارٍ فحص الرابط…").font(Theme.f(.subheadline)).foregroundStyle(Theme.sub)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle("خيارات التنزيل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
        }
        .task {
            guard let u = LinkInspector.normalize(link) else { error = L("الرابط غير صالح."); return }
            do { probe = try await LinkInspector.probe(u) } catch { self.error = error.localizedDescription }
        }
    }

    private func header(_ p: LinkProbe) -> some View {
        HStack(spacing: 12) {
            Badge(name: icon(p.kind), size: 46, active: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: p.name).font(Theme.f(.headline)).foregroundStyle(.white).lineLimit(2)
                Text(verbatim: [kindTitle(p.kind), p.size.map { sizeText($0) }].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 0)
        }
        .glassCard(padding: 14)
    }

    @ViewBuilder private func options(_ p: LinkProbe) -> some View {
        switch p.kind {
        case .video:
            group(L("الفيديو"), [
                (L("أعلى جودة (الأصلي)"), "sparkles.tv", PostProcess.none),
                (L("جودة متوسطة"), "tv", .videoMedium),
                (L("جودة منخفضة (حجم أصغر)"), "rectangle.compress.vertical", .videoLow),
            ], p)
            group(L("الصوت فقط"), [(L("صوت فقط MP3"), "music.note", .mp3), (L("صوت فقط M4A"), "waveform", .m4a)], p)
        case .audio:
            group(L("الصوت"), [(L("الأصلي"), "waveform", .none), (L("تحويل إلى MP3"), "music.note", .mp3), (L("تحويل إلى M4A"), "waveform", .m4a)], p)
        case .image:
            group(L("الصورة"), [(L("الأصلية"), "photo", .none), (L("مضغوطة (حجم أصغر)"), "rectangle.compress.vertical", .imageCompressed),
                                (L("بصيغة JPG"), "photo", .jpg), (L("بصيغة PNG"), "photo", .png)], p)
        case .hls:
            VStack(alignment: .leading, spacing: 6) {
                Text("الجودات المتوفرة").font(Theme.f(.footnote, .bold)).foregroundStyle(Theme.sub)
                if p.variants.isEmpty {
                    option("sparkles.tv", L("تنزيل الفيديو (MP4)"), nil) { startHLS(p.url, name: p.name, post: .none) }
                } else {
                    ForEach(Array(p.variants.enumerated()), id: \.offset) { _, v in
                        option("tv", v.0, approx(v.1)) { startHLS(v.2, name: p.name, post: .none) }
                    }
                }
                option("music.note", L("صوت فقط MP3"), nil) { startHLS(p.variants.last?.2 ?? p.url, name: p.name, post: .mp3) }
                option("waveform", L("صوت فقط M4A"), nil) { startHLS(p.variants.last?.2 ?? p.url, name: p.name, post: .m4a) }
            }
            Text("روابط البث (m3u8) تُنزَّل ثم تُحوَّل إلى ملف MP4. البث المحمي بالتشفير (DRM) لا يُنزَّل.")
                .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
        case .page:
            if p.found.isEmpty {
                Text("هذا رابط صفحة موقع ولم يُعثر فيها على ملفات مباشرة. افتحه في «المتصفح» لتشغيل الفيديو، ثم اضغط زر «تنزيل» الذي يظهر.")
                    .font(Theme.f(.subheadline)).foregroundStyle(Theme.sub).glassCard(padding: 14)
            } else {
                Text(LF("وُجد في الصفحة %@:", itemsText(p.found.count))).font(Theme.f(.footnote, .bold)).foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(p.found, id: \.self) { u in
                    NavigationLink { DownloadOptionsSheet(link: u.absoluteString, done: done) } label: {
                        HStack(spacing: 10) {
                            Badge(name: icon(LinkInspector.kind(mime: nil, ext: u.pathExtension.lowercased())), size: 34)
                            Text(verbatim: u.lastPathComponent.removingPercentEncoding ?? u.lastPathComponent).font(Theme.f(.subheadline)).foregroundStyle(.white)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Image(systemName: "chevron.forward").foregroundStyle(Theme.sub)
                        }
                        .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                    }
                    .buttonStyle(.plain)
                }
            }
            option("arrow.down.doc", L("حفظ الصفحة نفسها"), nil) { start(p.url.absoluteString, .none, name: (p.url.host ?? "page") + ".html") }
        case .document, .other:
            option("arrow.down", LF("تنزيل %@", p.size.map { sizeText($0) } ?? ""), nil) { start(p.url.absoluteString, .none, name: p.name) }
        }
    }

    private func group(_ title: String, _ rows: [(String, String, PostProcess)], _ p: LinkProbe) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title).font(Theme.f(.footnote, .bold)).foregroundStyle(Theme.sub)
            ForEach(rows, id: \.0) { r in option(r.1, r.0, nil) { start(p.url.absoluteString, r.2, name: p.name) } }
        }
    }

    private func option(_ icon: String, _ title: String, _ detail: String?, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 12) {
                Badge(name: icon, size: 36)
                Text(verbatim: title).font(Theme.f(.body, .medium)).foregroundStyle(.white)
                Spacer()
                if let detail { Text(verbatim: detail).font(Theme.f(.caption)).foregroundStyle(Theme.sub) }
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.gold)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }

    private func approx(_ bw: Int) -> String { LF("%@ م.ب/دقيقة تقريبًا", ar(String(format: "%.0f", Double(bw) * 60 / 8 / 1_000_000))) }

    private func start(_ url: String, _ post: PostProcess, name: String?) {
        if DownloadManager.shared.add(url, name: name, post: post) { done(L("بدأ التنزيل")) }
        dismiss()
    }

    private func startHLS(_ url: URL, name: String, post: PostProcess) {
        HLSDownloader.shared.start(url, name: name, post: post)
        done(L("بدأ التنزيل"))
        dismiss()
    }

    private func icon(_ k: LinkProbe.Kind) -> String {
        switch k {
        case .video, .hls: return "play.rectangle"
        case .audio: return "waveform"
        case .image: return "photo"
        case .document: return "doc.text"
        case .page: return "globe"
        case .other: return "doc"
        }
    }

    private func kindTitle(_ k: LinkProbe.Kind) -> String {
        switch k {
        case .video: return L("فيديو")
        case .hls: return L("بث فيديو (عدة جودات)")
        case .audio: return L("صوت")
        case .image: return L("صورة")
        case .document: return L("مستند")
        case .page: return L("صفحة موقع")
        case .other: return L("ملف")
        }
    }
}

// MARK: - تنزيل بث HLS ثم تحويله إلى MP4

@MainActor
final class HLSDownloader: NSObject, AVAssetDownloadDelegate {
    static let shared = HLSDownloader()
    private var session: AVAssetDownloadURLSession!
    private var map: [Int: UUID] = [:]

    private override init() {
        super.init()
        let cfg = URLSessionConfiguration.background(withIdentifier: "app.hilal.widgets.hls")
        session = AVAssetDownloadURLSession(configuration: cfg, assetDownloadDelegate: self, delegateQueue: .main)
    }

    func start(_ url: URL, name: String, post: PostProcess) {
        let id = DownloadManager.shared.addExternal(url: url.absoluteString, name: name, post: post)
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": LinkInspector.ua]])
        guard let t = session.makeAssetDownloadTask(asset: asset, assetTitle: name, assetArtworkData: nil, options: nil) else {
            DownloadManager.shared.externalFailed(id, L("تعذّر بدء تنزيل البث."))
            return
        }
        map[t.taskIdentifier] = id
        t.resume()
    }

    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange,
                                totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        let loaded = loadedTimeRanges.map { $0.timeRangeValue.duration.seconds }.reduce(0, +)
        let total = timeRangeExpectedToLoad.duration.seconds
        let tid = assetDownloadTask.taskIdentifier
        MainActor.assumeIsolated {
            if let id = map[tid], total > 0 { DownloadManager.shared.externalProgress(id, loaded / total) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        let tid = assetDownloadTask.taskIdentifier
        MainActor.assumeIsolated {
            guard let id = map[tid] else { return }
            Task { await self.finish(id, package: location) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let tid = task.taskIdentifier
        MainActor.assumeIsolated {
            if let id = map.removeValue(forKey: tid) { DownloadManager.shared.externalFailed(id, error.localizedDescription) }
        }
    }

    private func finish(_ id: UUID, package: URL) async {
        let dm = DownloadManager.shared
        guard let it = dm.items.first(where: { $0.id == id }) else { return }
        dm.externalStatus(id, L("جارٍ التحويل إلى MP4…"))
        let store = FileStore.shared
        let downloads = store.root.appendingPathComponent(L("التنزيلات"), isDirectory: true)
        try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let dir = store.destination(for: it.name, base: downloads, source: URL(string: it.url)?.host)
        let dest = store.unique(store.sanitize(it.name.hasSuffix(".mp4") ? it.name : it.name + ".mp4"), in: dir)
        do {
            _ = try await MediaTools.export(AVURLAsset(url: package), preset: AVAssetExportPresetHighestQuality, to: dest, type: .mp4, progress: { _ in })
            try? FileManager.default.removeItem(at: package)
            await dm.finishExternal(id, file: dest)
        } catch {
            try? FileManager.default.removeItem(at: package)
            dm.externalFailed(id, L("تعذّر تحويل البث (قد يكون محميًا)."))
        }
    }
}
