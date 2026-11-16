import Foundation

/// منشورات x.com / twitter.com: تُقرأ من بيانات التضمين الرسمية (نفس ما تعرضه أداة «تضمين المنشور»)
/// فيظهر مقطع المنشور نفسه بكل جوداته، بدل كل المقاطع الموجودة في الصفحة (الردود والمقترحات)
enum XExtractor {
    /// رقم المنشور من رابط x.com أو twitter.com
    static func statusID(_ url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              ["x.com", "twitter.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        let parts = url.pathComponents
        guard let i = parts.firstIndex(where: { $0 == "status" || $0 == "statuses" }), i + 1 < parts.count else { return nil }
        let id = parts[i + 1].prefix { $0.isNumber }
        return id.count >= 5 ? String(id) : nil
    }

    static func probe(_ url: URL) async -> LinkProbe? {
        guard let id = statusID(url), let n = Double(id) else { return nil }
        var c = URLComponents(string: "https://cdn.syndication.twimg.com/tweet-result")!
        c.queryItems = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "lang", value: "ar"),
                        URLQueryItem(name: "token", value: token(n))]
        var req = URLRequest(url: c.url!)
        req.setValue(LinkInspector.ua, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // وسائط المنشور نفسه، وإن خلا منها فوسائط المنشور المقتبس
        var media = json["mediaDetails"] as? [[String: Any]] ?? []
        if media.isEmpty, let q = json["quoted_tweet"] as? [String: Any] { media = q["mediaDetails"] as? [[String: Any]] ?? [] }
        guard !media.isEmpty else { return nil }

        let videos = media.filter { ["video", "animated_gif"].contains($0["type"] as? String ?? "") }
        var items: [FoundItem] = []
        var thumb: URL?
        for (k, m) in media.enumerated() {
            let type = m["type"] as? String ?? ""
            let still = (m["media_url_https"] as? String).flatMap(URL.init(string:))
            if thumb == nil { thumb = still }
            let group = videos.count > 1 ? (videos.firstIndex { ($0["media_url_https"] as? String) == (m["media_url_https"] as? String) }).map { $0 + 1 } : nil
            if type == "photo", let s = m["media_url_https"] as? String, let u = URL(string: s + "?name=orig") {
                items.append(FoundItem(url: u, kind: .image, height: nil, size: nil, group: nil))
                continue
            }
            guard let info = m["video_info"] as? [String: Any], let vars = info["variants"] as? [[String: Any]] else { continue }
            for v in vars where (v["content_type"] as? String) == "video/mp4" {
                guard let s = v["url"] as? String, let u = URL(string: s) else { continue }
                items.append(FoundItem(url: u, kind: .video, height: FoundItem.height(in: u), size: nil, group: group))
            }
            _ = k
        }
        guard !items.isEmpty else { return nil }

        // الأحجام بطلب صغير لكل رابط، والترتيب من الأعلى دقة
        let sized = await LinkInspector.details(items.map(\.url), referer: "https://x.com/")
        var bySize: [URL: Int64] = [:]
        for s in sized { if let z = s.size { bySize[s.url] = z } }
        items = items.map { var x = $0; x.size = bySize[x.url]; return x }
        items.sort { a, b in
            if (a.group ?? 0) != (b.group ?? 0) { return (a.group ?? 0) < (b.group ?? 0) }
            if a.kind != b.kind { return a.kind == .video }
            return (a.height ?? 0) > (b.height ?? 0)
        }
        var seen = Set<String>()
        items = items.filter { it in
            guard it.kind == .video, let h = it.height else { return true }
            return seen.insert("\(it.group ?? 0)-\(h)").inserted
        }

        let user = json["user"] as? [String: Any]
        var p = LinkProbe(url: url, kind: .page, name: "x.com", size: nil, mime: "text/html")
        p.items = items
        p.found = items.map(\.url)
        p.thumb = thumb
        p.title = (user?["name"] as? String) ?? (json["text"] as? String).map { String($0.prefix(80)) }
        return p
    }

    /// مفتاح بيانات التضمين: (id / 1e15 × π) بالأساس ٣٦ بدون الأصفار والنقطة، مطابقًا لـ JavaScript
    static func token(_ id: Double) -> String {
        let s = radix36(id / 1e15 * Double.pi)
        return String(s.filter { $0 != "0" && $0 != "." })
    }

    /// تحويل عدد عشري إلى الأساس ٣٦ بخوارزمية Number.prototype.toString(36) نفسها
    static func radix36(_ value: Double) -> String {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        var integer = value.rounded(.down)
        var fraction = value - integer
        var delta = max(0.5 * (value.nextUp - value), Double(0).nextUp)
        var frac: [Int] = []
        if fraction >= delta {
            repeat {
                fraction *= 36; delta *= 36
                let d = Int(fraction)
                frac.append(d); fraction -= Double(d)
                if fraction > 0.5 || (fraction == 0.5 && (d & 1) == 1), fraction + delta > 1 {
                    // تقريب للأعلى
                    while true {
                        guard let last = frac.popLast() else { integer += 1; break }
                        if last + 1 < 36 { frac.append(last + 1); break }
                    }
                    break
                }
            } while fraction >= delta
        }
        var n = UInt64(integer)
        var s = n == 0 ? "0" : ""
        while n > 0 { s = String(chars[Int(n % 36)]) + s; n /= 36 }
        if !frac.isEmpty { s += "." + String(frac.map { chars[$0] }) }
        return s
    }
}
