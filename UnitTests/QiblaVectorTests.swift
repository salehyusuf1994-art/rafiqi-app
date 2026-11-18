import XCTest
@testable import Hilal

/// متجهات مرجعية للقبلة من مصدر خارجي (لا من خوارزمية التطبيق): AlAdhan Qibla API، اطّلع عليه ١٨ نوفمبر ٢٠٢٦
/// https://api.aladhan.com/v1/qibla/{lat}/{lng}
/// تغطي: أوروبا، أمريكا الشمالية، جنوب خط الاستواء، قرب خط التاريخ (فيجي)، وعرضًا عاليًا (ريكيافيك).
/// الحسابان في التطبيق (صفحة القبلة Qibla وويدجت القبلة QiblaMath) يجب أن يطابقا المرجع ويتطابقا معًا.
final class QiblaVectorTests: XCTestCase {
    private let vectors: [(name: String, lat: Double, lng: Double, deg: Double)] = [
        ("لندن", 51.5074, -0.1278, 118.98724251452296),
        ("نيويورك", 40.7128, -74.006, 58.481712034206865),
        ("جاكرتا", -6.2088, 106.8456, 295.15174505875416),
        ("سيدني", -33.8688, 151.2093, 277.499589412883),
        ("سوفا — فيجي (قرب خط التاريخ)", -18.1416, 178.4419, 281.8927469181185),
        ("ريكيافيك (عرض عالٍ)", 64.1466, -21.9426, 106.11766325174096),
    ]

    func testAppQiblaMatchesReference() {
        for v in vectors {
            XCTAssertEqual(Qibla.bearing(lat: v.lat, lng: v.lng), v.deg, accuracy: 0.05, v.name)
        }
    }

    func testWidgetQiblaMatchesReference() {
        for v in vectors {
            XCTAssertEqual(QiblaMath.bearing(lat: v.lat, lng: v.lng), v.deg, accuracy: 0.05, v.name)
        }
    }

    /// النتيجة دائمًا في المدى ٠…٣٦٠ (لا سالب ولا ٣٦٠ نفسها) حتى عند خط الطول ±١٨٠
    func testRangeAtAntimeridian() {
        for lng in [-180.0, -179.999, 179.999, 180.0] {
            let b = Qibla.bearing(lat: -18, lng: lng)
            XCTAssertTrue(b >= 0 && b < 360, "\(lng) → \(b)")
        }
    }
}
