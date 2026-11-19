import XCTest
import PDFKit
@testable import Hilal

/// اختبارات أمان تتكرر مع كل بناء (تدقيق ٠١). كل اختبار يعيد الحالة كما كانت.
@MainActor
final class SecurityTests: XCTestCase {

    // MARK: النقل عبر الواي فاي: الرمز والجلسات

    func testWiFiGuardLockoutAfterTenWrongCodes() {
        WiFiGuard.reset(code: "12345678")
        defer { WiFiGuard.reset(code: nil) }
        for _ in 0..<10 { XCTAssertNil(WiFiGuard.login("00000000")) }
        XCTAssertTrue(WiFiGuard.blocked)
        XCTAssertNil(WiFiGuard.login("12345678"), "بعد ١٠ محاولات خاطئة يُرفض حتى الرمز الصحيح")
    }

    func testWiFiSessionsAreRandomAndRevocable() {
        WiFiGuard.reset(code: "12345678")
        defer { WiFiGuard.reset(code: nil) }
        let a = WiFiGuard.login("12345678"), b = WiFiGuard.login("12345678")
        XCTAssertNotNil(a); XCTAssertNotNil(b)
        XCTAssertNotEqual(a, b)
        XCTAssertGreaterThanOrEqual(a?.count ?? 0, 40, "٣٢ بايت عشوائية")
        XCTAssertTrue(WiFiGuard.valid(a))
        XCTAssertFalse(WiFiGuard.valid("12345678"), "رمز الدخول نفسه ليس جلسة")
        XCTAssertFalse(WiFiGuard.valid(nil))
        WiFiGuard.reset(code: nil)
        XCTAssertFalse(WiFiGuard.valid(a), "إيقاف النقل يُبطل كل الجلسات")
    }

    func testTLSIdentityIsCreated() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("على الجوال الحقيقي يستبدل شهادة النقل الفعلية: المحاكي فقط")
        #endif
        guard let id = WiFiTLS.identity(ip: "192.168.1.20") else {
            throw XCTSkip("سلسلة المفاتيح غير متاحة في بيئة الاختبار هذه")
        }
        XCTAssertEqual(id.fingerprint.split(separator: ":").count, 8)
        var cert: SecCertificate?
        XCTAssertEqual(SecIdentityCopyCertificate(id.identity, &cert), errSecSuccess)
        XCTAssertNotNil(cert)
    }

    // MARK: الخزنة: المجلد المقفل لا يبقى في Documents (المكشوف لتطبيق «الملفات»)

    func testLockedFolderLeavesDocuments() throws {
        let store = FileStore.shared
        let name = "SecTest-\(UUID().uuidString.prefix(6))"
        let folder = try XCTUnwrap(store.createFolder(name, in: store.root))
        try "secret".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let locked = store.setLocked(folder, true)
        defer {
            let u = store.setLocked(locked, false)
            try? FileManager.default.removeItem(at: u)
        }
        XCTAssertTrue(store.inVault(locked))
        let docs = try FileManager.default.contentsOfDirectory(atPath: store.root.path)
        XCTAssertFalse(docs.contains { $0.contains(name) }, "لا أثر له في Documents")
        XCTAssertTrue(store.list(store.root).contains { $0.name == name }, "ويظهر داخل التطبيق")
        XCTAssertTrue(FileManager.default.fileExists(atPath: locked.appendingPathComponent("a.txt").path), "المحتوى لم يضِع")
    }

    // MARK: ZIP: لا كتابة خارج مجلد الفك (ZIP slip) ولا عبر رابط رمزي

    private let slipZip = "UEsDBBQAAAAAAAAAIQCSVKm+BAAAAAQAAAAGAAAAb2sudHh0ZmluZVBLAwQUAAAAAAAAACEAflME2QUAAAAFAAAACwAAAC4uL2V2aWwudHh0cHduZWRQSwECFAMUAAAAAAAAACEAklSpvgQAAAAEAAAABgAAAAAAAAAAAAAApIEAAAAAb2sudHh0UEsBAhQDFAAAAAAAAAAhAH5TBNkFAAAABQAAAAsAAAAAAAAAAAAAAKSBKAAAAC4uL2V2aWwudHh0UEsFBgAAAAACAAIAbQAAAFYAAAAAAA=="
    private let linkZip = "UEsDBBQAAAAAAAAAIQB3tMGYBgAAAAYAAAADAAAAbG5rLi4vLi4vUEsDBBQAAAAAAAAAIQB+UwTZBQAAAAUAAAAPAAAAbG5rL2VzY2FwZWQudHh0cHduZWRQSwECFAMUAAAAAAAAACEAd7TBmAYAAAAGAAAAAwAAAAAAAAAAAAAA/6EAAAAAbG5rUEsBAhQDFAAAAAAAAAAhAH5TBNkFAAAABQAAAA8AAAAAAAAAAAAAAKSBJwAAAGxuay9lc2NhcGVkLnR4dFBLBQYAAAAAAgACAG4AAABZAAAAAAA="

    private func unzipCase(_ b64: String) async throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("SecZip-\(UUID().uuidString)", isDirectory: true)
        let dir = base.appendingPathComponent("case", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let zip = dir.appendingPathComponent("x.zip")
        try XCTUnwrap(Data(base64Encoded: b64)).write(to: zip)
        _ = await FileStore.shared.unzip(zip)
        return base
    }

    /// الضغط والفك يعملان فعلًا (اختبارا الحماية أدناه لا معنى لهما لو كان الفك معطّلًا كليًا)
    func testZipRoundTripWorks() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("SecZipOK-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        let src = base.appendingPathComponent("src", isDirectory: true)
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try "hello".write(to: src.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let z = await FileStore.shared.zip([src])
        let zip = try XCTUnwrap(z, "تعذّر الضغط")
        try fm.removeItem(at: src)
        let o = await FileStore.shared.unzip(zip)
        let out = try XCTUnwrap(o, "تعذّر الفك")
        let found = (fm.enumerator(at: out, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).first { $0.lastPathComponent == "a.txt" }
        let file = try XCTUnwrap(found, "الملف لم يُستخرج")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "hello")
    }

    func testZipSlipIsBlocked() async throws {
        let base = try await unzipCase(slipZip)
        defer { try? FileManager.default.removeItem(at: base) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("case/evil.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("evil.txt").path))
    }

    func testZipSymlinkEscapeIsBlocked() async throws {
        let base = try await unzipCase(linkZip)
        defer { try? FileManager.default.removeItem(at: base) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("escaped.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("case/escaped.txt").path))
    }

    // MARK: توكنات القنوات المضافة: في سلسلة المفاتيح لا في ملف الإعدادات

    func testChannelHeadersLeaveUserDefaults() throws {
        let probe = "probe-\(UUID().uuidString)"
        guard TVSecrets.set(probe, ["x": "y"]) else { throw XCTSkip("سلسلة المفاتيح غير متاحة في بيئة الاختبار هذه") }
        TVSecrets.set(probe, nil)
        let token = "Bearer SECTEST-\(UUID().uuidString)"
        let url = "https://example.com/sectest-\(UUID().uuidString).m3u8"
        TVChannels.addCustom(name: "SecTest", url: url, cat: TVChannels.builtin[0].cat, referer: nil, headers: ["Authorization": token])
        let added = try XCTUnwrap(TVChannels.custom.first { $0.urls.first == url })
        defer { TVChannels.removeCustom(added.id) }
        let raw = AppGroup.defaults.data(forKey: "tv_custom").map { String(decoding: $0, as: UTF8.self) } ?? ""
        XCTAssertFalse(raw.contains(token), "التوكن لا يُحفظ نصًا في الإعدادات")
        XCTAssertEqual(added.headers?["Authorization"], token, "والقناة ما زالت تعمل بترويستها")
    }

    // MARK: الماسح: حذف الملف يحذف نسخة المسح المرتبطة

    func testScanProjectForgottenWithItsFile() throws {
        let id = UUID()
        let dir = ScanProjects.root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"{"title":"t","date":0,"pages":[],"files":["/المسح الضوئي/هوية-اختبار.pdf"]}"#
        try Data(json.utf8).write(to: dir.appendingPathComponent("project.json"))
        defer { try? FileManager.default.removeItem(at: dir) }
        ScanProjects.forget(keys: ["/مجلد آخر"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path), "ملف آخر لا يمسّه")
        ScanProjects.forget(keys: ["/المسح الضوئي"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path), "حذف المجلد يحذف نسخ ملفاته")
    }

    // MARK: تحويل HTML إلى PDF: لا تُنفَّذ أكواد الصفحة

    func testHTMLToPDFRunsNoScripts() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SecPDF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let html = dir.appendingPathComponent("t.html")
        try "<html><body><p>STATICTEXT</p><script>document.body.innerHTML += '<p>INJECTEDTEXT</p>'</script></body></html>"
            .write(to: html, atomically: true, encoding: .utf8)
        let pdf = try await DocToPDF.convert(html)
        defer { try? FileManager.default.removeItem(at: pdf) }
        let text = PDFDocument(url: pdf)?.string ?? ""
        XCTAssertTrue(text.contains("STATICTEXT"), "المحتوى نفسه يُحوَّل")
        XCTAssertFalse(text.contains("INJECTEDTEXT"), "والسكربت لا يعمل")
    }

    // MARK: ملف الخصوصية داخل التطبيق

    func testPrivacyManifestBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    }
}
