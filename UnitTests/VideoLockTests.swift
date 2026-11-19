import XCTest
import UIKit
@testable import Hilal

/// قفل مشغّل الفيديو: زرّ القفل لا يحمل قائمة وهو مقفل.
/// (زرٌّ له قائمة يفتحها بالضغط المطوّل، فكانت القائمة تبتلع الضغطة المطوّلة ولا يُفتح القفل أبدًا)
@MainActor
final class VideoLockTests: XCTestCase {
    func testLockedButtonHasNoMenuSoLongPressUnlocks() {
        let vc = VideoController(playlist: [URL(fileURLWithPath: NSTemporaryDirectory() + "none.mp4")], start: 0)
        vc.loadViewIfNeeded()
        let b = vc.lockButton
        XCTAssertNotNil(b.menu, "مفتوح: القائمة موجودة")
        XCTAssertTrue(b.showsMenuAsPrimaryAction)
        let hold = b.gestureRecognizers?.compactMap { $0 as? UILongPressGestureRecognizer }.first
        XCTAssertNotNil(hold, "الضغط المطوّل لفتح القفل موجود")

        for mode in [PlayerLockMode.hold, .code] {
            vc.setLockMode(mode)
            XCTAssertNil(b.menu, "مقفل (\(mode)): لا قائمة تبتلع الضغط المطوّل")
            XCTAssertFalse(b.showsMenuAsPrimaryAction)
            XCTAssertEqual(b.accessibilityLabel, L("المشغّل مقفل"))
            XCTAssertFalse(vc.allowsPictureInPicturePlayback, "لا نافذة عائمة أثناء القفل")
            XCTAssertTrue(hold?.isEnabled ?? false)

            vc.setLockMode(.open)
            XCTAssertNotNil(b.menu, "بعد الفتح ترجع القائمة")
            XCTAssertTrue(b.showsMenuAsPrimaryAction)
            XCTAssertEqual(b.accessibilityLabel, L("قفل المشغّل"))
            XCTAssertTrue(vc.allowsPictureInPicturePlayback)
        }
    }
}
