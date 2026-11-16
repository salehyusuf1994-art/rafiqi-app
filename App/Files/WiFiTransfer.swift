import SwiftUI
import Network

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

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            l.newConnectionHandler = { conn in HTTPConn(conn: conn).start() }
            l.stateUpdateHandler = { st in
                Task { @MainActor in
                    switch st {
                    case .ready: WiFiServer.shared.running = true
                    case .failed, .cancelled: WiFiServer.shared.running = false
                    default: break
                    }
                }
            }
            l.start(queue: queue)
            listener = l
            address = Self.wifiIP().map { "http://\($0):\(port)" }
            if !awake { KeepAwake.begin(); awake = true }
        } catch {
            lastEvent = L("تعذّر تشغيل النقل. تأكّد من الاتصال بشبكة واي فاي.")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
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
            let dest = unique(name, in: dir)
            FileManager.default.createFile(atPath: dest.path, contents: nil)
            file = try? FileHandle(forWritingTo: dest)
            target = dest
            remaining = Int(headers["content-length"] ?? "0") ?? 0
            if !body.isEmpty { file?.write(body); remaining -= body.count }
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

    /// يمنع الخروج من مجلد الملفات أو الوصول إلى المخفي
    private func safe(_ rel: String) -> URL? {
        let clean = rel.split(separator: "/").filter { $0 != ".." && $0 != "." && !$0.hasPrefix(".") }.joined(separator: "/")
        let u = clean.isEmpty ? root : root.appendingPathComponent(clean)
        return u.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path) ? u : nil
    }

    private func unique(_ name: String, in dir: URL) -> URL {
        var u = dir.appendingPathComponent(name)
        let ext = (name as NSString).pathExtension, base = (name as NSString).deletingPathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: u.path) {
            u = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"); n += 1
        }
        return u
    }

    private func readBody() {
        guard remaining > 0 else { return finishUpload() }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [self] data, _, done, err in
            if let data, !data.isEmpty { file?.write(data); remaining -= data.count }
            if remaining <= 0 { finishUpload() }
            else if done || err != nil {
                try? file?.close()
                if let target { try? FileManager.default.removeItem(at: target) }
                conn.cancel()
            } else { readBody() }
        }
    }

    private func finishUpload() {
        try? file?.close()
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
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(size)\r\nContent-Disposition: attachment; filename*=UTF-8''\(name)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8), completion: .contentProcessed { [self] _ in pump(h) })
    }

    private func pump(_ h: FileHandle) {
        let chunk = h.readData(ofLength: 512 * 1024)
        if chunk.isEmpty {
            try? h.close()
            conn.send(content: nil, isComplete: true, completion: .contentProcessed { [self] _ in conn.cancel() })
            return
        }
        conn.send(content: chunk, completion: .contentProcessed { [self] e in
            if e != nil { try? h.close(); conn.cancel() } else { pump(h) }
        })
    }

    private func reply(_ code: Int, _ type: String, _ body: Data) {
        let status = code == 200 ? "OK" : "Error"
        var d = Data("HTTP/1.1 \(code) \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        d.append(body)
        conn.send(content: d, completion: .contentProcessed { [self] _ in conn.cancel() })
    }

    /// صفحة المتصفح في الكمبيوتر (بالعربية، بدون مكتبات خارجية)
    private func page() -> String {
        """
        <!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>رفيقي — ملفاتي</title>
        <style>
        body{margin:0;font-family:-apple-system,"Segoe UI",Tahoma,sans-serif;background:#0b0c12;color:#eee}
        header{padding:20px 28px;background:#14151d;border-bottom:1px solid #2a2b35;display:flex;gap:12px;align-items:center;flex-wrap:wrap}
        h1{font-size:20px;margin:0;color:#e3c27f;flex:1}
        button,.btn{background:#e3c27f;color:#000;border:0;border-radius:10px;padding:9px 16px;font-size:15px;cursor:pointer;font-weight:600}
        .ghost{background:#24252f;color:#eee}
        main{padding:16px 28px}#crumbs{margin:6px 0 14px;color:#aaa}#crumbs a{color:#e3c27f;text-decoration:none;cursor:pointer}
        table{width:100%;border-collapse:collapse}td{padding:11px 8px;border-bottom:1px solid #22232c}
        td.s{color:#999;white-space:nowrap;width:120px}a.f{color:#fff;text-decoration:none;cursor:pointer}
        #drop{border:2px dashed #3a3b47;border-radius:16px;padding:26px;text-align:center;color:#aaa;margin-bottom:16px}
        #drop.on{border-color:#e3c27f;color:#e3c27f}#prog{color:#e3c27f;margin:8px 0}
        </style></head><body>
        <header><h1>رفيقي — ملفاتي</h1>
        <button class="ghost" onclick="mk()">مجلد جديد</button>
        <label class="btn">رفع ملفات<input id="pick" type="file" multiple hidden></label></header>
        <main><div id="drop">اسحب الملفات وأفلتها هنا لرفعها إلى الجوال</div><div id="prog"></div>
        <div id="crumbs"></div><table id="t"></table></main>
        <script>
        var cur='';
        function esc(s){return s.replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
        function sz(n){if(n<1024)return n+' B';var u=['KB','MB','GB'],i=-1;do{n/=1024;i++}while(n>=1024&&i<2);return n.toFixed(1)+' '+u[i]}
        function load(p){cur=p;fetch('/list?path='+encodeURIComponent(p)).then(r=>r.json()).then(function(d){
          var parts=p?p.split('/'):[],h='<a onclick="load(\\'\\')">ملفاتي</a>',acc='';
          parts.forEach(function(x){acc+=(acc?'/':'')+x;h+=' / <a onclick="load(\\''+esc(acc).replace(/'/g,"\\\\'")+'\\')">'+esc(x)+'</a>'});
          document.getElementById('crumbs').innerHTML=h;
          var rows=d.items.map(function(it){var full=(p?p+'/':'')+it.name;var j=JSON.stringify(full).replace(/"/g,'&quot;');
            return '<tr><td>'+(it.dir?'📁 <a class="f" onclick="load('+j+')">':'📄 <a class="f" href="/dl?path='+encodeURIComponent(full)+'">')+esc(it.name)+'</a></td><td class="s">'+(it.dir?'':sz(it.size))+'</td></tr>'}).join('');
          document.getElementById('t').innerHTML=rows||'<tr><td style="color:#888">المجلد فارغ</td></tr>'})}
        function up(files){var list=Array.from(files),i=0;function next(){if(i>=list.length){document.getElementById('prog').textContent='اكتمل الرفع ✓';load(cur);return}
          var f=list[i++],x=new XMLHttpRequest();x.open('PUT','/put?path='+encodeURIComponent(cur)+'&name='+encodeURIComponent(f.name));
          x.upload.onprogress=function(e){document.getElementById('prog').textContent='يرفع '+f.name+' — '+Math.round(e.loaded/e.total*100)+'%'};
          x.onload=next;x.onerror=function(){document.getElementById('prog').textContent='تعذّر رفع '+f.name;next()};x.send(f)}next()}
        function mk(){var n=prompt('اسم المجلد');if(n)fetch('/mkdir?path='+encodeURIComponent(cur)+'&name='+encodeURIComponent(n),{method:'POST'}).then(function(){load(cur)})}
        document.getElementById('pick').onchange=function(e){up(e.target.files)};
        var d=document.getElementById('drop');d.ondragover=function(e){e.preventDefault();d.className='on'};d.ondragleave=function(){d.className=''};
        d.ondrop=function(e){e.preventDefault();d.className='';up(e.dataTransfer.files)};load('');
        </script></body></html>
        """
    }
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
                        step(3, "افتح العنوان الظاهر في متصفح الكمبيوتر، ثم ارفع الملفات أو نزّلها.")
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
    }

    private func step(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(verbatim: ar(n)).font(Theme.f(.subheadline, .bold)).foregroundStyle(.black)
                .frame(width: 24, height: 24).background(Circle().fill(Theme.gold))
            Text(L(t)).font(Theme.f(.subheadline)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
        }
    }
}
