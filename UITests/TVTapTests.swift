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

        // تحديث البث: الشاشة تبقى والقناة تعيد التحميل
        let refresh = app.buttons["تحديث البث"].firstMatch
        XCTAssertTrue(refresh.waitForExistence(timeout: 3), "refresh button missing")
        refresh.tap()
        sleep(6)
        shot(app, "3_after_refresh")
        XCTAssertTrue(playerShown(app), "player closed after refresh")

        // النافذة العائمة: زر النظام في عناصر المشغّل (يظهر بعد لمس الفيديو)
        let video = app.otherElements.matching(NSPredicate(format: "identifier CONTAINS 'AVPlayerView' OR label CONTAINS 'فيديو' OR label CONTAINS 'Video'")).firstMatch
        if video.exists { video.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
        sleep(1)
        let pip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'picture' OR label CONTAINS 'صورة' OR identifier CONTAINS[c] 'pip'")).firstMatch
        print("TVTEST pip button:", pip.exists, pip.exists ? pip.label : "")
        if pip.exists && pip.isHittable {
            pip.tap()
            sleep(5)
            shot(app, "4_tv_pip")
            print("TVTEST after pip, player screen still shown:", playerShown(app))
        }
    }

    /// يفتح الإعدادات ويمرّر حتى يظهر الصف، مع صورة وتشخيص إن لم يُعثر عليه
    private func settingsRow(_ app: XCUIApplication, _ prefix: String, tag: String) -> XCUIElement {
        app.buttons["الإعدادات"].firstMatch.tap()
        sleep(2)
        shot(app, "settings_" + tag)
        let row = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        for _ in 0..<8 where !(row.exists && row.isHittable) { app.swipeUp(); sleep(1) }
        if !row.exists {
            shot(app, "settings_" + tag + "_missing")
            print("TVTEST settings row missing:", prefix, String(app.debugDescription.prefix(4000)))
        }
        return row
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

    /// «تقسيم المقطع»: نغمة ٩٠ ثانية — المدة الجاهزة (دقيقة) ثم مدة مخصّصة ٢٠ ثانية = ٥ أجزاء في مجلد جديد
    func testSplitTool() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-shot", "home", "-splitTest"]
        app.launch()
        let header = app.staticTexts["طول كل جزء"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 30), "split editor did not open")
        sleep(1)
        let summary = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'سيُقسَّم إلى'")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "no parts summary")
        print("TVTEST split summary:", summary.label)
        shot(app, "14_split_editor")
        app.buttons["مدة أخرى"].firstMatch.tap()
        let fields = app.textFields
        XCTAssertTrue(fields.element(boundBy: 1).waitForExistence(timeout: 5), "custom fields missing")
        fields.element(boundBy: 1).tap()
        fields.element(boundBy: 1).typeText("20")
        sleep(1)
        print("TVTEST split custom summary:", summary.label)
        shot(app, "15_split_custom")
        // إخفاء لوحة الأرقام بزر «تم» ثم التنفيذ
        let doneKey = app.buttons["تم"].firstMatch
        if doneKey.waitForExistence(timeout: 3) { doneKey.tap() } else { app.swipeDown() }
        sleep(1)
        let run = app.buttons["تنفيذ"].firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        if !run.isHittable { app.swipeUp() }
        run.tap()
        let done = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'قُسِّم المقطع إلى'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 120), "split did not finish")
        print("TVTEST split done:", done.label)
        shot(app, "16_split_done")
        XCTAssertTrue(done.label.contains("٥") || done.label.contains("5"), "expected 5 parts: \(done.label)")
    }

    /// فصل الصوت بالذكاء الاصطناعي: كلام + نغمة
    func testSeparator() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-shot", "home", "-sepTest"]
        app.launch()
        let t = app.alerts.firstMatch
        let ok = t.waitForExistence(timeout: 6000)
        let label = ok ? t.label : "timeout"
        print("TVTEST separator:", label)
        shot(app, "12_separator")
        XCTAssertTrue(ok && label.hasPrefix("SEPTEST") && !label.contains("error"), "separator failed")
        // دقة الفصل: الصوت البشري يطابق الكلام، والموسيقى تطابق النغمة
        func val(_ k: String) -> Double {
            guard let r = label.range(of: k + "=") else { return -99 }
            return Double(label[r.upperBound...].prefix { $0 != " " }) ?? -99
        }
        XCTAssertGreaterThan(val("vocals~speech"), 0.7, "vocals not clean")
        XCTAssertGreaterThan(val("music~tone"), 0.7, "music not clean")
        // النموذج عالي الدقة يتفوّق على الأداة الحالية في الشرطين: يبقي الصوت البشري ولا يترك موسيقى (والعكس)
        XCTAssertGreaterThan(val("sdrV_rof"), val("sdrV_old"), "RoFormer vocals not better than current")
        XCTAssertGreaterThan(val("sdrM_rof"), val("sdrM_old"), "RoFormer music not better than current")
        XCTAssertGreaterThan(val("keepV_rof"), 70, "voice lost while removing music")
        XCTAssertLessThan(val("leakV_rof"), 10, "music left in the vocals")
        XCTAssertGreaterThan(val("keepM_rof"), 70, "music lost while removing voice")
        XCTAssertLessThan(val("leakM_rof"), 10, "voice left in the music")
        // الجودة لا تقل عن المقيس سابقًا (٢٦ و٢٥ ديسيبل)
        XCTAssertGreaterThan(val("sdrV_rof"), 25.5, "vocal quality dropped")
        XCTAssertGreaterThan(val("sdrM_rof"), 24.5, "music quality dropped")
    }

    /// الإشعارات: الضغط على بطاقة صلاة يفتح صفحتها
    func testNotifyCardOpens() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        sleep(3)
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 { let a = sb.alerts.firstMatch; if a.waitForExistence(timeout: 3) { a.buttons.element(boundBy: a.buttons.count > 1 ? 1 : 0).tap() } }
        app.buttons["الإعدادات"].firstMatch.tap()
        sleep(2)
        var row = app.buttons["الإشعارات، تنبيهات الصلاة وأصواتها"].firstMatch
        if !row.exists { row = app.staticTexts["الإشعارات"].firstMatch }
        for _ in 0..<6 where !row.isHittable { app.swipeUp(); sleep(1) }
        row.tap()
        sleep(3)
        shot(app, "7_notify_center")
        let fajr = app.buttons.containing(NSPredicate(format: "label CONTAINS 'مفعّل' OR label CONTAINS 'متوقّف'")).firstMatch
        print("TVTEST notify tile exists:", fajr.exists, fajr.label)
        fajr.tap()
        sleep(3)
        shot(app, "8_notify_detail")
        // صفحة الصلاة تحتوي «وقت اليوم» وعنوانها في الشريط باسم الصلاة
        let opened = app.staticTexts["وقت اليوم"].waitForExistence(timeout: 5)
        print("TVTEST notify detail opened:", opened)
        XCTAssertTrue(opened, "prayer card did not open")
        // الرجوع ثم فتح «المؤذن»
        app.navigationBars.buttons.firstMatch.tap()
        sleep(2)
        let mu = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'المؤذن'")).firstMatch
        for _ in 0..<6 where !mu.isHittable { app.swipeUp(); sleep(1) }
        mu.tap()
        sleep(2)
        shot(app, "9_muezzin")
        let muOpened = app.navigationBars["المؤذن"].exists || app.staticTexts["المؤذن"].exists && app.buttons.containing(NSPredicate(format: "label CONTAINS 'العفاسي'")).count > 0
        print("TVTEST muezzin opened:", muOpened)
        XCTAssertTrue(app.navigationBars["المؤذن"].waitForExistence(timeout: 4), "muezzin picker did not open")
    }

    func testMethodPick() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        sleep(3)
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 { let a = sb.alerts.firstMatch; if a.waitForExistence(timeout: 3) { a.buttons.element(boundBy: a.buttons.count > 1 ? 1 : 0).tap() } }
        let row = settingsRow(app, "طريقة حساب الأوقات", tag: "method")
        row.tap()
        sleep(2)
        let mwl = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'رابطة العالم الإسلامي'")).firstMatch
        // تنبيه إذن متأخر (الموقع/الإشعارات) قد يظهر بعد الضغط فيمنع فتح الصفحة: نغلقه ونعيد المحاولة
        if !mwl.waitForExistence(timeout: 8) {
            for _ in 0..<2 { let a = sb.alerts.firstMatch; if a.waitForExistence(timeout: 2) { a.buttons.element(boundBy: a.buttons.count > 1 ? 1 : 0).tap() } }
            if row.exists { row.tap() }
            XCTAssertTrue(mwl.waitForExistence(timeout: 10), "method list missing")
        }
        mwl.tap()
        sleep(1)
        print("TVTEST method selected:", mwl.isSelected)
        shot(app, "10_method")
        XCTAssertTrue(mwl.isSelected, "method not selected")
        let uq = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'أم القرى'")).firstMatch
        uq.tap(); sleep(1)
        XCTAssertTrue(uq.isSelected)
    }

    /// تغيير أيقونة التطبيق فعليًا ثم إرجاعها للأصلية
    func testZAppIconChange() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        sleep(3)
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 { let a = sb.alerts.firstMatch; if a.waitForExistence(timeout: 3) { a.buttons.element(boundBy: a.buttons.count > 1 ? 1 : 0).tap() } }
        let row = settingsRow(app, "أيقونة التطبيق", tag: "icon")
        row.tap()
        sleep(2)
        let gold = app.buttons["كحلي ذهبي"].firstMatch
        XCTAssertTrue(gold.waitForExistence(timeout: 5), "icon picker not opened")
        gold.tap()
        // تنبيه النظام «غيّرت أيقونة…»
        let a = sb.alerts.firstMatch
        if a.waitForExistence(timeout: 6) { a.buttons.firstMatch.tap() }
        sleep(3)
        let failed = app.staticTexts["تعذّر تغيير الأيقونة، حاول مرة أخرى."].exists
        print("TVTEST icon changed:", gold.isSelected, "failed:", failed)
        shot(app, "11_app_icon")
        XCTAssertTrue(gold.isSelected && !failed, "icon not changed")
        // الإرجاع للأصلية: محاكي الفحص لا يعرض تنبيه النظام فيبقى الطلب الثاني معلّقًا، لذا يُسجَّل دون أن يُفشل الاختبار
        let orig = app.buttons["الأصلية"].firstMatch
        orig.tap()
        if sb.alerts.firstMatch.waitForExistence(timeout: 12) { sb.alerts.firstMatch.buttons.firstMatch.tap() }
        sleep(10)
        print("TVTEST icon reverted:", orig.isSelected)
    }

    /// تنزيل من صفحة موقع: الضغط على ملف وُجد في الصفحة يفتح خياراته (كان لا يستجيب)
    func testPageFoundItemOpens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-shot", "filesdl"]
        app.launch()
        sleep(3)
        let field = app.textFields["رابط التحميل"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "link field missing")
        field.tap()
        field.typeText("https://raw.githubusercontent.com/salehyusuf1994-art/rafiqi-app/main/tools/testpage.html")
        app.buttons["تنزيل"].firstMatch.tap()
        let item = app.buttons.containing(NSPredicate(format: "label CONTAINS 'mov_bbb.mp4'")).firstMatch
        // الصفحة وملفاتها على مواقع خارجية: شبكة جهاز الفحص قد تتأخر، فنعيد المحاولة مرة قبل الحكم
        if !item.waitForExistence(timeout: 45) {
            print("TVTEST page retry")
            shot(app, "13_page_retry")
            // صفحة الخيارات مفتوحة على خطأ الشبكة: «إعادة المحاولة» منها (زر «تنزيل» تحتها غير قابل للضغط)
            let retry = app.buttons.containing(NSPredicate(format: "label CONTAINS 'إعادة المحاولة'")).firstMatch
            let again = app.buttons["تنزيل"].firstMatch
            if retry.exists { retry.tap() } else if again.exists && again.isHittable { again.tap() }
        }
        XCTAssertTrue(item.waitForExistence(timeout: 60), "page items not listed")
        shot(app, "13_page_items")
        // العناوين الواضحة: «صوت MP3» و«صورة JPG» بدل أسماء الملفات العشوائية
        let mp3 = app.buttons.containing(NSPredicate(format: "label CONTAINS 'صوت MP3'")).firstMatch
        let jpg = app.buttons.containing(NSPredicate(format: "label CONTAINS 'صورة JPG'")).firstMatch
        print("TVTEST page labels:", mp3.exists, jpg.exists)
        XCTAssertTrue(mp3.exists && jpg.exists, "clear labels missing")
        item.tap()
        let best = app.buttons.containing(NSPredicate(format: "label CONTAINS 'أعلى جودة'")).firstMatch
        let ok = best.waitForExistence(timeout: 40)
        print("TVTEST page item opened:", ok)
        shot(app, "14_page_item_options")
        XCTAssertTrue(ok, "found item did not open its options")
        best.tap()
        sleep(3)
        let closed = !best.exists
        print("TVTEST download started & sheet closed:", closed)
        shot(app, "15_page_item_downloading")
        XCTAssertTrue(closed, "options sheet did not close after starting")
    }

    /// منشور x.com: يظهر مقطع المنشور نفسه بجوداته مع صورته وعنوانه
    func testXPostQualities() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-shot", "filesdl"]
        app.launch()
        sleep(3)
        let field = app.textFields["رابط التحميل"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "link field missing")
        field.tap()
        field.typeText("https://x.com/onetakenews/status/2121782437982441589")
        app.buttons["تنزيل"].firstMatch.tap()
        let q = app.buttons.containing(NSPredicate(format: "label CONTAINS 'جودة' AND label CONTAINS 'p'")).firstMatch
        let ok = q.waitForExistence(timeout: 40)
        let title = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'One Take'")).firstMatch.exists
        let n = app.buttons.matching(NSPredicate(format: "label CONTAINS 'جودة' AND label CONTAINS 'p'")).count
        print("TVTEST x qualities:", ok, "count:", n, "title:", title, ok ? q.label : "")
        shot(app, "16_x_post")
        XCTAssertTrue(ok, "x post qualities missing")
        XCTAssertTrue(title, "x post title missing")
    }

}
