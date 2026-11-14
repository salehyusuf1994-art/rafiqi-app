import XCTest

/// اختبار واجهة حقيقي: الضغط على قناة في تبويب القنوات يجب أن يفتح المشغّل
final class TVTapTests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSTemporaryDirectory()
        let dir = URL(fileURLWithPath: home).appendingPathComponent("uitest")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
    }

    func testTapChannelOpensPlayer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-shot", "media5"]
        app.launch()
        sleep(6)
        shot(app, "1_tv_tab")
        let names = ["قناة القرآن الكريم", "قناة السنة النبوية", "الإخبارية السعودية", "العربية"]
        var tapped = ""
        for n in names {
            let t = app.staticTexts[n].firstMatch
            if t.waitForExistence(timeout: 3) && t.isHittable { t.tap(); tapped = n; break }
        }
        print("TVTEST tapped:", tapped.isEmpty ? "NOTHING FOUND" : tapped)
        print("TVTEST tree:", app.debugDescription.prefix(6000))
        sleep(5)
        shot(app, "2_after_tap")
        let close = app.buttons["xmark"].exists || app.images["xmark"].exists || app.staticTexts["القناة غير متاحة الآن"].exists
        print("TVTEST player shown:", close)
        XCTAssertTrue(close, "player did not open")
    }
}
