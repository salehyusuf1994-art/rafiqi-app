import Foundation
import UIKit
import SwiftUI

// MARK: - أماكن الويدجت على الشاشة
// صغير: ٦ أماكن (٣ صفوف × يمين/يسار) — متوسط: ٣ صفوف

enum Slot: String, CaseIterable, Codable {
    case tr, tl, mr, ml, br, bl   // صغير
    case mt, mm, mb               // متوسط
    case lt, lb                   // كبير: الصفين الأعلى أو الأسفل (إطاره من إطاري المتوسط)

    var isMedium: Bool { self == .mt || self == .mm || self == .mb }
    var isLarge: Bool { self == .lt || self == .lb }

    /// لون المعايرة: ٩ درجات متباعدة ٤٠° (الكبير ما يدخل المعايرة)
    var hue: Double { Double(Slot.allCases.firstIndex(of: self)!) * 40 }
    var calibColor: Color { isLarge ? Color.black : Color(hue: hue / 360, saturation: 1, brightness: 1) }

    static func of(place: String, medium: Bool, large: Bool = false) -> Slot {
        let row = place.first ?? "m"          // t / m / b
        if large { return row == "t" ? .lt : .lb }
        if medium { return row == "t" ? .mt : row == "b" ? .mb : .mm }
        return Slot(rawValue: place) ?? .mr
    }
}

/// إطار ويدجت على الشاشة (نِسَب من حجم الشاشة) + مقاسه بالنقاط
struct Frame: Codable, Equatable {
    var slot: Slot
    var x, y, w, h: Double     // ٠…١
    var pw, ph: Double         // نقاط
    var calibrated = false
    var file: String { "bg_\(slot.rawValue)_\(Int(pw.rounded()))x\(Int(ph.rounded())).jpg" }
}

enum Backdrop {
    static var d: UserDefaults { AppGroup.defaults }

    // ── مقاس الشاشة بالنقاط (يحفظه التطبيق) ──
    static var screenPt: CGSize {
        get {
            if let a = d.array(forKey: "screen_pt") as? [Double], a.count == 2 { return CGSize(width: a[0], height: a[1]) }
            return CGSize(width: 440, height: 956)   // آيفون ١٧ برو ماكس
        }
        set { d.set([Double(newValue.width), Double(newValue.height)], forKey: "screen_pt") }
    }

    // ── الإطارات الافتراضية (أيقونات صغيرة، قياسات ١٧ برو ماكس 1320×2868) ──
    static var defaultFrames: [Frame] {
        let W = 1320.0, H = 2868.0, sp = screenPt
        let rows: [(String, Double)] = [("t", 282), ("m", 934), ("b", 1586)]
        var out: [Frame] = []
        func f(_ s: Slot, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Frame {
            Frame(slot: s, x: x / W, y: y / H, w: w / W, h: h / H, pw: w / W * sp.width, ph: h / H * sp.height)
        }
        for (r, y) in rows {
            out.append(f(Slot(rawValue: r + "r")!, 700, y, 527, 527))
            out.append(f(Slot(rawValue: r + "l")!, 94, y, 527, 527))
            out.append(f(Slot.of(place: r + "r", medium: true), 94, y, 1133, 527))
        }
        return out
    }

    static var calibratedFrames: [Frame] {
        get { (d.data(forKey: "frames")).flatMap { try? JSONDecoder().decode([Frame].self, from: $0) } ?? [] }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "frames") }
    }

    /// كل الإطارات: المعايَرة أولاً، والافتراضية لأي مقاس ما انعاير
    static var frames: [Frame] {
        let cal = calibratedFrames
        let base = cal + defaultFrames.filter { df in !cal.contains { $0.slot == df.slot && close($0, df.pw, df.ph) } }
        return base + largeFrames(from: base)
    }

    /// إطار الويدجت الكبيرة = من أعلى إطار المتوسط الأول إلى أسفل الثاني
    static func largeFrames(from base: [Frame]) -> [Frame] {
        var out: [Frame] = []
        let sp = screenPt
        for (ls, a, b) in [(Slot.lt, Slot.mt, Slot.mm), (Slot.lb, Slot.mm, Slot.mb)] {
            guard let fa = base.first(where: { $0.slot == a }), let fb = base.first(where: { $0.slot == b }) else { continue }
            let y0 = fa.y, y1 = fb.y + fb.h
            out.append(Frame(slot: ls, x: fa.x, y: y0, w: fa.w, h: y1 - y0, pw: fa.pw, ph: (y1 - y0) * sp.height,
                             calibrated: fa.calibrated && fb.calibrated))
        }
        return out
    }

    static func close(_ f: Frame, _ w: Double, _ h: Double, tol: Double = 0.04) -> Bool {
        abs(f.pw - w) <= f.pw * tol && abs(f.ph - h) <= f.ph * tol
    }

    /// أقرب إطار لمكان الويدجت ومقاسه الحالي (يتغير لما تكبّر/تصغّر الأيقونات)
    static func frame(for slot: Slot, size: CGSize) -> Frame? {
        frames.filter { $0.slot == slot }
            .min { abs($0.pw - size.width) + abs($0.ph - size.height) < abs($1.pw - size.width) + abs($1.ph - size.height) }
    }

    static func hasExactFrame(slot: Slot, size: CGSize) -> Bool {
        frames.contains { $0.slot == slot && close($0, size.width, size.height) }
    }

    // ── الخلفية ──
    static var wallURL: URL? { AppGroup.container?.appendingPathComponent("wall.jpg") }
    static var hasWallpaper: Bool { wallURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    static func image(slot: Slot, size: CGSize) -> UIImage? {
        guard hasWallpaper, let f = frame(for: slot, size: size),
              let u = AppGroup.container?.appendingPathComponent(f.file),
              let data = try? Data(contentsOf: u) else { return nil }
        return UIImage(data: data)
    }

    /// يحوّل أي صورة لمقاس الشاشة: لقطة الشاشة تبقى كما هي، والصورة العادية تتقص من الوسط مثل ما يعرضها الآيفون
    static func normalize(_ img: UIImage, screenPx: CGSize) -> UIImage {
        let src = img.size.width * img.scale, srcH = img.size.height * img.scale
        if abs(src - screenPx.width) < 2 && abs(srcH - screenPx.height) < 2 { return img }
        let k = max(screenPx.width / src, screenPx.height / srcH)
        let dw = src * k, dh = srcH * k
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: screenPx, format: fmt).image { _ in
            img.draw(in: CGRect(x: (screenPx.width - dw) / 2, y: (screenPx.height - dh) / 2, width: dw, height: dh))
        }
    }

    @discardableResult
    static func setWallpaper(_ img: UIImage, screenPx: CGSize) -> Bool {
        guard let u = wallURL, let data = normalize(img, screenPx: screenPx).jpegData(compressionQuality: 0.95) else { return false }
        do { try data.write(to: u, options: .atomic) } catch { return false }
        return regenerate()
    }

    /// يقص خلفية كل إطار (يتنادى بعد تغيير الخلفية أو المعايرة)
    @discardableResult
    static func regenerate() -> Bool {
        guard let dir = AppGroup.container, let u = wallURL, let data = try? Data(contentsOf: u),
              let img = UIImage(data: data), let cg = img.cgImage else { return false }
        // امسح القديم
        if let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for n in items where n.hasPrefix("bg_") { try? FileManager.default.removeItem(at: dir.appendingPathComponent(n)) }
        }
        let W = Double(cg.width), H = Double(cg.height)
        var ok = true
        for f in frames {
            let r = CGRect(x: f.x * W, y: f.y * H, width: f.w * W, height: f.h * H).integral
            guard let part = cg.cropping(to: r), let jpg = UIImage(cgImage: part).jpegData(compressionQuality: 0.92) else { ok = false; continue }
            do { try jpg.write(to: dir.appendingPathComponent(f.file), options: .atomic) } catch { ok = false }
        }
        return ok
    }

    /// بعد التحديث: يقص الإطارات الجديدة (مثل الويدجت الكبيرة) إن لم تُقص بعد
    static func ensureCrops() {
        guard hasWallpaper, let dir = AppGroup.container else { return }
        let missing = frames.contains { !FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.file).path) }
        if missing { regenerate() }
    }

    static func clearWallpaper() {
        if let u = wallURL { try? FileManager.default.removeItem(at: u) }
        if let dir = AppGroup.container, let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for n in items where n.hasPrefix("bg_") { try? FileManager.default.removeItem(at: dir.appendingPathComponent(n)) }
        }
    }

    // ── المعايرة: الويدجتات تتلوّن ١٠ دقائق، ولقطة شاشة وحدة تكفي ──
    static var calibUntil: Date {
        get { Date(timeIntervalSince1970: d.double(forKey: "calib_until")) }
        set { d.set(newValue.timeIntervalSince1970, forKey: "calib_until") }
    }
    static func calibrating(at date: Date) -> Bool { date < calibUntil }

    /// يدوّر على مربعات المعايرة الملوّنة في لقطة الشاشة
    static func detect(in img: UIImage, screenPt: CGSize) -> [Frame] {
        guard let cg = img.cgImage else { return [] }
        let W = cg.width, H = cg.height
        let f = 2, w = W / f, h = H / f
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        // الرسم داخل withUnsafeMutableBytes: مؤشر المخزن صالح طوال عمر السياق
        let drawn: Bool = buf.withUnsafeMutableBytes { raw in
            guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return [] }

        let n = Slot.allCases.count
        var cols = [[Int]](repeating: [Int](repeating: 0, count: w), count: n)
        var rows = [[Int]](repeating: [Int](repeating: 0, count: h), count: n)
        var total = [Int](repeating: 0, count: n)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let r = Double(buf[i]), g = Double(buf[i + 1]), b = Double(buf[i + 2])
                let mx = max(r, g, b), mn = min(r, g, b)
                guard mx > 90, (mx - mn) / mx > 0.72 else { continue }
                var hue: Double
                let c = mx - mn
                if mx == r { hue = 60 * ((g - b) / c) } else if mx == g { hue = 60 * ((b - r) / c + 2) } else { hue = 60 * ((r - g) / c + 4) }
                if hue < 0 { hue += 360 }
                let k = Int((hue / 40).rounded()) % 9
                var diff = abs(hue - Double(k) * 40); if diff > 180 { diff = 360 - diff }
                guard diff < 13 else { continue }
                cols[k][x] += 1; rows[k][y] += 1; total[k] += 1
            }
        }
        func run(_ a: [Int]) -> (Int, Int, Int)? {
            guard let peak = a.max(), peak > 40, let at = a.firstIndex(of: peak) else { return nil }
            var lo = at, hi = at
            while lo > 0 && a[lo - 1] >= peak / 2 { lo -= 1 }
            while hi < a.count - 1 && a[hi + 1] >= peak / 2 { hi += 1 }
            return (lo, hi, peak)
        }
        var out: [Frame] = []
        let sx = screenPt.width / Double(W), sy = screenPt.height / Double(H)
        for (k, slot) in Slot.allCases.enumerated() where !slot.isLarge {
            guard let cx = run(cols[k]), let cy = run(rows[k]) else { continue }
            let x0 = cx.0, x1 = cx.1, y0 = cy.0, y1 = cy.1
            let bw = Double(x1 - x0 + 1), bh = Double(y1 - y0 + 1)
            guard bw > 40, bh > 40, Double(total[k]) > 0.7 * bw * bh else { continue }
            let aspect = bw / bh
            guard slot.isMedium ? (aspect > 1.6 && aspect < 2.8) : (aspect > 0.8 && aspect < 1.25) else { continue }
            // نوسّع بكسل من كل جهة (حواف الويدجت المدوّرة/اللامعة)
            let px = Double(x0 * f) - 1, py = Double(y0 * f) - 1
            let pw = bw * Double(f) + 2, ph = bh * Double(f) + 2
            out.append(Frame(slot: slot, x: px / Double(W), y: py / Double(H), w: pw / Double(W), h: ph / Double(H),
                             pw: pw * sx, ph: ph * sy, calibrated: true))
        }
        return out
    }

    /// يدمج نتائج المعايرة: يستبدل إطار نفس المكان ونفس المقاس
    static func merge(_ new: [Frame]) {
        var cal = calibratedFrames
        for nf in new {
            cal.removeAll { $0.slot == nf.slot && close($0, nf.pw, nf.ph, tol: 0.06) }
            cal.append(nf)
        }
        calibratedFrames = cal
    }

    // ── المقاسات اللي شافتها الويدجتات (عشان التطبيق ينبّه لو تغيّر حجم الأيقونات) ──
    static func noteSeen(slot: Slot, size: CGSize) {
        var m = (d.dictionary(forKey: "seen") as? [String: [Double]]) ?? [:]
        m[slot.rawValue] = [Double(size.width), Double(size.height)]
        d.set(m, forKey: "seen")
    }
    static var unmatchedSlots: [Slot] {
        let m = (d.dictionary(forKey: "seen") as? [String: [Double]]) ?? [:]
        return m.compactMap { k, v in
            guard let s = Slot(rawValue: k), !s.isLarge, v.count == 2 else { return nil }
            return hasExactFrame(slot: s, size: CGSize(width: v[0], height: v[1])) ? nil : s
        }
    }
}

// MARK: - لون الخط

enum Tint {
    static let presets: [(String, String, Color)] = [
        ("auto", "تلقائي", Tint.autoColor),
        ("white", "أبيض", Color.white),
        ("glass", "زجاجي", Tint.glassColor),
        ("gold", "ذهبي", Color(red: 0.93, green: 0.80, blue: 0.52)),
        ("silver", "فضي", Color(red: 0.80, green: 0.83, blue: 0.87)),
        ("beige", "بيج", Color(red: 0.96, green: 0.90, blue: 0.80)),
        ("sky", "سماوي", Color(red: 0.70, green: 0.86, blue: 1.0)),
        ("mint", "أخضر", Color(red: 0.70, green: 0.95, blue: 0.80)),
        ("rose", "وردي", Color(red: 1.0, green: 0.78, blue: 0.82)),
        ("black", "أسود", Color(red: 0.10, green: 0.10, blue: 0.11)),
    ]

    /// اللون العام من التطبيق
    static var appColor: Color {
        get {
            if let a = AppGroup.defaults.array(forKey: "tint") as? [Double], a.count == 3 { return Color(red: a[0], green: a[1], blue: a[2]) }
            return autoColor
        }
        set {
            let u = UIColor(newValue)
            var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
            u.getRed(&r, green: &g, blue: &b, alpha: &a)
            AppGroup.defaults.set([Double(r), Double(g), Double(b)].map { min(1, max(0, $0)) }, forKey: "tint")
        }
    }

    /// «زجاجي»: لون أزرق رمادي فاتح يُرسم بلمعة وحافة مثل أرقام ساعة القفل (العلامة هي هذا اللون نفسه)
    static let glassColor = Color(red: 0.60, green: 0.71, blue: 0.80)
    static func isGlass(_ c: Color) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return abs(r - 0.60) < 0.006 && abs(g - 0.71) < 0.006 && abs(b - 0.80) < 0.006
    }

    /// «تلقائي»: خط زجاجي فوق الخلفيات الداكنة، وأبيض بظل خفيف فوق الفاتحة (العلامة هي هذا اللون نفسه)
    static let autoColor = Color(red: 0.61, green: 0.62, blue: 0.63)
    static func isAuto(_ c: Color) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return abs(r - 0.61) < 0.006 && abs(g - 0.62) < 0.006 && abs(b - 0.63) < 0.006
    }

    /// مرة واحدة: «تلقائي» يصير الأساس — إلا لمن اختار لونًا (ذهبي، سماوي…) فيبقى لونه
    static func migrateToAuto() {
        let d = AppGroup.defaults
        guard !d.bool(forKey: "tint_auto_v1") else { return }
        d.set(true, forKey: "tint_auto_v1")
        if let a = d.array(forKey: "tint") as? [Double], a.count == 3 {
            let c = Color(red: a[0], green: a[1], blue: a[2])
            let white = a.allSatisfy { $0 > 0.97 }
            guard white || isGlass(c) else { return }
        }
        appColor = autoColor
    }

    static func color(_ key: String) -> Color {
        presets.first { $0.0 == key }?.2 ?? appColor
    }
}
