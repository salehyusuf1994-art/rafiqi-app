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
    /// تفاصيل ما وُجد في الصفحة (النوع والدقة والحجم) لعرضه بعناوين واضحة
    var items: [FoundItem] = []
}

/// ملف وُجد داخل صفحة موقع
struct FoundItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    var kind: LinkProbe.Kind
    /// دقة الفيديو (٧٢٠ لـ 720p) إن عُرفت من الرابط
    var height: Int?
    var size: Int64?

    /// «جودة عالية • 720p»، «صوت MP3»، «صورة JPG»…
    var title: String {
        let ext = url.pathExtension.uppercased()
        switch kind {
        case .video:
            guard let h = height else { return ext.isEmpty ? L("فيديو") : LF("فيديو %@", ext) }
            return FoundItem.tier(h) + " • " + "\(h)p"
        case .hls: return L("بث فيديو (عدة جودات)")
        case .audio: return ext.isEmpty ? L("صوت") : LF("صوت %@", ext)
        case .image: return ext.isEmpty ? L("صورة") : LF("صورة %@", ext == "JPEG" ? "JPG" : ext)
        case .document: return ext.isEmpty ? L("مستند") : LF("مستند %@", ext)
        case .page: return L("صفحة موقع")
        case .other: return ext.isEmpty ? L("ملف") : LF("ملف %@", ext)
        }
    }

    static func tier(_ h: Int) -> String {
        h >= 1080 ? L("جودة فائقة") : h >= 720 ? L("جودة عالية") : h >= 480 ? L("جودة متوسطة") : L("جودة منخفضة")
    }

    /// الدقة من الرابط: «/720x1280/» أو «_720p»
    static func height(in url: URL) -> Int? {
        let s = url.absoluteString
        if let re = try? NSRegularExpression(pattern: #"(?<![0-9])([0-9]{3,4})x([0-9]{3,4})(?![0-9])"#),
           let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let a = Range(m.range(at: 1), in: s), let b = Range(m.range(at: 2), in: s),
           let w = Int(s[a]), let h = Int(s[b]), w >= 144, h >= 144 { return min(w, h) }
        if let re = try? NSRegularExpression(pattern: #"(?<![0-9])(144|240|360|480|540|720|1080|1440|2160)p(?![a-z0-9])"#, options: [.caseInsensitive]),
           let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let a = Range(m.range(at: 1), in: s) { return Int(s[a]) }
        return nil
    }
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

    static func probe(_ url: URL, referer: String? = nil) async throws -> LinkProbe {
        var req = URLRequest(url: url)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
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
            p.items = await details(p.found, referer: final.absoluteString)
        }
        return p
    }

    /// نوع كل ملف وحجمه (طلب صغير لكل رابط بالتوازي)، ثم الترتيب: الفيديو من الأعلى دقة، فالصوت، فالصور، فالباقي
    static func details(_ urls: [URL], referer: String) async -> [FoundItem] {
        let list = Array(urls.prefix(24))
        var out: [FoundItem] = await withTaskGroup(of: FoundItem?.self) { g in
            for u in list {
                g.addTask {
                    var req = URLRequest(url: u)
                    req.setValue(ua, forHTTPHeaderField: "User-Agent")
                    req.setValue(referer, forHTTPHeaderField: "Referer")
                    req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
                    req.timeoutInterval = 10
                    let ext = u.pathExtension.lowercased()
                    var mime: String?, size: Int64?
                    if let (_, resp) = try? await URLSession.shared.data(for: req), let h = resp as? HTTPURLResponse {
                        if h.statusCode >= 400 { return nil }   // رابط لا يعمل: لا يُعرض
                        mime = h.mimeType
                        if let cr = h.value(forHTTPHeaderField: "Content-Range"), let t = cr.split(separator: "/").last { size = Int64(t) }
                        else if h.expectedContentLength > 1 { size = h.expectedContentLength }
                    }
                    var k = kind(mime: mime, ext: ext)
                    if k == .page { return nil }                       // رابط صفحة أخرى، لا ملف
                    if k == .other && ext.isEmpty && size == nil { return nil }
                    if (mime ?? "").lowercased().hasPrefix("text/") && ext.isEmpty { k = .other }
                    return FoundItem(url: u, kind: k, height: k == .video ? FoundItem.height(in: u) : nil, size: size)
                }
            }
            var r: [FoundItem] = []
            for await x in g { if let x { r.append(x) } }
            return r
        }
        func rank(_ k: LinkProbe.Kind) -> Int {
            switch k {
            case .video: return 0
            case .hls: return 1
            case .audio: return 2
            case .image: return 3
            case .document: return 4
            default: return 5
            }
        }
        out.sort { a, b in
            rank(a.kind) != rank(b.kind) ? rank(a.kind) < rank(b.kind) : (a.height ?? 0) != (b.height ?? 0) ? (a.height ?? 0) > (b.height ?? 0) : (a.size ?? 0) > (b.size ?? 0)
        }
        // نفس الدقة مكررة: يبقى واحد
        var seen = Set<String>()
        return out.filter { it in
            guard it.kind == .video, let h = it.height else { return true }
            return seen.insert("v\(h)").inserted
        }
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
            let label = h.map { FoundItem.tier($0) + " • " + "\($0)p" } ?? LF("%@ ك.ب/ث", ar(bw / 1000))
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
    var done: (String) -> Void
    /// ملف اختير من داخل صفحة موقع: تُعرض خياراته مكان الصفحة (بدون فتح صفحة فوقها)
    @State private var sub: SubLink?

    struct SubLink: Equatable { let url: String; let referer: String? }

    var body: some View {
        NavigationStack {
            Group {
                if let sub {
                    DownloadOptionsPage(link: sub.url, referer: sub.referer, done: done, close: { dismiss() }, open: open)
                        .id(sub.url)
                } else {
                    DownloadOptionsPage(link: link, done: done, close: { dismiss() }, open: open)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                if sub != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { withAnimation { sub = nil } } label: { Label("رجوع", systemImage: "chevron.backward") }
                    }
                }
            }
        }
    }

    private func open(_ u: URL, _ referer: String?) { withAnimation { sub = SubLink(url: u.absoluteString, referer: referer) } }
}

/// محتوى خيارات التنزيل (بدون NavigationStack خاص، ليُفتح داخل الصفحة نفسها عند اختيار ملف من صفحة موقع)
struct DownloadOptionsPage: View {
    let link: String
    /// الصفحة التي وُجد فيها الملف (كثير من المواقع ترفض التنزيل المباشر بدونها)
    var referer: String? = nil
    @State private var probe: LinkProbe?
    @State private var error: String?
    var done: (String) -> Void
    /// يغلق صفحة الخيارات كلها بعد بدء التنزيل
    var close: () -> Void
    /// يعرض خيارات ملف وُجد في الصفحة (الرابط، والصفحة مصدرًا)
    var open: (URL, String?) -> Void

    var body: some View {
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
        .task {
            guard let u = LinkInspector.normalize(link) else { error = L("الرابط غير صالح."); return }
            do { probe = try await LinkInspector.probe(u, referer: referer) } catch { self.error = error.localizedDescription }
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
            if p.items.isEmpty {
                Text("هذا رابط صفحة موقع ولم يُعثر فيها على ملفات مباشرة. افتحه في «المتصفح» لتشغيل الفيديو، ثم اضغط زر «تنزيل» الذي يظهر.")
                    .font(Theme.f(.subheadline)).foregroundStyle(Theme.sub).glassCard(padding: 14)
            } else {
                Text(LF("وُجد في الصفحة %@:", itemsText(p.items.count))).font(Theme.f(.footnote, .bold)).foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(p.items) { it in
                    if direct(it) {
                        // ملف معروف النوع والدقة: يبدأ تنزيله مباشرة
                        option(icon(it.kind), it.title, it.size.map { sizeText($0) }) {
                            start(it.url.absoluteString, .none, name: fileName(it, page: p), referer: p.url.absoluteString)
                        }
                    } else {
                        // بث أو ملف غير معروف الدقة: تُفتح خياراته (الجودات والتحويل)
                        Button { open(it.url, p.url.absoluteString) } label: {
                            HStack(spacing: 12) {
                                Badge(name: icon(it.kind), size: 36)
                                Text(verbatim: it.title).font(Theme.f(.body, .medium)).foregroundStyle(.white)
                                Spacer()
                                if let sz = it.size { Text(verbatim: sizeText(sz)).font(Theme.f(.caption)).foregroundStyle(Theme.sub) }
                                Image(systemName: "chevron.forward").foregroundStyle(Theme.sub)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(it.title + " " + (it.url.lastPathComponent))
                    }
                }
                // صوت MP3 من الفيديو (من أصغر نسخة: الصوت نفسه بتنزيل أقل)
                if let v = p.items.last(where: { $0.kind == .video && $0.height != nil }) {
                    option("music.note", L("صوت MP3"), v.size.map { sizeText($0) }) {
                        start(v.url.absoluteString, .mp3, name: fileName(v, page: p), referer: p.url.absoluteString)
                    }
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

    /// يُنزَّل مباشرة: فيديو معروف الدقة، أو صوت أو صورة أو مستند
    private func direct(_ it: FoundItem) -> Bool {
        switch it.kind {
        case .video: return it.height != nil
        case .audio, .image, .document: return true
        default: return false
        }
    }

    /// اسم الملف: اسم الموقع مع الدقة (مثل «x.com 720p.mp4») بدل الحروف العشوائية في الرابط
    private func fileName(_ it: FoundItem, page: LinkProbe) -> String {
        let ext = it.url.pathExtension.isEmpty ? "mp4" : it.url.pathExtension
        let site = (page.url.host ?? "").replacingOccurrences(of: "www.", with: "")
        if let h = it.height { return "\(site) \(h)p.\(ext)" }
        return it.url.lastPathComponent.removingPercentEncoding ?? it.url.lastPathComponent
    }

    private func start(_ url: String, _ post: PostProcess, name: String?, referer ref: String? = nil) {
        let r = ref ?? referer
        if DownloadManager.shared.add(url, name: name, headers: r.map { ["Referer": $0] } ?? [:], post: post) { done(L("بدأ التنزيل")) }
        close()
    }

    private func startHLS(_ url: URL, name: String, post: PostProcess) {
        HLSDownloader.shared.start(url, name: name, post: post, referer: referer)
        done(L("بدأ التنزيل"))
        close()
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

    func start(_ url: URL, name: String, post: PostProcess, referer: String? = nil) {
        let id = DownloadManager.shared.addExternal(url: url.absoluteString, name: name, post: post)
        var headers = ["User-Agent": LinkInspector.ua]
        if let referer { headers["Referer"] = referer }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
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
