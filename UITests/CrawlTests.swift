import XCTest

/// زاحف الواجهة: يضغط كل زر في كل شاشة (حتى عمق شاشتين) ويسجّل الضغطات التي لا تغيّر شيئًا
/// التبويب يُحدَّد بمتغير البيئة CRAWL_TAB (عبر TEST_RUNNER_CRAWL_TAB)
final class CrawlTests: XCTestCase {
    struct Step: Hashable { let scrolls: Int; let type: UInt; let label: String; let nth: Int }

    let tabs = ["الرئيسية", "الويدجت", "المسموع والمرئي", "إدارة الملفات", "الإعدادات"]
    let skipWords = ["حذف", "مسح", "Delete", "Remove", "إعادة ضبط", "إعادة تعيين", "إفراغ", "التقاط"]
    let tappable: Set<XCUIElement.ElementType> = [.button, .cell, .switch, .link, .segmentedControl]
    var app: XCUIApplication!
    var report = ""
    var start = Date()
    var budget: TimeInterval = 55 * 60
    var tabName = ""
    var shotN = 0

    // MARK: أدوات

    func log(_ s: String) { print("CRAWL", s); report += s + "\n" }

    func outDir() -> URL {
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
        let u = URL(fileURLWithPath: home).appendingPathComponent("uitest/crawl")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func save() {
        try? report.write(to: outDir().appendingPathComponent("crawl_\(tabName).txt"), atomically: true, encoding: .utf8)
    }

    func shot(_ name: String) {
        shotN += 1
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let safe = name.replacingOccurrences(of: "/", with: "_").prefix(60)
        try? png.write(to: outDir().appendingPathComponent("\(tabName)_\(String(format: "%03d", shotN))_\(safe).png"))
    }

    func flatten(_ s: XCUIElementSnapshot, _ a: inout [XCUIElementSnapshot]) {
        a.append(s); for c in s.children { flatten(c, &a) }
    }

    func snap() -> [XCUIElementSnapshot] {
        guard app.state == .runningForeground, let s = try? app.snapshot() else { return [] }
        var a: [XCUIElementSnapshot] = []; flatten(s, &a); return a
    }

    static let digits = CharacterSet(charactersIn: "0123456789٠١٢٣٤٥٦٧٨٩:٫.,،%")
    /// الأرقام تُحذف فقط من الأوقات والعدّادات (فيها «:»)؛ التواريخ تبقى كما هي
    func clean(_ s: String) -> String {
        guard s.contains(":") || s.contains("٪") || s.contains("%") else { return s.trimmingCharacters(in: .whitespaces) }
        return String(s.unicodeScalars.filter { !Self.digits.contains($0) }).trimmingCharacters(in: .whitespaces)
    }

    /// بصمة الشاشة: نصوص وأزرار وقيمها، بدون أرقام (العدّادات تتغيّر كل ثانية)
    func sig() -> Set<String> {
        if app.state != .runningForeground { return ["<APP:\(app.state.rawValue)>"] }
        var r = Set<String>()
        for e in snap() where [.staticText, .button, .switch, .cell, .textField, .navigationBar, .alert, .sheet, .image, .slider].contains(e.elementType) {
            let v = (e.value as? String).map(clean) ?? ""
            let l = clean(e.label.isEmpty ? e.identifier : e.label)
            if l.isEmpty && v.isEmpty && e.elementType != .alert && e.elementType != .sheet { continue }
            r.insert("\(e.elementType.rawValue)|\(l)|\(v)|\(e.isSelected)")
        }
        return r
    }

    func similarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        let u = a.union(b).count
        return u == 0 ? 1 : Double(a.intersection(b).count) / Double(u)
    }

    func handleAlerts() {
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<4 {
            let a = sb.alerts.firstMatch
            guard a.exists else { return }
            log("   (system alert: \(a.label))")
            let n = a.buttons.count
            // نسمح دائمًا (الزر الثاني عادة «السماح»)
            let b = a.buttons.element(boundBy: n > 1 ? 1 : 0)
            if b.exists { b.tap() }
            sleep(1)
        }
    }

    func tapAt(_ f: CGRect) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
    }

    func screenBounds() -> CGRect { app.windows.firstMatch.frame }

    /// العناصر القابلة للضغط والظاهرة الآن (بدون شريط التبويب السفلي)
    func candidates() -> [(XCUIElementSnapshot, String, Int)] {
        let b = screenBounds()
        var seen: [String: Int] = [:]
        var out: [(XCUIElementSnapshot, String, Int)] = []
        let all = snap()
        let bottomBar = all.filter { $0.elementType == .button && tabs.contains($0.label) }.map(\.frame.minY).min() ?? (b.maxY - 90)
        for e in all where tappable.contains(e.elementType) && e.isEnabled {
            let f = e.frame
            guard f.width > 8, f.height > 8, f.midY > 55, f.midY < bottomBar - 4, f.midX > 0, f.midX < b.maxX else { continue }
            var label = e.label.isEmpty ? e.identifier : e.label
            if label.isEmpty { label = "<\(e.elementType.rawValue)@\(Int(f.midX)),\(Int(f.midY))>" }
            if tabs.contains(label) { continue }
            if skipWords.contains(where: { label.contains($0) }) { continue }
            let key = "\(e.elementType.rawValue)|\(label)"
            let n = seen[key, default: 0]; seen[key] = n + 1
            out.append((e, label, n))
        }
        return out
    }

    func find(_ s: Step) -> XCUIElementSnapshot? {
        var n = 0
        let b = screenBounds()
        for e in snap() where e.elementType.rawValue == s.type && e.isEnabled {
            let label = e.label.isEmpty ? e.identifier : e.label
            let f = e.frame
            let fallback = "<\(e.elementType.rawValue)@\(Int(f.midX)),\(Int(f.midY))>"
            guard label == s.label || fallback == s.label else { continue }
            guard f.midY > 40, f.midY < b.maxY - 20 else { continue }
            if n == s.nth { return e }
            n += 1
        }
        return nil
    }

    func scroll(_ n: Int) { for _ in 0..<n { app.swipeUp(velocity: 600); usleep(700_000) } }

    /// تشغيل من جديد والوصول إلى الشاشة عبر خطواتها
    @discardableResult
    func reach(_ path: [Step]) -> Bool {
        app.terminate()
        app.launch()
        sleep(3)
        handleAlerts()
        let tb = app.buttons[tabName].firstMatch
        guard tb.waitForExistence(timeout: 8) else { log("!! tab button missing: \(tabName)"); return false }
        tb.tap(); sleep(2)
        handleAlerts()
        for s in path {
            scroll(s.scrolls)
            guard let e = find(s) else { log("!! replay failed at: \(s.label)"); return false }
            tapAt(e.frame); sleep(2)
            handleAlerts()
        }
        return true
    }

    // MARK: الزحف

    func testCrawl() throws {
        continueAfterFailure = true
        let idx = Int(ProcessInfo.processInfo.environment["CRAWL_TAB"] ?? "4") ?? 4
        tabName = tabs[idx]
        if let m = ProcessInfo.processInfo.environment["CRAWL_MIN"], let v = Double(m) { budget = v * 60 }
        app = XCUIApplication()
        app.launchArguments = ["-crawl", "1", "-seedFiles"]
        start = Date()
        log("== TAB \(tabName)")

        var queue: [([Step], Int, String)] = [([], 0, tabName)]
        var visited: [Set<String>] = []
        let maxDepth = 2

        while !queue.isEmpty, Date().timeIntervalSince(start) < budget {
            let (path, depth, title) = queue.removeFirst()
            guard reach(path) else { save(); continue }
            let base0 = sig()
            if visited.contains(where: { similarity($0, base0) > 0.85 }) && !path.isEmpty { log("-- skip duplicate screen: \(title)"); continue }
            visited.append(base0)
            log("")
            log("## SCREEN [d\(depth)] \(title)")
            shot(title)

            var done = Set<String>()
            for sc in 0..<5 {
                if Date().timeIntervalSince(start) > budget { break }
                if sc > 0 {
                    // نتحقق أن التمرير أظهر شيئًا جديدًا
                    let before = sig()
                    guard reach(path) else { break }
                    scroll(sc)
                    if similarity(before, sig()) > 0.97 && sc > 1 { break }
                } else { /* already there */ }
                let cands = candidates()
                if cands.isEmpty { continue }
                var needReach = false
                for (e, label, nth) in cands {
                    let key = "\(e.elementType.rawValue)|\(label)|\(nth)"
                    if done.contains(key) { continue }
                    done.insert(key)
                    if Date().timeIntervalSince(start) > budget { break }
                    if needReach {
                        guard reach(path) else { break }
                        scroll(sc)
                    }
                    let step = Step(scrolls: sc, type: e.elementType.rawValue, label: label, nth: nth)
                    guard let cur = find(step) else { log("   ?  not found again: \(label)"); needReach = true; continue }
                    let before = sig()
                    tapAt(cur.frame)
                    usleep(1_500_000)
                    handleAlerts()
                    var after = sig()
                    if after == before { sleep(2); after = sig() }
                    let typeName = e.elementType == .switch ? "switch" : e.elementType == .cell ? "cell" : "button"
                    if app.state == .notRunning {
                        log("   💥 CRASH after tap: \(label)"); shot("CRASH_\(label)"); needReach = true; continue
                    }
                    if app.state != .runningForeground {
                        log("   ↗︎ left app: \(label)"); needReach = true; continue
                    }
                    if after == before {
                        log("   ❌ NO CHANGE [\(typeName)]: \(label)")
                        needReach = false
                        continue
                    }
                    let s = similarity(before, after)
                    if s > 0.6 {
                        log("   ✓ in-place (\(Int(s * 100))%) [\(typeName)]: \(label)")
                        // تغيير داخل الصفحة: نعيد التشغيل حتى لا تتراكم الحالات
                        needReach = true
                    } else {
                        log("   ✓ opened (\(Int(s * 100))%) [\(typeName)]: \(label)")
                        if depth < maxDepth, !visited.contains(where: { similarity($0, after) > 0.85 }),
                           !queue.contains(where: { $0.2 == title + " › " + label }) {
                            queue.append((path + [step], depth + 1, title + " › " + label))
                        }
                        needReach = true
                    }
                    save()
                }
            }
            save()
        }
        log("")
        log("== END \(tabName) remaining=\(queue.count) elapsed=\(Int(Date().timeIntervalSince(start)))s")
        save()
    }
}
