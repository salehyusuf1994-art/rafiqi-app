import SwiftUI
import WebKit

// MARK: - المتصفح الداخلي: يكتشف الملفات القابلة للتنزيل في الصفحة، ويحفظ ما يرسله الموقع للتنزيل

@MainActor
final class BrowserModel: NSObject, ObservableObject {
    @Published var address = ""
    @Published var title = ""
    @Published var canBack = false
    @Published var canForward = false
    @Published var loading = false
    @Published var progress: Double = 0
    @Published var found: [MediaLink] = []
    @Published var message: String?
    let web: WKWebView
    private var obs: [NSKeyValueObservation] = []

    struct MediaLink: Identifiable, Hashable {
        let url: String
        let label: String
        var id: String { url }
    }

    struct Entry: Codable, Hashable, Identifiable {
        var title: String
        var url: String
        var date = Date()
        var id: String { url }
    }
    @Published var bookmarks: [Entry] = BrowserModel.load("browser.bookmarks")
    @Published var history: [Entry] = BrowserModel.load("browser.history")
    let isPrivate: Bool

    static func load(_ k: String) -> [Entry] {
        (UserDefaults.standard.data(forKey: k)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }
    func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(bookmarks), forKey: "browser.bookmarks")
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(history.prefix(300))), forKey: "browser.history")
    }
    var isBookmarked: Bool { bookmarks.contains { $0.url == web.url?.absoluteString } }
    func toggleBookmark() {
        guard let u = web.url?.absoluteString else { return }
        if let i = bookmarks.firstIndex(where: { $0.url == u }) { bookmarks.remove(at: i) }
        else { bookmarks.insert(Entry(title: title.isEmpty ? (web.url?.host ?? u) : title, url: u), at: 0) }
        persist()
    }
    func clearHistory() { history = []; persist() }

    init(privateMode: Bool = false) {
        isPrivate = privateMode
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = privateMode ? .nonPersistent() : .default()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = .all
        web = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .clear
        obs = [
            web.observe(\.canGoBack) { w, _ in Task { @MainActor in self.canBack = w.canGoBack } },
            web.observe(\.canGoForward) { w, _ in Task { @MainActor in self.canForward = w.canGoForward } },
            web.observe(\.isLoading) { w, _ in Task { @MainActor in self.loading = w.isLoading } },
            web.observe(\.estimatedProgress) { w, _ in Task { @MainActor in self.progress = w.estimatedProgress } },
            web.observe(\.url) { w, _ in Task { @MainActor in self.address = w.url?.absoluteString ?? self.address } },
            web.observe(\.title) { w, _ in Task { @MainActor in self.title = w.title ?? "" } },
        ]
    }

    /// عنوان أو كلمات بحث
    func go(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var url: URL?
        if t.contains("."), !t.contains(" ") {
            url = URL(string: t.lowercased().hasPrefix("http") ? t : "https://" + t)
        }
        if url == nil {
            let q = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t
            url = URL(string: "https://www.google.com/search?q=" + q)
        }
        if let url { web.load(URLRequest(url: url)) }
    }

    /// يجمع روابط الصوت والفيديو والملفات في الصفحة
    func scan() async {
        let js = """
        (function(){
          var out=[], seen={};
          function add(u,l){ if(!u||u.indexOf('blob:')==0||u.indexOf('data:')==0) return; try{u=new URL(u,location.href).href}catch(e){return}
            if(seen[u]) return; seen[u]=1; out.push([u,(l||'').trim().slice(0,80)]); }
          document.querySelectorAll('video,audio').forEach(function(m){ add(m.currentSrc||m.src, m.title||document.title);
            m.querySelectorAll('source').forEach(function(s){ add(s.src, s.type) }) });
          var re=/\\.(mp4|m4v|mov|webm|mkv|mp3|m4a|aac|wav|flac|ogg|opus|pdf|zip|rar|7z|epub|docx?|xlsx?|pptx?|jpe?g|png|gif|webp|heic|apk|ipa|srt)(\\?|#|$)/i;
          document.querySelectorAll('a[href]').forEach(function(a){ if(re.test(a.href)||a.hasAttribute('download')) add(a.href, a.textContent) });
          document.querySelectorAll('img').forEach(function(i){ if(i.naturalWidth>=400) add(i.currentSrc||i.src, i.alt) });
          return out;
        })();
        """
        let r = try? await web.evaluateJavaScript(js)
        let arr = (r as? [[String]]) ?? []
        found = arr.compactMap { $0.count == 2 ? MediaLink(url: $0[0], label: $0[1]) : nil }
    }

    /// ترويسات تنزيل رابط من هذه الصفحة: الكوكيز التي تخص رابط التنزيل نفسه فقط (بقواعد المتصفح)،
    /// فلا تُرسل جلسة موقع لموقع آخر، ولا يُرسل كوكي «آمن» عبر اتصال غير مشفّر
    private func headers(for target: URL?) async -> [String: String] {
        var h: [String: String] = [:]
        if let u = web.url { h["Referer"] = u.absoluteString }
        guard let target, let host = target.host?.lowercased() else { return h }
        let https = target.scheme?.lowercased() == "https"
        let path = target.path.isEmpty ? "/" : target.path
        let cookies = await web.configuration.websiteDataStore.httpCookieStore.allCookies()
        let match = cookies.filter { c in
            let d = c.domain.lowercased()
            let domainOK = d.hasPrefix(".") ? (host == String(d.dropFirst()) || host.hasSuffix(d)) : host == d
            let pathOK = c.path.isEmpty || c.path == "/" || path == c.path || path.hasPrefix(c.path.hasSuffix("/") ? c.path : c.path + "/")
            let expired = c.expiresDate.map { $0 < Date() } ?? false
            return domainOK && pathOK && !expired && (https || !c.isSecure)
        }
        if let c = HTTPCookie.requestHeaderFields(with: match)["Cookie"], !c.isEmpty { h["Cookie"] = c }
        return h
    }

    func download(_ link: String) async {
        let h = await headers(for: URL(string: link))
        if DownloadManager.shared.add(link, headers: h) { message = L("بدأ التنزيل، تابعه من «التنزيلات».") }
    }
}

extension BrowserModel: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        // ملف لا يُعرض في المتصفح أو مرسل كمرفق: يُنزَّل
        if let r = navigationResponse.response as? HTTPURLResponse,
           let cd = r.value(forHTTPHeaderField: "Content-Disposition"), cd.lowercased().contains("attachment") {
            return .download
        }
        return navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.shouldPerformDownload ? .download : .allow
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }

    /// الروابط التي تفتح نافذة جديدة تُفتح في نفس الصفحة
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await scan() }
        if !isPrivate, let u = webView.url?.absoluteString {
            history.removeAll { $0.url == u }
            history.insert(Entry(title: webView.title ?? u, url: u), at: 0)
            persist()
        }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let store = FileStore.shared
        let downloads = store.root.appendingPathComponent(L("التنزيلات"), isDirectory: true)
        try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let dir = store.destination(for: suggestedFilename, base: downloads, source: response.url?.host)
        let dest = store.unique(store.sanitize(suggestedFilename), in: dir)
        pending[ObjectIdentifier(download)] = (dest, response.url?.absoluteString ?? "")
        message = LF("جارٍ تنزيل «%@»…", suggestedFilename)
        return dest
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let (dest, url) = pending.removeValue(forKey: ObjectIdentifier(download)) else { return }
        DownloadManager.shared.recordFinished(name: dest.lastPathComponent, url: url, file: dest)
        FileStore.shared.touch()
        message = LF("اكتمل تنزيل «%@».", dest.lastPathComponent)
        if FilePrefs.autoPhotos {
            let k = FileKind.of(dest, isDir: false)
            if k == .image || k == .video { Task { _ = await FileStore.shared.saveToPhotos([dest]) } }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        pending.removeValue(forKey: ObjectIdentifier(download))
        message = L("تعذّر التنزيل من هذه الصفحة.")
    }
}

/// تخزين مؤقت لوجهات تنزيلات المتصفح
@MainActor private var pending: [ObjectIdentifier: (URL, String)] = [:]

struct WebViewRep: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// المتصفح مع زر التصفّح الخاص (يُعاد إنشاؤه عند التبديل)
struct BrowserView: View {
    @State private var privateMode = false
    var body: some View {
        BrowserInner(privateMode: $privateMode).id(privateMode)
    }
}

struct BrowserInner: View {
    @Binding var privateMode: Bool
    @StateObject private var m: BrowserModel
    init(privateMode: Binding<Bool>) {
        _privateMode = privateMode
        _m = StateObject(wrappedValue: BrowserModel(privateMode: privateMode.wrappedValue))
    }
    @State private var editing = ""
    @State private var showFound = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            bar
            if m.loading { ProgressView(value: m.progress).tint(Theme.gold).frame(height: 2) }
            ZStack(alignment: .bottomTrailing) {
                if m.address.isEmpty { start } else { WebViewRep(web: m.web) }
                if !m.found.isEmpty {
                    Button { showFound = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(LF("تنزيل (%@)", ar(m.found.count))).font(Theme.f(.subheadline, .bold))
                        }
                        .foregroundStyle(.black).padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Capsule().fill(Theme.gold)).shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                    }
                    .padding(16)
                }
            }
            nav
        }
        .sheet(isPresented: $showFound) { foundSheet }
        .overlay(alignment: .top) {
            if let msg = m.message {
                Text(verbatim: msg).font(Theme.f(.footnote, .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Capsule().fill(.ultraThinMaterial)).padding(.top, 60)
                    .task(id: msg) { try? await Task.sleep(for: .seconds(3)); m.message = nil }
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            Image(systemName: m.address.hasPrefix("https") ? "lock.fill" : "globe").font(.system(size: 13)).foregroundStyle(Theme.sub)
            TextField(L("ابحث أو اكتب عنوان موقع"), text: $editing)
                .focused($focused)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.webSearch).submitLabel(.go)
                .onSubmit { m.go(editing); focused = false }
            if m.loading {
                Button { m.web.stopLoading() } label: { Image(systemName: "xmark").foregroundStyle(Theme.sub) }
            } else if !m.address.isEmpty {
                Button { m.web.reload() } label: { Image(systemName: "arrow.clockwise").foregroundStyle(Theme.sub) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
        .padding(.horizontal, 12).padding(.bottom, 8)
        .onChange(of: m.address) { _, a in if !focused { editing = a } }
    }

    private var nav: some View {
        HStack {
            navButton("chevron.backward", m.canBack) { m.web.goBack() }
            navButton("chevron.forward", m.canForward) { m.web.goForward() }
            Spacer()
            if let u = m.web.url {
                Menu {
                    ShareLink(item: u) { Label("مشاركة الرابط", systemImage: "square.and.arrow.up") }
                    Button { Task { await savePDF() } } label: { Label("حفظ الصفحة PDF", systemImage: "doc.richtext") }
                } label: { Image(systemName: "square.and.arrow.up").font(.system(size: 18)).foregroundStyle(.white).frame(width: 44, height: 36) }
                Spacer()
                navButton(m.isBookmarked ? "star.fill" : "star", true) { m.toggleBookmark() }
            }
            Spacer()
            navButton(privateMode ? "eyeglasses" : "eye.slash", true) { privateMode.toggle() }
            Spacer()
            navButton("house", !m.address.isEmpty) { m.web.stopLoading(); m.address = ""; editing = "" }
            Spacer()
            navButton("arrow.down.doc", !m.address.isEmpty) { Task { await m.scan(); showFound = true } }
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
    }

    private func navButton(_ icon: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 18, weight: .medium)).frame(width: 44, height: 36) }
            .foregroundStyle(on ? Color.white : Color.white.opacity(0.3)).disabled(!on)
    }

    private var start: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "safari").font(.system(size: 44, weight: .light)).foregroundStyle(Theme.gold.opacity(0.85)).padding(.top, 30)
                Text("المتصفح").font(Theme.f(.title2)).foregroundStyle(.white)
                Text("تصفّح أي موقع، وعند وجود ملف صوت أو فيديو أو مستند في الصفحة يظهر زر «تنزيل». الملفات التي يرسلها الموقع للتنزيل تُحفظ تلقائيًا في «التنزيلات».")
                    .font(Theme.f(.footnote)).foregroundStyle(Theme.sub).multilineTextAlignment(.center).padding(.horizontal, 20)
                Text("لا يدعم التنزيل من المنصات التي تحمي مقاطعها مثل يوتيوب ونتفليكس.")
                    .font(Theme.f(.caption)).foregroundStyle(Theme.sub.opacity(0.8)).multilineTextAlignment(.center).padding(.horizontal, 20)
                if privateMode {
                    Label("تصفّح خاص: لا يُحفظ السجل ولا ملفات تعريف الارتباط", systemImage: "eye.slash")
                        .font(Theme.f(.footnote, .bold)).foregroundStyle(Theme.gold)
                }
                if !m.bookmarks.isEmpty { links(L("الإشارات المرجعية"), m.bookmarks, clear: nil) }
                if !m.history.isEmpty && !privateMode { links(L("السجل"), Array(m.history.prefix(15)), clear: { m.clearHistory() }) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// حفظ الصفحة الحالية PDF في «التنزيلات»
    private func savePDF() async {
        guard let data = try? await m.web.pdf() else { m.message = L("تعذّر حفظ الصفحة."); return }
        let store = FileStore.shared
        let dir = store.root.appendingPathComponent(L("التنزيلات"), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = store.sanitize((m.title.isEmpty ? (m.web.url?.host ?? "page") : m.title)) + ".pdf"
        if let u = store.importData(data, name: name, to: dir) { m.message = LF("حُفظت «%@»", u.lastPathComponent) }
    }

    private func links(_ title: String, _ list: [BrowserModel.Entry], clear: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: title).font(Theme.f(.headline)).foregroundStyle(.white)
                Spacer()
                if let clear { Button(L("مسح السجل"), action: clear).font(Theme.f(.footnote, .bold)).foregroundStyle(Theme.gold) }
            }
            ForEach(list) { e in
                Button { editing = e.url; m.go(e.url) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "globe").foregroundStyle(Theme.sub)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: e.title).font(Theme.f(.subheadline)).foregroundStyle(.white).lineLimit(1)
                            Text(verbatim: URL(string: e.url)?.host ?? e.url).font(Theme.f(.caption)).foregroundStyle(Theme.sub).lineLimit(1)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.top, 10)
    }

    private var foundSheet: some View {
        NavigationStack {
            List {
                if m.found.isEmpty {
                    Text("لم يُعثر على ملفات قابلة للتنزيل في هذه الصفحة.").foregroundStyle(Theme.sub)
                }
                ForEach(m.found) { f in
                    let kind = FileKind.of(URL(string: f.url) ?? URL(fileURLWithPath: f.url), isDir: false)
                    Button {
                        Task { await m.download(f.url) }
                        showFound = false
                    } label: {
                        HStack(spacing: 12) {
                            Badge(name: kind.icon, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: (URL(string: f.url)?.lastPathComponent.removingPercentEncoding).flatMap { $0.isEmpty ? nil : $0 } ?? f.url)
                                    .font(Theme.f(.subheadline, .medium)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                                if !f.label.isEmpty {
                                    Text(verbatim: f.label).font(Theme.f(.caption)).foregroundStyle(Theme.sub).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.down.circle").foregroundStyle(Theme.gold)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .glassList()
            .navigationTitle("ملفات في الصفحة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { showFound = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}
