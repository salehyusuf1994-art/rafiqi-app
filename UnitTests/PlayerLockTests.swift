import XCTest
@testable import Hilal

/// قفل المشغّل: الرمز لا يُحفظ نصًا، والتحقق صحيح، والمحاولات الخاطئة تُبطئ التخمين
final class PlayerLockTests: XCTestCase {
    override func tearDown() {
        PlayerLockCode.clear()
        MainActor.assumeIsolated { PlayerLockCode.registerSuccess() }
        super.tearDown()
    }

    @MainActor func testSetVerifyClear() {
        PlayerLockCode.clear()
        XCTAssertFalse(PlayerLockCode.isSet)
        XCTAssertTrue(PlayerLockCode.set("2580"))
        XCTAssertTrue(PlayerLockCode.isSet)
        XCTAssertTrue(PlayerLockCode.verify("2580"))
        XCTAssertFalse(PlayerLockCode.verify("2581"))
        XCTAssertFalse(PlayerLockCode.verify(""))
        XCTAssertFalse(PlayerLockCode.verify("25800"))
        PlayerLockCode.clear()
        XCTAssertFalse(PlayerLockCode.isSet)
        XCTAssertFalse(PlayerLockCode.verify("2580"))
    }

    @MainActor func testRejectsInvalidCodes() {
        XCTAssertFalse(PlayerLockCode.set("123"))
        XCTAssertFalse(PlayerLockCode.set("12345"))
        XCTAssertFalse(PlayerLockCode.set("12a4"))
        XCTAssertFalse(PlayerLockCode.set("١٢٣٤"))   // أرقام عربية: لوحة الرمز ترسل أرقامًا لاتينية فقط
        XCTAssertFalse(PlayerLockCode.isSet)
    }

    /// المخزَّن ملح + بصمة (٤٨ بايت)، ولا يحتوي الرمز نفسه، والملح يختلف كل مرة
    @MainActor func testStoredValueIsSaltedHash() {
        XCTAssertTrue(PlayerLockCode.set("1234"))
        let a = SecureStore.data(service: "app.rafiqi.playerlock", account: "code.v1")
        XCTAssertEqual(a?.count, 48)
        XCTAssertNil(a.flatMap { String(data: $0, encoding: .utf8) }?.range(of: "1234"))
        XCTAssertTrue(PlayerLockCode.set("1234"))
        let b = SecureStore.data(service: "app.rafiqi.playerlock", account: "code.v1")
        XCTAssertNotEqual(a, b, "الملح يجب أن يكون عشوائيًا")
        XCTAssertTrue(PlayerLockCode.verify("1234"))
    }

    @MainActor func testThrottleAfterFiveFailures() {
        PlayerLockCode.registerSuccess()
        for _ in 0..<4 { PlayerLockCode.registerFailure() }
        XCTAssertNil(PlayerLockCode.blockedUntil)
        PlayerLockCode.registerFailure()
        let until = try? XCTUnwrap(PlayerLockCode.blockedUntil)
        XCTAssertGreaterThan(until?.timeIntervalSinceNow ?? 0, 25)
        PlayerLockCode.registerFailure()
        XCTAssertGreaterThan(PlayerLockCode.blockedUntil?.timeIntervalSinceNow ?? 0, 55)
        PlayerLockCode.registerSuccess()
        XCTAssertNil(PlayerLockCode.blockedUntil)
    }

    @MainActor func testFlow() {
        XCTAssertEqual(PlayerLockFlow.after(.unlock, ok: true).mode, .open)
        XCTAssertNil(PlayerLockFlow.after(.unlock, ok: false).mode)
        XCTAssertEqual(PlayerLockFlow.after(.create(lockAfter: true), ok: true).mode, .code)
        XCTAssertNil(PlayerLockFlow.after(.create(lockAfter: false), ok: true).mode)
        XCTAssertEqual(PlayerLockFlow.after(.verifyToChange, ok: true).next, .create(lockAfter: false))
        XCTAssertTrue(PlayerLockCode.set("4321"))
        _ = PlayerLockFlow.after(.verifyToRemove, ok: true)
        XCTAssertFalse(PlayerLockCode.isSet)
    }
}
