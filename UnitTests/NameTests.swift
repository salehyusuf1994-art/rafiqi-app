import XCTest
@testable import Hilal

/// أسماء الملفات: الامتداد لا يضيع، والأحرف الخفية لا تدخل الاسم، واتجاه النص يُحسب من أول حرف
@MainActor
final class NameTests: XCTestCase {

    private func tempDir() throws -> URL {
        let store = FileStore.shared
        return try XCTUnwrap(store.createFolder("NameTest-\(UUID().uuidString.prefix(6))", in: store.root))
    }

    func testRenameKeepsExtensionWhenNameHasDot() throws {
        let store = FileStore.shared
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("نغمة.wav")
        try Data([1, 2, 3]).write(to: f)
        let out = try XCTUnwrap(store.rename(f, to: "جزء 1.2"))
        XCTAssertEqual(out.lastPathComponent, "جزء 1.2.wav", "النقطة في الاسم ليست امتدادًا جديدًا")
        // كتابة الامتداد نفسه لا يكرره
        let again = try XCTUnwrap(store.rename(out, to: "مقطع.WAV"))
        XCTAssertEqual(again.lastPathComponent, "مقطع.WAV")
        // اسم فارغ أو مسافات فقط: لا تغيير
        XCTAssertNil(store.rename(again, to: "   "))
        XCTAssertTrue(FileManager.default.fileExists(atPath: again.path))
    }

    func testRenameToExistingNameGetsUniqueName() throws {
        let store = FileStore.shared
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("أ.txt"), b = dir.appendingPathComponent("ب.txt")
        try Data("1".utf8).write(to: a); try Data("2".utf8).write(to: b)
        let out = try XCTUnwrap(store.rename(b, to: "أ"))
        XCTAssertNotEqual(out.lastPathComponent, "أ.txt", "لا يُكتب فوق ملف موجود")
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "1")
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), "2")
    }

    func testNewNoteWithDotStaysText() throws {
        let store = FileStore.shared
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let u = try XCTUnwrap(store.createText("ملاحظة 1.2", in: dir))
        XCTAssertEqual(u.pathExtension, "txt")
        let md = try XCTUnwrap(store.createText("مسودة.md", in: dir))
        XCTAssertEqual(md.lastPathComponent, "مسودة.md")
    }

    func testSanitizeRemovesInvisibleAndControlCharacters() {
        let store = FileStore.shared
        // RLO يقلب العرض فيُخفي الامتداد الحقيقي («صورةgnp.exe» تظهر كأنها png)
        XCTAssertEqual(store.sanitize("صورة\u{202E}gnp.exe"), "صورةgnp.exe")
        XCTAssertEqual(store.sanitize("\u{200F}اسم\u{200E} 1\n2\t"), "اسم 12")
        XCTAssertEqual(store.sanitize("a/b:c"), "a-b-c")
        XCTAssertEqual(store.sanitize(".مخفي"), "_مخفي")
        // ZWNJ (فارسي) ومحارف الإيموجي المركّبة تبقى
        XCTAssertEqual(store.sanitize("می\u{200C}خواهم"), "می\u{200C}خواهم")
        XCTAssertEqual(store.sanitize("👨\u{200D}👩"), "👨\u{200D}👩")
    }

    func testFirstStrongDirection() {
        XCTAssertEqual(TextDirection.firstStrongIsRTL("نغمة"), true)
        XCTAssertEqual(TextDirection.firstStrongIsRTL("Part 1 ("), false)
        XCTAssertEqual(TextDirection.firstStrongIsRTL("12 - مقطع"), true)
        XCTAssertEqual(TextDirection.firstStrongIsRTL("١٢ Part"), false)
        XCTAssertNil(TextDirection.firstStrongIsRTL("12 (3)"))
        XCTAssertNil(TextDirection.firstStrongIsRTL(""))
    }
}
