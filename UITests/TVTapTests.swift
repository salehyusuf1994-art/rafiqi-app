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

    private func playerShown(_ app: XCUIApplication) -> Bool {
        app.buttons["xmark"].exists || app.images["xmark"].exists || app.staticTexts["القناة غير متاحة الآن"].exists
    }

    private func closePlayer(_ app: XCUIApplication) {
        let x = app.buttons["xmark"].firstMatch
        if x.exists { x.tap() } else if app.images["xmark"].exists { app.images["xmark"].firstMatch.tap() }
        sleep(2)
    }

    /// قناة مضافة: من قائمة القنوات، ثم من شاشة «القنوات المضافة»
    func testCustomChannelOpensPlayer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-shot", "media5", "-seedTV"]
        app.launch()
        sleep(6)
        // ١) من القائمة الرئيسية
        let card = app.staticTexts["تجربة مضافة"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "custom channel card missing")
        card.tap()
        sleep(5)
        shot(app, "3_custom_from_list")
        let a = playerShown(app)
        print("TVTEST custom list player shown:", a)
        XCTAssertTrue(a, "custom channel from list did not open")
        closePlayer(app)
        // ٢) من «القنوات المضافة»
        var tile = app.staticTexts["القنوات المضافة"].firstMatch
        for _ in 0..<8 where !(tile.exists && tile.isHittable) { app.swipeUp(); sleep(1); tile = app.staticTexts["القنوات المضافة"].firstMatch }
        tile.tap()
        sleep(3)
        shot(app, "4_custom_sheet")
        let row = app.staticTexts["تجربة مضافة"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "row missing in sheet")
        row.tap()
        sleep(6)
        shot(app, "5_custom_from_sheet")
        let b = playerShown(app)
        print("TVTEST custom sheet player shown:", b)
        XCTAssertTrue(b, "custom channel from sheet did not open")
    }

    /// أول تشغيل عادي: لازم يطلب التطبيق إذن الإشعارات
    func testAsksNotificationPermission() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var found = false
        for i in 0..<6 {
            let a = sb.alerts.firstMatch
            guard a.waitForExistence(timeout: 8) else { break }
            let label = a.label
            print("TVTEST alert:", label)
            shot(app, "6_alert_\(i)")
            if label.contains("إشعار") || label.localizedCaseInsensitiveContains("notification") { found = true }
            let btn = a.buttons.element(boundBy: a.buttons.count > 1 ? 1 : 0)
            btn.tap(); sleep(2)
            if found { break }
        }
        print("TVTEST notification prompt shown:", found)
        XCTAssertTrue(found, "notification permission was not requested")
    }
}
