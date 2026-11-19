import SwiftUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - روابط البث: الترويسات، وقوائم M3U، وتجربة الرابط

/// أصل البث مع ترويساته (User-Agent له مفتاح خاص في النظام)
enum StreamAsset {
    static func make(_ url: URL, headers: [String: String]) -> AVURLAsset {
        guard !headers.isEmpty else { return AVURLAsset(url: url) }
        var opts: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        if let ua = headers.first(where: { $0.key.lowercased() == "user-agent" })?.value, !ua.isEmpty {
            opts[AVURLAssetHTTPUserAgentKey] = ua
        }
        return AVURLAsset(url: url, options: opts)
    }

    /// أول جزء من الرابط فقط (لمعرفة نوعه دون تنزيل فيديو كامل)
    static func head(_ url: URL, headers: [String: String], limit: Int = 200_000) async -> (Data, Int)? {
        guard let res = try? await URLSession.shared.bytes(for: request(url, headers: headers)) else { return nil }
        let (bytes, r) = res
        var d = Data()
        do {
            for try await b in bytes {
                d.append(b)
                if d.count >= limit { break }
            }
        } catch {}
        return (d, (r as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// طلب نصي بنفس الترويسات (لتحميل قوائم M3U)
    static func request(_ url: URL, headers: [String: String]) -> URLRequest {
        var r = URLRequest(url: url)
        r.timeoutInterval = 20
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        if headers.keys.first(where: { $0.lowercased() == "user-agent" }) == nil {
            r.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")
        }
        return r
    }
}

/// رابط بصيغة «الرابط|Referer=…&User-Agent=…» (صيغة Kodi الشائعة في القوائم)
enum StreamLink {
    static func split(_ raw: String) -> (url: String, headers: [String: String]) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bar = t.firstIndex(of: "|") else { return (t, [:]) }
        let url = String(t[..<bar])
        var h: [String: String] = [:]
        for part in t[t.index(after: bar)...].split(separator: "&") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let k = kv[0].trimmingCharacters(in: .whitespaces)
            let v = (kv[1].removingPercentEncoding ?? kv[1]).trimmingCharacters(in: .whitespaces)
            if !k.isEmpty, !v.isEmpty { h[Headers.canonical(k)] = v }
        }
        return (url, h)
    }

    static func valid(_ s: String) -> URL? {
        guard let u = URL(string: s), let sc = u.scheme?.lowercased(), sc == "https" || sc == "http", u.host != nil else { return nil }
        return u
    }
}

/// ترويسات: تحويل من نص «المفتاح: القيمة» في كل سطر وإليه
enum Headers {
    static func canonical(_ k: String) -> String {
        switch k.lowercased() {
        case "user-agent", "useragent", "http-user-agent": return "User-Agent"
        case "referer", "referrer", "http-referrer", "http-referer": return "Referer"
        case "origin", "http-origin": return "Origin"
        case "cookie", "http-cookie": return "Cookie"
        case "authorization": return "Authorization"
        default: return k
        }
    }

    static func parse(_ text: String) -> [String: String] {
        var h: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty, let sep = l.firstIndex(where: { $0 == ":" || $0 == "=" }) else { continue }
            let k = l[..<sep].trimmingCharacters(in: .whitespaces)
            let v = l[l.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            if !k.isEmpty, !v.isEmpty { h[canonical(k)] = v }
        }
        return h
    }

    static func text(_ h: [String: String]) -> String {
        h.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }

    /// قيم جاهزة لـ User-Agent
    static let agents: [(String, String)] = [
        ("Safari (آيفون)", "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        ("Chrome (كمبيوتر)", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"),
        ("VLC", "VLC/3.0.20 LibVLC/3.0.20"),
        ("Kodi", "Kodi/21.0 (Linux; Android 13) Android/13 Sys_CPU/aarch64 App_Bitness/64 Version/21.0"),
    ]
}

// MARK: - قراءة قوائم M3U

struct M3UEntry: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var url: String
    var logo: String
    var group: String
    var headers: [String: String]
    /// محمية بتشفير (DRM): لا يشغّلها مشغّل أبل
    var drm: Bool
}

enum M3UParser {
    /// قائمة قنوات (وليست بثًا مباشرًا بصيغة HLS)
    static func isPlaylist(_ text: String) -> Bool {
        text.contains("#EXTINF") && !text.contains("#EXT-X-TARGETDURATION") && !text.contains("#EXT-X-STREAM-INF")
            && !text.contains("#EXT-X-MEDIA-SEQUENCE")
    }

    static func parse(_ text: String) -> [M3UEntry] {
        var out: [M3UEntry] = []
        var name = "", logo = "", group = ""
        var h: [String: String] = [:]
        var drm = false
        var pending = false

        func attr(_ line: String, _ key: String) -> String {
            guard let r = line.range(of: key + "=\"") else { return "" }
            let rest = line[r.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { return "" }
            return String(rest[..<end]).trimmingCharacters(in: .whitespaces)
        }
        func reset() { name = ""; logo = ""; group = ""; h = [:]; drm = false; pending = false }

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#EXTM3U") { continue }
            if line.hasPrefix("#EXTINF") {
                reset()
                pending = true
                // الاسم بعد آخر فاصلة خارج علامات التنصيص
                var inQuote = false, comma: String.Index?
                for i in line.indices {
                    if line[i] == "\"" { inQuote.toggle() } else if line[i] == ",", !inQuote { comma = i }
                }
                if let c = comma { name = String(line[line.index(after: c)...]).trimmingCharacters(in: .whitespaces) }
                if name.isEmpty { name = attr(line, "tvg-name") }
                logo = attr(line, "tvg-logo")
                group = attr(line, "group-title")
                let ua = attr(line, "http-user-agent"); if !ua.isEmpty { h["User-Agent"] = ua }
                let rf = attr(line, "http-referrer"); if !rf.isEmpty { h["Referer"] = rf }
            } else if line.hasPrefix("#EXTVLCOPT:") {
                let kv = line.dropFirst("#EXTVLCOPT:".count).split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { h[Headers.canonical(kv[0])] = kv[1].trimmingCharacters(in: .whitespaces) }
            } else if line.hasPrefix("#EXTHTTP:") {
                let json = line.dropFirst("#EXTHTTP:".count)
                if let d = json.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                    for (k, v) in o { if let s = v as? String { h[Headers.canonical(k)] = s } }
                }
            } else if line.hasPrefix("#KODIPROP:") {
                let p = line.dropFirst("#KODIPROP:".count)
                if p.contains("license_type") || p.contains("license_key") { drm = true }
                if p.hasPrefix("inputstream.adaptive.stream_headers=") || p.hasPrefix("inputstream.adaptive.common_headers=") {
                    let v = p.split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
                    for (k, val) in StreamLink.split("x|" + v).headers { h[k] = val }
                }
            } else if line.hasPrefix("#EXTGRP:") {
                if group.isEmpty { group = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces) }
            } else if line.hasPrefix("#") {
                continue
            } else {
                let (u, extra) = StreamLink.split(line)
                guard StreamLink.valid(u) != nil else { reset(); continue }
                var all = h
                for (k, v) in extra { all[k] = v }
                let low = u.lowercased()
                if low.contains(".mpd") { drm = true }   // DASH: لا يدعمه مشغّل أبل
                out.append(M3UEntry(name: pending && !name.isEmpty ? name : (URL(string: u)?.host ?? u),
                                    url: u, logo: logo.hasPrefix("http") ? logo : "", group: group, headers: all, drm: drm))
                reset()
            }
        }
        return out
    }

    static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }
}

// MARK: - تجربة الرابط قبل الحفظ

@MainActor
final class StreamTester: ObservableObject {
    enum State: Equatable { case idle, loading, ok, failed(String), playlist }
    @Published var state: State = .idle
    let player = AVPlayer()
    private var obs: NSKeyValueObservation?
    private var timeout: Task<Void, Never>?
    private var token = 0

    func test(_ url: URL, headers: [String: String]) {
        stop()
        token += 1
        let t = token
        state = .loading
        player.isMuted = false
        let item = AVPlayerItem(asset: StreamAsset.make(url, headers: headers))
        obs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            let st = it.status
            let err = it.error?.localizedDescription
            Task { @MainActor in
                guard let self, self.token == t else { return }
                if st == .readyToPlay { self.state = .ok; self.timeout?.cancel() }
                else if st == .failed { await self.explain(url, headers: headers, err, token: t) }
            }
        }
        player.replaceCurrentItem(with: item)
        // التجربة تأخذ الصوت مثل أي مشغّل: يتوقف القرآن أو الإذاعة فلا يُسمع صوتان معًا
        PlaybackGate.claim(.tv)
        player.play()
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, !Task.isCancelled, self.token == t, self.state == .loading else { return }
            await self.explain(url, headers: headers, nil, token: t)
        }
    }

    /// لم يشتغل: هل هو قائمة M3U؟ أو مرفوض من الخادم؟
    private func explain(_ url: URL, headers: [String: String], _ err: String?, token t: Int) async {
        player.replaceCurrentItem(with: nil)
        if let res = await StreamAsset.head(url, headers: headers) {
            let (d, code) = res
            guard token == t else { return }
            if M3UParser.isPlaylist(M3UParser.decode(d)) { state = .playlist; return }
            if code == 401 || code == 403 {
                state = .failed(LF("رفض الخادم الطلب (%@). جرّب إضافة Referer أو User-Agent أو ترويسة مصادقة.", ar(code)))
                return
            }
            if code == 404 || code == 410 { state = .failed(LF("الرابط غير موجود (%@). ربما انتهى أو تغيّر.", ar(code))); return }
        }
        guard token == t else { return }
        state = .failed(err ?? L("لم يبدأ البث خلال ١٥ ثانية."))
    }

    func stop() {
        timeout?.cancel()
        obs = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .idle
    }
}

// MARK: - شاشة «إضافة قناة» / «تعديل قناة»

struct AddTVSheet: View {
    var editing: TVChannel? = nil
    @Environment(\.dismiss) private var dismiss

    enum Mode: Hashable { case single, playlist }
    @State private var mode: Mode = .single

    // قناة واحدة
    @State private var name = ""
    @State private var url = ""
    @State private var cat: TVCat = .sports
    @State private var referer = ""
    @State private var agent = ""
    @State private var extra = ""
    @State private var logo = ""
    @StateObject private var tester = StreamTester()

    // قائمة M3U
    @State private var listURL = ""
    @State private var entries: [M3UEntry] = []
    @State private var picked = Set<UUID>()
    @State private var group: String? = nil
    @State private var query = ""
    @State private var listCat: TVCat = .sports
    @State private var loadingList = false
    @State private var listError: String?
    @State private var importing = false
    @State private var added: Int?
    @State private var prepared = false
    /// اسم القائمة المستوردة (يظهر في «القنوات المضافة» لحذفها كاملة)
    @State private var sourceName = ""

    private var headers: [String: String] {
        var h = Headers.parse(extra)
        let ua = agent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ua.isEmpty { h["User-Agent"] = ua }
        let (_, inline) = StreamLink.split(url)
        for (k, v) in inline where h[k] == nil { h[k] = v }
        return h
    }
    private var refererValue: String {
        let r = referer.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.isEmpty ? (StreamLink.split(url).headers["Referer"] ?? "") : r
    }
    private var validURL: URL? { StreamLink.valid(StreamLink.split(url).url) }
    private var allHeaders: [String: String] {
        TVChannel(id: "t", name: "", cat: cat, urls: [], logo: "", referer: refererValue, headers: headers).httpHeaders
    }

    var body: some View {
        NavigationStack {
            Form {
                if editing == nil {
                    Section {
                        Picker("", selection: $mode) {
                            Text("قناة واحدة").tag(Mode.single)
                            Text("قائمة M3U").tag(Mode.playlist)
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if mode == .single { singleForm } else { playlistForm }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(editing == nil ? L("إضافة قناة") : L("تعديل القناة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { tester.stop(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if mode == .single {
                        Button("حفظ") { saveSingle() }.disabled(validURL == nil)
                    } else {
                        Button(LF("إضافة (%@)", ar(picked.count))) { addPicked() }.disabled(picked.isEmpty)
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: m3uTypes) { r in
                guard case .success(let f) = r else { return }
                let ok = f.startAccessingSecurityScopedResource()
                defer { if ok { f.stopAccessingSecurityScopedResource() } }
                if let d = try? Data(contentsOf: f) { load(M3UParser.decode(d)); sourceName = f.lastPathComponent }
            }
            .onAppear(perform: prepare)
            .onDisappear { tester.stop() }
        }
        .presentationDetents([.large])
    }

    private var m3uTypes: [UTType] {
        [UTType(filenameExtension: "m3u"), UTType(filenameExtension: "m3u8"), .plainText, .text].compactMap { $0 }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        guard let c = editing else { return }
        name = c.name
        url = c.urls.first ?? ""
        cat = c.cat
        logo = c.logo
        referer = c.referer ?? ""
        var h = c.headers ?? [:]
        if let k = h.keys.first(where: { $0.lowercased() == "user-agent" }) { agent = h[k] ?? ""; h[k] = nil }
        extra = Headers.text(h)
    }

    // ── قناة واحدة ──

    @ViewBuilder private var singleForm: some View {
        Section {
            TextField("اسم القناة", text: $name)
            TextField("https://…/playlist.m3u8", text: $url, axis: .vertical)
                .lineLimit(1...4)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
                .onChange(of: url) { _, _ in if tester.state != .idle { tester.stop() } }
            Picker("القسم", selection: $cat) {
                ForEach(TVCat.allCases, id: \.self) { c in Text(verbatim: c.title).tag(c) }
            }
        } footer: {
            Text("رابط بث مباشر بصيغة HLS (ينتهي عادة بـ m3u8)، أو mp4 مباشر. ويُقبل الرابط بصيغة «الرابط|Referer=…&User-Agent=…».")
        }

        Section {
            TextField("https://…", text: $referer)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
        } header: {
            Text("موقع القناة — Referer (اختياري)")
        } footer: {
            Text("بعض القنوات لا تبث إلا إذا عُرف موقعها. يُرسل كـ Referer و Origin.")
        }

        Section {
            HStack {
                TextField("User-Agent", text: $agent)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
                Menu {
                    ForEach(Headers.agents.indices, id: \.self) { i in
                        Button(L(Headers.agents[i].0)) { agent = Headers.agents[i].1 }
                    }
                    if !agent.isEmpty { Divider(); Button("مسح", role: .destructive) { agent = "" } }
                } label: { Image(systemName: "list.bullet.circle").font(Theme.f(.title3)) }
                .accessibilityLabel(L("اختيار المتصفح"))
            }
            TextField("Authorization: Bearer …\nCookie: …", text: $extra, axis: .vertical)
                .lineLimit(2...6)
                .font(.system(.footnote, design: .monospaced))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
        } header: {
            Text("ترويسات إضافية (اختياري)")
        } footer: {
            Text("ترويسة في كل سطر بصيغة «الاسم: القيمة». تُرسل مع كل طلبات البث.")
        }

        Section {
            Button {
                guard let u = validURL else { return }
                tester.test(u, headers: allHeaders)
            } label: {
                Label(tester.state == .loading ? L("جارٍ التجربة…") : L("تجربة التشغيل"), systemImage: "play.circle")
            }
            .disabled(validURL == nil || tester.state == .loading)

            switch tester.state {
            case .idle:
                EmptyView()
            case .loading:
                HStack { ProgressView(); Text("جارٍ الاتصال بالبث…").foregroundStyle(Theme.sub) }
            case .ok:
                VideoPlayer(player: tester.player)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                Label("الرابط يعمل", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let msg):
                Label(msg, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(Theme.f(.subheadline))
            case .playlist:
                VStack(alignment: .leading, spacing: 8) {
                    Label("هذا رابط قائمة M3U فيها عدة قنوات، وليس بث قناة واحدة.", systemImage: "list.bullet.rectangle")
                        .font(Theme.f(.subheadline))
                    Button("افتحه كقائمة M3U") {
                        listURL = url; mode = .playlist; tester.stop()
                        Task { await fetchList() }
                    }
                    .font(Theme.f(.subheadline, .semibold))
                }
            }
        }
    }

    private func saveSingle() {
        guard let u = validURL else { return }
        tester.stop()
        let n = name.trimmingCharacters(in: .whitespaces)
        let ref = refererValue
        var h = headers
        h["Referer"] = nil
        if var c = editing {
            c.name = n.isEmpty ? c.name : n
            c.urls = [u.absoluteString]
            c.cat = cat
            c.referer = ref.isEmpty ? nil : ref
            c.headers = h.isEmpty ? nil : h
            TVChannels.updateCustom(c)
        } else {
            TVChannels.addCustom(name: n.isEmpty ? (u.host ?? L("قناة")) : n, url: u.absoluteString, cat: cat,
                                 referer: ref, headers: h, logo: logo)
        }
        dismiss()
    }

    // ── قائمة M3U ──

    private var groups: [String] {
        var seen = Set<String>()
        return entries.map(\.group).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    private var shown: [M3UEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return entries.filter { e in
            (group == nil || e.group == group) && (q.isEmpty || e.name.localizedCaseInsensitiveContains(q))
        }
    }

    @ViewBuilder private var playlistForm: some View {
        Section {
            TextField("https://…/playlist.m3u", text: $listURL)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
            HStack(spacing: 18) {
                Button { Task { await fetchList() } } label: {
                    Label(loadingList ? L("جارٍ التحميل…") : L("تحميل القائمة"), systemImage: "arrow.down.circle")
                }
                .disabled(StreamLink.valid(listURL.trimmingCharacters(in: .whitespacesAndNewlines)) == nil || loadingList)
                Spacer()
                Button { importing = true } label: { Image(systemName: "doc.badge.plus") }
                    .accessibilityLabel(L("اختيار ملف قائمة"))
                Button {
                    if let t = UIPasteboard.general.string {
                        if M3UParser.isPlaylist(t) { load(t); sourceName = L("قائمة ملصقة") } else { listURL = t.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                } label: { Image(systemName: "doc.on.clipboard") }
                    .accessibilityLabel(L("لصق"))
            }
            .buttonStyle(.borderless)
            if let e = listError {
                Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(Theme.f(.subheadline))
            }
            if let n = added {
                Label(LF("أُضيفت %@", channelsText(n)), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        } footer: {
            Text("الصق رابط قائمة M3U، أو اختر ملفها من «الملفات» 📄، أو الصق نصّها 📋. تُقرأ أسماء القنوات وشعاراتها ومجموعاتها وترويساتها (http-referrer و http-user-agent).")
        }

        if !entries.isEmpty {
            Section {
                Picker("أضفها إلى قسم", selection: $listCat) {
                    ForEach(TVCat.allCases, id: \.self) { c in Text(verbatim: c.title).tag(c) }
                }
                if !groups.isEmpty {
                    Picker("المجموعة", selection: $group) {
                        Text("كل المجموعات").tag(String?.none)
                        ForEach(groups, id: \.self) { g in Text(verbatim: g).tag(String?.some(g)) }
                    }
                }
                TextField("بحث في القنوات", text: $query)
                HStack {
                    Button("تحديد المعروض") { for e in shown where !e.drm { picked.insert(e.id) } }
                    Spacer()
                    Button("إلغاء التحديد") { picked.removeAll() }
                }
                .buttonStyle(.borderless)
                .font(Theme.f(.subheadline, .semibold))
            } header: {
                Text(LF("%@ في القائمة", channelsText(entries.count)))
            }

            Section {
                ForEach(shown.prefix(400)) { e in row(e) }
            } footer: {
                if shown.count > 400 { Text("تظهر أول ٤٠٠ قناة؛ استخدم البحث أو المجموعة لتضييق القائمة.") }
                else { Text("🔒 تعني أن للقناة ترويسات ستُحفظ معها. القنوات المعلّمة ⚠️ محمية بتشفير DRM أو بصيغة DASH ولا تعمل على الآيفون.") }
            }
        }
    }

    private func row(_ e: M3UEntry) -> some View {
        let on = picked.contains(e.id)
        return Button {
            if on { picked.remove(e.id) } else { picked.insert(e.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(Theme.f(.title3)).foregroundStyle(on ? Theme.gold : Theme.sub)
                TVLogo(channel: TVChannel(id: e.id.uuidString, name: e.name, cat: listCat, urls: [], logo: e.logo),
                       width: 52, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: e.name).foregroundStyle(.white).lineLimit(1)
                    if !e.group.isEmpty { Text(verbatim: e.group).font(Theme.f(.caption)).foregroundStyle(Theme.sub).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if !e.headers.isEmpty { Image(systemName: "lock.fill").font(Theme.f(.caption)).foregroundStyle(Theme.sub) }
                if e.drm { Image(systemName: "exclamationmark.triangle.fill").font(Theme.f(.caption)).foregroundStyle(.orange) }
            }
        }
        .buttonStyle(.plain)
    }

    private func fetchList() async {
        let raw = listURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let (u0, inline) = StreamLink.split(raw)
        guard let u = StreamLink.valid(u0) else { return }
        loadingList = true
        listError = nil
        added = nil
        defer { loadingList = false }
        var h = Headers.parse(extra)
        if !agent.isEmpty { h["User-Agent"] = agent }
        for (k, v) in inline { h[k] = v }
        do {
            let (d, r) = try await URLSession.shared.data(for: StreamAsset.request(u, headers: h))
            let code = (r as? HTTPURLResponse)?.statusCode ?? 200
            guard (200..<300).contains(code) else { listError = LF("تعذّر تحميل القائمة (%@).", ar(code)); return }
            let text = M3UParser.decode(d)
            if !M3UParser.isPlaylist(text) {
                listError = text.contains("#EXT-X-") ? L("هذا رابط بث قناة واحدة (HLS) وليس قائمة؛ أضفه من «قناة واحدة».")
                                                     : L("لا توجد قنوات في هذا الرابط.")
                return
            }
            load(text)
            sourceName = u.lastPathComponent.isEmpty ? (u.host ?? "M3U") : (u.host ?? "") + "/" + u.lastPathComponent
        } catch {
            listError = error.localizedDescription
        }
    }

    private func load(_ text: String) {
        entries = M3UParser.parse(text)
        picked.removeAll()
        group = nil
        query = ""
        added = nil
        listError = entries.isEmpty ? L("لا توجد قنوات في هذه القائمة.") : nil
    }

    private func addPicked() {
        let list = entries.filter { picked.contains($0.id) }.map { e -> TVChannel in
            var h = e.headers
            let ref = h["Referer"]
            h["Referer"] = nil
            return TVChannel(id: "custom." + UUID().uuidString, name: e.name, cat: listCat, urls: [e.url], logo: e.logo,
                             referer: ref, headers: h.isEmpty ? nil : h, source: sourceName)
        }
        added = TVChannels.addCustom(list)
        picked.removeAll()
    }
}

// MARK: - «القنوات المضافة»: إدارة وحذف ما أضفته (قناة، أو قائمة كاملة، أو الكل)

struct CustomChannelsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var list = TVChannels.custom
    @State private var selection = Set<String>()
    @State private var editMode: EditMode = .inactive
    @State private var editing: TVChannel?
    @State private var confirm: Confirm?

    enum Confirm: Identifiable {
        case source(String?), selected, all
        var id: String {
            switch self {
            case .source(let s): return "s:" + (s ?? "")
            case .selected: return "sel"
            case .all: return "all"
            }
        }
    }

    /// المصادر بترتيب الإضافة (القنوات المضافة يدويًا أولًا)
    private var sources: [String?] {
        var seen = Set<String>(), out: [String?] = []
        if list.contains(where: { $0.source == nil }) { out.append(nil) }
        for c in list { if let s = c.source, seen.insert(s).inserted { out.append(s) } }
        return out
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                if list.isEmpty {
                    Text("لا توجد قنوات مضافة.").foregroundStyle(Theme.sub)
                }
                ForEach(sources, id: \.self) { src in
                    let items = list.filter { $0.source == src }
                    Section {
                        ForEach(items) { c in
                            row(c)
                            .tag(c.id)
                            .swipeActions {
                                Button(role: .destructive) { remove([c.id]) } label: { Label("حذف", systemImage: "trash") }
                                Button { editing = c } label: { Label("تعديل", systemImage: "pencil") }.tint(.blue)
                            }
                            .contextMenu {
                                Button { watch(c) } label: { Label("مشاهدة", systemImage: "play.fill") }
                                Button { editing = c } label: { Label("تعديل القناة", systemImage: "pencil") }
                                Button(role: .destructive) { remove([c.id]) } label: { Label("حذف القناة", systemImage: "trash") }
                            }
                        }
                    } header: {
                        HStack {
                            Label(src ?? L("مضافة يدويًا"), systemImage: src == nil ? "link" : "list.bullet.rectangle")
                                .lineLimit(1)
                            Spacer()
                            Text(verbatim: ar(items.count))
                        }
                    } footer: {
                        if src != nil {
                            Button(role: .destructive) { confirm = .source(src) } label: {
                                Label("حذف هذه القائمة كاملة", systemImage: "trash")
                                    .font(Theme.f(.footnote, .semibold)).foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }
                if !list.isEmpty {
                    Section {
                        Button(role: .destructive) { confirm = .all } label: {
                            Label("حذف كل القنوات المضافة", systemImage: "trash.fill").foregroundStyle(.red)
                        }
                    } footer: {
                        Text("اضغط على القناة لتشغيلها. اسحبها لليسار لحذفها أو تعديلها، أو اضغط «تحديد» لحذف عدة قنوات معًا. القنوات الأساسية في التطبيق لا تتأثر.")
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("القنوات المضافة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("تم") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if editMode.isEditing {
                        Button(LF("حذف (%@)", ar(selection.count))) { confirm = .selected }
                            .disabled(selection.isEmpty).tint(.red)
                    } else if !list.isEmpty {
                        Button("تحديد") { withAnimation { editMode = .active } }
                    }
                }
                if editMode.isEditing {
                    ToolbarItem(placement: .bottomBar) {
                        Button("إلغاء التحديد") { withAnimation { selection.removeAll(); editMode = .inactive } }
                    }
                }
            }
            .confirmationDialog("تأكيد الحذف", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                                titleVisibility: .visible, presenting: confirm) { c in
                Button(role: .destructive) {
                    switch c {
                    case .source(let s): remove(Set(list.filter { $0.source == s }.map(\.id)))
                    case .selected: remove(selection); selection.removeAll(); editMode = .inactive
                    case .all: remove(Set(list.map(\.id)))
                    }
                } label: { Text(confirmTitle(c)) }
            } message: { c in
                Text(confirmTitle(c))
            }
            .sheet(item: $editing, onDismiss: { list = TVChannels.custom }) { c in AddTVSheet(editing: c) }
        }
    }

    /// الضغط على القناة يشغّلها (وفي وضع «تحديد» يحددها فقط)
    @ViewBuilder private func row(_ c: TVChannel) -> some View {
        let content = HStack(spacing: 12) {
            TVLogo(channel: c, width: 52, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: c.name).foregroundStyle(.white).lineLimit(1)
                Text(verbatim: c.cat.title).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 0)
            if !editMode.isEditing {
                Image(systemName: "play.circle.fill").font(Theme.f(.title3)).foregroundStyle(Theme.gold)
            }
        }
        .contentShape(Rectangle())
        if editMode.isEditing {
            content
        } else {
            Button { watch(c) } label: { content }.buttonStyle(.plain)
        }
    }

    private func watch(_ c: TVChannel) {
        dismiss()
        TVRouter.shared.open = c
    }

    private func confirmTitle(_ c: Confirm) -> String {
        switch c {
        case .source(let s):
            return LF("حذف %@ من «%@»", channelsText(list.filter { $0.source == s }.count), s ?? L("مضافة يدويًا"))
        case .selected: return LF("حذف المحدد (%@)", channelsText(selection.count))
        case .all: return LF("حذف كل القنوات المضافة (%@)", ar(list.count))
        }
    }

    private func remove(_ ids: Set<String>) {
        TVChannels.removeCustom(ids)
        withAnimation { list = TVChannels.custom }
    }
}
