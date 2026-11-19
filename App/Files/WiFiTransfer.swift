import SwiftUI
import Network
import Security

// MARK: - نقل الملفات عبر الواي فاي: خادم ويب صغير داخل التطبيق يفتحه الكمبيوتر من المتصفح

@MainActor
final class WiFiServer: ObservableObject {
    static let shared = WiFiServer()
    @Published private(set) var running = false
    @Published private(set) var address: String?
    @Published private(set) var lastEvent: String?
    private var listener: NWListener?
    private var awake = false
    let port: UInt16 = 8080
    private let queue = DispatchQueue(label: "rafiqi.wifi")

    /// رمز الدخول (٨ أرقام) يتغيّر مع كل تشغيل؛ يُطلب في متصفح الكمبيوتر
    @Published private(set) var code = ""
    /// بصمة شهادة التشفير — يطابقها المستخدم في المتصفح
    @Published private(set) var fingerprint = ""
    private var idleTimer: Timer?

    func start() {
        guard listener == nil else { return }
        // التشفير إلزامي: بدون عنوان واي فاي أو شهادة لا يعمل النقل أبدًا (لا رجوع لـ HTTP)
        guard let ip = Self.wifiIP() else { lastEvent = L("تعذّر تشغيل النقل. تأكّد من الاتصال بشبكة واي فاي."); return }
        guard let tls = WiFiTLS.identity(ip: ip), let secID = sec_identity_create(tls.identity) else {
            lastEvent = L("تعذّر تجهيز التشفير، فلم يُشغَّل النقل.")
            return
        }
        var bytes = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let r = bytes.reduce(0) { ($0 << 8) | Int($1) } % 100_000_000
        code = String(format: "%08d", r)
        fingerprint = tls.fingerprint
        WiFiGuard.reset(code: code)
        do {
            let tlsOpts = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(tlsOpts.securityProtocolOptions, secID)
            sec_protocol_options_set_min_tls_protocol_version(tlsOpts.securityProtocolOptions, .TLSv12)
            let params = NWParameters(tls: tlsOpts, tcp: NWProtocolTCP.Options())
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            // الشبكة المحلية فقط: اتصال من عنوان عام (إنترنت عبر بيانات الجوال) يُرفض قبل أي شيء
            l.newConnectionHandler = { conn in
                guard WiFiServer.isLocal(conn.endpoint) else { conn.cancel(); return }
                HTTPConn(conn: conn).start()
            }
            l.stateUpdateHandler = { st in
                Task { @MainActor in
                    switch st {
                    case .ready: WiFiServer.shared.running = true
                    // فشل المستمع (انقطاع الشبكة مثلًا): نوقف كل شيء حتى يعمل زر «تشغيل» من جديد
                    case .failed:
                        WiFiServer.shared.stop()
                        WiFiServer.shared.lastEvent = L("انقطع النقل. تأكّد من الاتصال بشبكة واي فاي ثم شغّله من جديد.")
                    case .cancelled: WiFiServer.shared.running = false
                    default: break
                    }
                }
            }
            l.start(queue: queue)
            listener = l
            address = "https://\(ip):\(port)"
            if !awake { KeepAwake.begin(); awake = true }
            // يتوقف تلقائيًا بعد ١٠ دقائق بلا استخدام، أو بعد محاولات رمز خاطئة كثيرة
            idleTimer?.invalidate()
            idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                Task { @MainActor in
                    let s = WiFiServer.shared
                    if WiFiGuard.blocked {
                        s.stop(); s.lastEvent = L("أُوقف النقل: محاولات رمز خاطئة كثيرة من جهاز على الشبكة.")
                    } else if Date().timeIntervalSince(WiFiGuard.lastActivity) > 600 {
                        s.stop(); s.lastEvent = L("أُوقف النقل تلقائيًا بعد ١٠ دقائق بلا استخدام.")
                    }
                }
            }
        } catch {
            lastEvent = L("تعذّر تشغيل النقل. تأكّد من الاتصال بشبكة واي فاي.")
        }
    }

    /// عنوان من الشبكة المحلية (واي فاي، نقطة اتصال شخصية، أو الجهاز نفسه)
    nonisolated static func isLocal(_ e: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = e else { return false }
        switch host {
        case .ipv4(let a):
            let b = [UInt8](a.rawValue)
            guard b.count == 4 else { return false }
            return b[0] == 10 || b[0] == 127 || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && b[1] == 168)
                || (b[0] == 169 && b[1] == 254)
        case .ipv6(let a):
            let b = [UInt8](a.rawValue)
            guard b.count == 16 else { return false }
            if b[0] == 0xfe && (b[1] & 0xc0) == 0x80 { return true }        // fe80::/10
            if (b[0] & 0xfe) == 0xfc { return true }                        // fc00::/7
            if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return true } // ::1
            // IPv4 داخل IPv6 (::ffff:a.b.c.d)
            if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xff && b[11] == 0xff,
               let v4 = IPv4Address(Data(b[12..<16])) { return isLocal(.hostPort(host: .ipv4(v4), port: 0)) }
            return false
        default:
            return false
        }
    }

    func stop() {
        idleTimer?.invalidate(); idleTimer = nil
        code = ""
        fingerprint = ""
        WiFiGuard.reset(code: nil)
        listener?.cancel()
        listener = nil
        WiFiConns.cancelAll()
        running = false
        if awake { KeepAwake.end(); awake = false }
    }

    func note(_ s: String) { lastEvent = s; FileStore.shared.touch() }

    /// عنوان الجوال في شبكة الواي فاي
    nonisolated static func wifiIP() -> String? {
        var addr: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            guard let sa = i.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: i.ifa_name)
            guard name == "en0" || name == "bridge100" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            addr = String(cString: host)
            if name == "en0" { break }
        }
        return addr
    }
}

/// رمز الدخول ومحاولات الخطأ (تُقرأ من اتصالات الخلفية)
enum WiFiGuard {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var code: String?
    nonisolated(unsafe) private static var fails = 0
    nonisolated(unsafe) private static var last = Date()
    /// جلسات المتصفح: رمز عشوائي ٣٢ بايت يُعطى بعد إدخال الرمز الصحيح (لا يُحفظ رمز الدخول في المتصفح)
    nonisolated(unsafe) private static var sessions: Set<String> = []

    static func reset(code c: String?) { lock.lock(); code = c; fails = 0; last = Date(); sessions = []; lock.unlock() }
    /// يتحقق من الرمز ويرجع جلسة جديدة
    static func login(_ given: String?) -> String? {
        guard check(given) else { return nil }
        var b = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, b.count, &b) == errSecSuccess else { return nil }
        let t = Data(b).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        lock.lock(); sessions.insert(t); lock.unlock()
        return t
    }
    static func valid(_ token: String?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard code != nil, fails < 10, let token, sessions.contains(token) else { return false }
        last = Date()
        return true
    }
    static var blocked: Bool { lock.lock(); defer { lock.unlock() }; return fails >= 10 }
    /// نقل جارٍ (رفع أو تنزيل كبير) يُعدّ استخدامًا، فلا يتوقف الخادم في منتصفه بعد ١٠ دقائق
    static func touch() { lock.lock(); last = Date(); lock.unlock() }
    static var lastActivity: Date { lock.lock(); defer { lock.unlock() }; return last }
    /// يتحقق من الرمز؛ بعد ١٠ محاولات خاطئة يُرفض كل شيء حتى يُعاد التشغيل
    static func check(_ given: String?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let code, fails < 10 else { return false }
        if given == code { last = Date(); return true }
        if given != nil { fails += 1 }
        return false
    }
}

/// الاتصالات المفتوحة: تُقطع كلها عند إيقاف النقل
enum WiFiConns {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var all: [ObjectIdentifier: NWConnection] = [:]
    static func add(_ c: NWConnection) { lock.lock(); all[ObjectIdentifier(c)] = c; lock.unlock() }
    static func remove(_ c: NWConnection) { lock.lock(); all[ObjectIdentifier(c)] = nil; lock.unlock() }
    static func cancelAll() {
        lock.lock(); let list = Array(all.values); all = [:]; lock.unlock()
        list.forEach { $0.cancel() }
    }
}

/// اتصال HTTP واحد (طلب واحد ثم إغلاق)
final class HTTPConn {
    let conn: NWConnection
    private var head = Data()
    private var file: FileHandle?
    private var remaining = 0
    private var target: URL?
    private let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    init(conn: NWConnection) { self.conn = conn }

    func start() {
        WiFiConns.add(conn)
        conn.stateUpdateHandler = { [conn] st in
            switch st {
            case .failed, .cancelled: WiFiConns.remove(conn)
            default: break
            }
        }
        conn.start(queue: DispatchQueue(label: "rafiqi.wifi.conn"))
        readHead()
    }

    private func readHead() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, done, err in
            if let data { head.append(data) }
            if let r = head.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = head[..<r.lowerBound]
                let body = head[r.upperBound...]
                handle(String(decoding: headerData, as: UTF8.self), body: Data(body))
            } else if done || err != nil || head.count > 64 * 1024 {
                conn.cancel()
            } else {
                readHead()
            }
        }
    }

    private func handle(_ header: String, body: Data) {
        let lines = header.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else { return reply(400, "text/plain", Data("bad request".utf8)) }
        let method = String(parts[0]), full = String(parts[1])
        var headers: [String: String] = [:]
        for l in lines.dropFirst() {
            if let i = l.firstIndex(of: ":") { headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) }
        }
        let comps = URLComponents(string: "http://x" + full)
        let path = comps?.path ?? "/"
        let q = Dictionary((comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let rel = q["path"] ?? ""
        guard let dir = safe(rel) else { return reply(403, "text/plain", Data("forbidden".utf8)) }
        // الجلسة: رمز عشوائي في كوكي محمي (HttpOnly وSecure وSameSite=Strict)، لا رمز الدخول نفسه
        let cookie = (headers["cookie"] ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("rfs=") }.map { String($0.dropFirst(4)) }
        // السكربتات ملفات ثابتة بلا بيانات: تُخدم قبل الدخول، ولا سكربت داخل الصفحة نفسها (CSP بلا unsafe-inline)
        if method == "GET" && path == "/login.js" { return reply(200, "text/javascript; charset=utf-8", Data(Self.loginJS.utf8)) }
        if method == "GET" && path == "/app.js" { return reply(200, "text/javascript; charset=utf-8", Data(Self.appJS.utf8)) }
        if method == "POST" && path == "/login" {
            // الرمز في جسم الطلب (لا في الرابط حتى لا يُحفظ في سجل المتصفح)؛ قد يصل الجسم في حزمة لاحقة
            let need = min(64, Int(headers["content-length"] ?? "0") ?? 0)
            return readAll(body, need: need) { [self] full in
                let given = String(decoding: full, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !given.isEmpty, let token = WiFiGuard.login(given) else { return reply(401, "text/plain", Data("no".utf8)) }
                reply(200, "text/plain", Data("ok".utf8), extra: "Set-Cookie: rfs=\(token); Path=/; HttpOnly; Secure; SameSite=Strict\r\n")
            }
        }
        guard WiFiGuard.valid(cookie) else {
            return path == "/" ? reply(200, "text/html; charset=utf-8", Data(loginPage().utf8))
                               : reply(401, "text/plain", Data("code required".utf8))
        }

        switch (method, path) {
        case ("GET", "/"):
            reply(200, "text/html; charset=utf-8", Data(page().utf8))
        case ("GET", "/list"):
            reply(200, "application/json; charset=utf-8", list(dir, rel: rel))
        case ("GET", "/dl"):
            sendFile(dir)
        case ("PUT", "/put"):
            let name = (q["name"] ?? "file").replacingOccurrences(of: "/", with: "-")
            guard !name.hasPrefix(".") else { return reply(400, "text/plain", Data()) }
            let length = Int(headers["content-length"] ?? "0") ?? 0
            // لا نبدأ رفعًا لا تتسع له مساحة الجوال (مع هامش ٢٠٠ م.ب للنظام)
            if let free = (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage,
               Int64(length) > free - 200_000_000 {
                return reply(507, "text/plain", Data("no space".utf8))
            }
            let dest = unique(name, in: dir)
            guard FileManager.default.createFile(atPath: dest.path, contents: nil),
                  let h = try? FileHandle(forWritingTo: dest) else { return reply(500, "text/plain", Data()) }
            file = h
            target = dest
            remaining = length
            if !body.isEmpty {
                guard write(body) else { return failUpload() }
                remaining -= body.count
            }
            readBody()
        case ("POST", "/mkdir"):
            let name = (q["name"] ?? "").replacingOccurrences(of: "/", with: "-")
            guard !name.isEmpty, !name.hasPrefix(".") else { return reply(400, "text/plain", Data()) }
            try? FileManager.default.createDirectory(at: unique(name, in: dir), withIntermediateDirectories: true)
            Task { @MainActor in WiFiServer.shared.note(LF("أُنشئ مجلد «%@» من الكمبيوتر", name)) }
            reply(200, "text/plain", Data("ok".utf8))
        default:
            reply(404, "text/plain", Data("not found".utf8))
        }
    }

    /// يكمل قراءة جسم طلب صغير حتى طوله المعلن
    private func readAll(_ have: Data, need: Int, _ done: @escaping (Data) -> Void) {
        guard have.count < need else { return done(have) }
        conn.receive(minimumIncompleteLength: 1, maximumLength: need - have.count) { [self] data, _, end, err in
            var d = have
            if let data { d.append(data) }
            if d.count >= need || end || err != nil { done(d) } else { readAll(d, need: need, done) }
        }
    }

    /// يمنع الخروج من مجلد الملفات أو الوصول إلى المخفي
    private func safe(_ rel: String) -> URL? {
        let clean = rel.split(separator: "/").filter { $0 != ".." && $0 != "." && !$0.hasPrefix(".") }.joined(separator: "/")
        let u = clean.isEmpty ? root : root.appendingPathComponent(clean)
        let p = u.standardizedFileURL.path, r = root.standardizedFileURL.path
        return p == r || p.hasPrefix(r + "/") ? u : nil
    }

    private func unique(_ name: String, in dir: URL) -> URL { uniqueFileURL(name, in: dir) }

    private func readBody() {
        guard remaining > 0 else { return finishUpload() }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [self] data, _, done, err in
            if let data, !data.isEmpty {
                guard write(data) else { return failUpload() }
                remaining -= data.count
                WiFiGuard.touch()
            }
            if remaining <= 0 { finishUpload() }
            else if done || err != nil {
                try? file?.close(); file = nil
                if let target { try? FileManager.default.removeItem(at: target) }
                conn.cancel()
            } else { readBody() }
        }
    }

    /// كتابة آمنة: امتلاء المساحة يرجع خطأ بدل أن يُسقط التطبيق
    private func write(_ d: Data) -> Bool {
        guard let file else { return false }
        do { try file.write(contentsOf: d); return true } catch { return false }
    }

    /// فشل الكتابة: يُحذف الجزء الناقص ويُبلَّغ المتصفح
    private func failUpload() {
        try? file?.close(); file = nil
        if let target { try? FileManager.default.removeItem(at: target) }
        reply(507, "text/plain", Data("write failed".utf8))
    }

    private func finishUpload() {
        try? file?.close(); file = nil
        let n = target?.lastPathComponent ?? ""
        Task { @MainActor in WiFiServer.shared.note(LF("وصل «%@» من الكمبيوتر", n)) }
        reply(200, "text/plain", Data("ok".utf8))
    }

    private func list(_ dir: URL, rel: String) -> Data {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let items: [[String: Any]] = urls.map { u in
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            return ["name": u.lastPathComponent, "dir": v?.isDirectory ?? false, "size": v?.fileSize ?? 0,
                    "date": Int((v?.contentModificationDate ?? Date()).timeIntervalSince1970)]
        }.sorted { (($0["dir"] as? Bool) == true ? 0 : 1, $0["name"] as? String ?? "") < (($1["dir"] as? Bool) == true ? 0 : 1, $1["name"] as? String ?? "") }
        return (try? JSONSerialization.data(withJSONObject: ["path": rel, "items": items])) ?? Data("{}".utf8)
    }

    private func sendFile(_ u: URL) {
        guard let h = try? FileHandle(forReadingFrom: u),
              let size = (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return reply(404, "text/plain", Data()) }
        let name = u.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "file"
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(size)\r\nContent-Disposition: attachment; filename*=UTF-8''\(name)\r\nConnection: close\r\n\(Self.secureHeaders)\r\n"
        conn.send(content: Data(head.utf8), completion: .contentProcessed { [self] _ in pump(h) })
    }

    private func pump(_ h: FileHandle) {
        let chunk = h.readData(ofLength: 512 * 1024)
        if chunk.isEmpty {
            try? h.close()
            conn.send(content: nil, isComplete: true, completion: .contentProcessed { [self] _ in conn.cancel() })
            return
        }
        WiFiGuard.touch()
        conn.send(content: chunk, completion: .contentProcessed { [self] e in
            if e != nil { try? h.close(); conn.cancel() } else { pump(h) }
        })
    }

    /// ترويسات أمان ثابتة لكل رد
    private static let secureHeaders = "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nReferrer-Policy: no-referrer\r\n"
        + "Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'; form-action 'self'\r\n"

    private func reply(_ code: Int, _ type: String, _ body: Data, extra: String = "") {
        let status = code == 200 ? "OK" : "Error"
        var d = Data("HTTP/1.1 \(code) \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\(Self.secureHeaders)\(extra)\r\n".utf8)
        d.append(body)
        conn.send(content: d, completion: .contentProcessed { [self] _ in conn.cancel() })
    }

    /// نصوص الصفحة بلغة التطبيق
    private static func t(_ ar: String, _ en: String) -> String { Lang.isEN ? en : ar }
    private static var htmlHead: String { Lang.isEN ? #"<html lang="en" dir="ltr">"# : #"<html lang="ar" dir="rtl">"# }

    /// صفحة الرمز: يكتب المستخدم الرمز الظاهر في الجوال
    private func loginPage() -> String {
        let t = Self.t
        return """
        <!doctype html>\(Self.htmlHead)<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(t("رفيقي — رمز الدخول", "Rafiqi — Sign in"))</title>
        <style>body{margin:0;font-family:-apple-system,"Segoe UI",Tahoma,sans-serif;background:#0b0c12;color:#eee;display:flex;min-height:100vh;align-items:center;justify-content:center}
        .c{background:#14151d;border:1px solid #2a2b35;border-radius:20px;padding:30px;text-align:center;width:300px}
        h1{color:#e3c27f;font-size:20px;margin:0 0 8px}p{color:#aaa;font-size:14px}
        input{font-size:28px;letter-spacing:8px;text-align:center;width:100%;box-sizing:border-box;padding:10px;border-radius:12px;border:1px solid #3a3b47;background:#0b0c12;color:#fff;direction:ltr}
        button{margin-top:14px;width:100%;background:#e3c27f;color:#000;border:0;border-radius:12px;padding:11px;font-size:16px;font-weight:600;cursor:pointer}#e{color:#f77;min-height:20px}</style></head><body>
        <div class="c"><h1>\(t("رفيقي — ملفاتي", "Rafiqi — My Files"))</h1><p>\(t("اكتب الرمز الظاهر في صفحة النقل على الجوال", "Enter the code shown on the transfer page on your phone"))</p>
        <input id="k" inputmode="numeric" maxlength="8" autocomplete="off" autofocus><button id="b">\(t("دخول", "Sign in"))</button>
        <p id="e" data-bad="\(t("الرمز غير صحيح", "Wrong code"))"></p></div>
        <script src="/login.js"></script></body></html>
        """
    }

    private static let loginJS = #"""
    function go(){var k=document.getElementById('k').value.replace(/\s/g,''),e=document.getElementById('e');
    fetch('/login',{method:'POST',body:k,credentials:'same-origin'}).then(function(r){if(r.ok){location.reload()}else{e.textContent=e.dataset.bad}}).catch(function(){e.textContent=e.dataset.bad})}
    document.getElementById('b').onclick=go;document.getElementById('k').onkeydown=function(ev){if(ev.key==='Enter')go()};
    """#

    /// صفحة المتصفح في الكمبيوتر (بدون مكتبات خارجية). الأسماء تُكتب نصًا (textContent) فلا يُنفَّذ أي اسم ملف كشيفرة
    private func page() -> String {
        let t = Self.t
        let strings: [String: String] = [
            "root": t("ملفاتي", "My Files"), "empty": t("المجلد فارغ", "This folder is empty"),
            "uploading": t("يرفع", "Uploading"), "failed": t("تعذّر رفع", "Couldn't upload"),
            "done": t("اكتمل الرفع ✓", "Upload complete ✓"),
            "someFailed": t("انتهى الرفع، لكن تعذّر رفع بعض الملفات (عددها: %d)، وقد تكون المساحة ممتلئة", "Finished, but %d file(s) couldn't be uploaded (storage may be full)"),
            "folderName": t("اسم المجلد", "Folder name"),
        ]
        let json = (try? JSONSerialization.data(withJSONObject: strings)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return """
        <!doctype html>\(Self.htmlHead)<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(t("رفيقي — ملفاتي", "Rafiqi — My Files"))</title>
        <style>
        body{margin:0;font-family:-apple-system,"Segoe UI",Tahoma,sans-serif;background:#0b0c12;color:#eee}
        header{padding:20px 28px;background:#14151d;border-bottom:1px solid #2a2b35;display:flex;gap:12px;align-items:center;flex-wrap:wrap}
        h1{font-size:20px;margin:0;color:#e3c27f;flex:1}
        button,.btn{background:#e3c27f;color:#000;border:0;border-radius:10px;padding:9px 16px;font-size:15px;cursor:pointer;font-weight:600}
        .ghost{background:#24252f;color:#eee}
        main{padding:16px 28px}#crumbs{margin:6px 0 14px;color:#aaa}#crumbs a{color:#e3c27f;text-decoration:none;cursor:pointer}
        table{width:100%;border-collapse:collapse}td{padding:11px 8px;border-bottom:1px solid #22232c}td.m{color:#888}
        td.s{color:#999;white-space:nowrap;width:120px}a.f{color:#fff;text-decoration:none;cursor:pointer}
        #drop{border:2px dashed #3a3b47;border-radius:16px;padding:26px;text-align:center;color:#aaa;margin-bottom:16px}
        #drop.on{border-color:#e3c27f;color:#e3c27f}#prog{color:#e3c27f;margin:8px 0}
        </style></head><body>
        <header><h1>\(t("رفيقي — ملفاتي", "Rafiqi — My Files"))</h1>
        <button class="ghost" id="mk">\(t("مجلد جديد", "New folder"))</button>
        <label class="btn">\(t("رفع ملفات", "Upload files"))<input id="pick" type="file" multiple hidden></label></header>
        <main><div id="drop">\(t("اسحب الملفات وأفلتها هنا لرفعها إلى الجوال", "Drag and drop files here to upload them to your phone"))</div><div id="prog"></div>
        <div id="crumbs"></div><table id="t"></table></main>
        <script type="application/json" id="i18n">\(json.replacingOccurrences(of: "</", with: "<\\/"))</script>
        <script src="/app.js"></script></body></html>
        """
    }

    private static let appJS = #"""
    var T=JSON.parse(document.getElementById('i18n').textContent),cur='';
    function $(i){return document.getElementById(i)}
    function el(tag,txt){var e=document.createElement(tag);if(txt!=null)e.textContent=txt;return e}
    function link(txt,fn){var a=el('a',txt);a.href='#';a.onclick=function(ev){ev.preventDefault();fn()};return a}
    function sz(n){if(n<1024)return n+' B';var u=['KB','MB','GB'],i=-1;do{n/=1024;i++}while(n>=1024&&i<2);return n.toFixed(1)+' '+u[i]}
    function load(p){fetch('/list?path='+encodeURIComponent(p),{credentials:'same-origin'}).then(function(r){if(r.status===401){location.reload();throw 0}return r.json()}).then(function(d){
      cur=p;var c=$('crumbs');c.textContent='';c.appendChild(link(T.root,function(){load('')}));
      var acc='';(p?p.split('/'):[]).forEach(function(x){acc+=(acc?'/':'')+x;var to=acc;c.appendChild(document.createTextNode(' / '));c.appendChild(link(x,function(){load(to)}))});
      var t=$('t');t.textContent='';
      if(!d.items.length){var tr=el('tr'),td=el('td',T.empty);td.className='m';tr.appendChild(td);t.appendChild(tr);return}
      d.items.forEach(function(it){var full=(p?p+'/':'')+it.name,tr=el('tr'),td=el('td'),a;
        td.appendChild(document.createTextNode(it.dir?'📁 ':'📄 '));
        if(it.dir){a=link(it.name,function(){load(full)})}else{a=el('a',it.name);a.href='/dl?path='+encodeURIComponent(full)}
        a.className='f';td.appendChild(a);tr.appendChild(td);var s=el('td',it.dir?'':sz(it.size));s.className='s';tr.appendChild(s);t.appendChild(tr)})
    }).catch(function(){})}
    function up(files){var list=Array.from(files),i=0,bad=0;function next(){if(i>=list.length){$('prog').textContent=bad?T.someFailed.replace('%d',bad):T.done;load(cur);return}
      var f=list[i++],x=new XMLHttpRequest();x.open('PUT','/put?path='+encodeURIComponent(cur)+'&name='+encodeURIComponent(f.name));
      x.upload.onprogress=function(e){if(e.total)$('prog').textContent=T.uploading+' '+f.name+' — '+Math.round(e.loaded/e.total*100)+'%'};
      x.onload=function(){if(x.status!==200){bad++;$('prog').textContent=T.failed+' '+f.name}next()};
      x.onerror=function(){bad++;$('prog').textContent=T.failed+' '+f.name;next()};x.send(f)}next()}
    $('mk').onclick=function(){var n=prompt(T.folderName);if(n)fetch('/mkdir?path='+encodeURIComponent(cur)+'&name='+encodeURIComponent(n),{method:'POST',credentials:'same-origin'}).then(function(){load(cur)})};
    $('pick').onchange=function(e){up(e.target.files);e.target.value=''};
    var d=$('drop');d.ondragover=function(e){e.preventDefault();d.className='on'};d.ondragleave=function(){d.className=''};
    d.ondrop=function(e){e.preventDefault();d.className='';up(e.dataTransfer.files)};load('');
    """#
}

struct WiFiTransferView: View {
    @ObservedObject private var server = WiFiServer.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Badge(name: "wifi", size: 76, active: server.running).padding(.top, 10)
                    Text(server.running ? L("النقل يعمل") : L("النقل متوقف")).font(Theme.f(.title3, .bold)).foregroundStyle(.white)
                    if server.running, let a = server.address {
                        VStack(spacing: 8) {
                            Text("افتح هذا العنوان في متصفح الكمبيوتر:").font(Theme.f(.subheadline)).foregroundStyle(Theme.sub)
                            Text(verbatim: a).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundStyle(Theme.gold)
                                .textSelection(.enabled)
                            Button { UIPasteboard.general.string = a } label: { Label("نسخ العنوان", systemImage: "doc.on.doc").font(Theme.f(.subheadline, .bold)) }
                                .foregroundStyle(.white)
                            Divider().overlay(Theme.edge).padding(.vertical, 4)
                            Text("رمز الدخول:").font(Theme.f(.subheadline)).foregroundStyle(Theme.sub)
                            Text(verbatim: server.code).font(.system(size: 30, weight: .heavy, design: .monospaced)).kerning(6).foregroundStyle(.white)
                                .accessibilityIdentifier("wifiCode")
                            Text("لا تعطِ الرمز لأحد. المجلدات المقفلة لا تظهر في النقل.").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                                .multilineTextAlignment(.center)
                            Divider().overlay(Theme.edge).padding(.vertical, 4)
                            Label("الاتصال مشفّر (HTTPS)", systemImage: "lock.fill").font(Theme.f(.subheadline, .bold)).foregroundStyle(.green)
                            Text("سيحذّرك المتصفح أول مرة لأن الشهادة صادرة من جوالك لا من جهة عامة؛ اختر «متقدم» ثم «متابعة». للتأكد أنه جوالك: بصمة الشهادة في المتصفح تبدأ بـ").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                                .multilineTextAlignment(.center)
                            Text(verbatim: server.fingerprint).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                                .textSelection(.enabled)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        .frame(maxWidth: .infinity).glassCard(padding: 18)
                    } else if server.running {
                        Text("الجوال غير متصل بشبكة واي فاي.").font(Theme.f(.subheadline)).foregroundStyle(.orange)
                    }
                    Button {
                        if server.running { server.stop() } else { server.start() }
                    } label: {
                        Text(server.running ? L("إيقاف النقل") : L("تشغيل النقل")).font(Theme.f(.headline))
                            .foregroundStyle(server.running ? .white : .black).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(server.running ? Color.white.opacity(0.12) : Theme.gold))
                    }
                    if let e = server.lastEvent {
                        Text(verbatim: e).font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        step(1, "اجعل الجوال والكمبيوتر على شبكة الواي فاي نفسها.")
                        step(2, "اضغط «تشغيل النقل» وأبقِ هذه الصفحة مفتوحة.")
                        step(3, "افتح العنوان الظاهر في متصفح الكمبيوتر، واكتب رمز الدخول، ثم ارفع الملفات أو نزّلها.")
                        step(4, "يتوقف النقل تلقائيًا إذا خرجت من الصفحة أو بعد ١٠ دقائق بلا استخدام.")
                    }
                    .glassCard(padding: 16)
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle("النقل عبر الواي فاي")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { server.stop(); dismiss() } } }
        }
        .onChange(of: phase) { _, p in if p == .background { server.stop() } }
        // إغلاق الصفحة بالسحب لأسفل يوقف النقل أيضًا (لا يبقى الخادم يعمل في الخلفية)
        .onDisappear { server.stop() }
    }

    private func step(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(verbatim: ar(n)).font(Theme.f(.subheadline, .bold)).foregroundStyle(.black)
                .frame(width: 24, height: 24).background(Circle().fill(Theme.gold))
            Text(L(t)).font(Theme.f(.subheadline)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
        }
    }
}
