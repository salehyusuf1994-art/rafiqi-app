import Foundation
import CoreLocation

// MARK: - مدن السعودية (٤٥٨١ مدينة وقرية في ١٣ منطقة)

enum Places {
    struct City: Identifiable, Hashable {
        let id: Int
        let name: String
        let region: Int
        let lat: Double
        let lng: Double
    }

    private struct Raw: Decodable {
        let regions: [String]
        let cities: [[Value]]
        let capitals: [Int]
        enum Value: Decodable {
            case s(String), d(Double)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let v = try? c.decode(Double.self) { self = .d(v) } else { self = .s(try c.decode(String.self)) }
            }
            var str: String { if case .s(let v) = self { return v }; return "" }
            var num: Double { if case .d(let v) = self { return v }; return 0 }
        }
    }

    static let data: (regions: [String], cities: [City], capitals: [Int]) = {
        guard let url = Bundle.main.url(forResource: "ksa_cities", withExtension: "json"),
              let d = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode(Raw.self, from: d) else { return ([], [], []) }
        let cities = raw.cities.enumerated().map { i, a in
            City(id: i, name: a[0].str, region: Int(a[1].num), lat: a[2].num, lng: a[3].num)
        }
        return (raw.regions, cities, raw.capitals)
    }()

    static var regions: [String] { data.regions }
    static var cities: [City] { data.cities }

    /// المدن الكبيرة أول القائمة
    static let major: [City] = {
        let names = ["المدينة المنورة", "مكة المكرمة", "الرياض", "جدة", "الدمام", "الخبر", "الطائف", "أبها", "خميس مشيط",
                     "تبوك", "بريدة", "عنيزة", "حائل", "جازان", "نجران", "الباحة", "سكاكا", "عرعر", "ينبع", "الهفوف",
                     "المبرز", "القطيف", "الجبيل", "حفر الباطن", "العلا", "القريات", "الخرج", "بيشة", "القنفذة", "رابغ"]
        let capitals = Set(data.capitals)
        return names.compactMap { n in
            let m = cities.filter { $0.name == n }
            return m.first { capitals.contains($0.id) } ?? m.first
        }
    }()

    static func nearest(lat: Double, lng: Double, in list: [City]? = nil) -> City? {
        let k = cos(lat * .pi / 180)
        return (list ?? cities).min { a, b in
            let da = pow(a.lat - lat, 2) + pow((a.lng - lng) * k, 2)
            let db = pow(b.lat - lat, 2) + pow((b.lng - lng) * k, 2)
            return da < db
        }
    }

    /// للبحث: يوحّد الهمزات والتاء المربوطة والألف المقصورة ويشيل التشكيل
    static func norm(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "[\u{064B}-\u{065F}\u{0670}]", with: "", options: .regularExpression)
        for (a, b) in [("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ة", "ه"), ("ى", "ي"), ("ؤ", "و"), ("ئ", "ي")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t
    }

    /// اسم المكان: من خرائط أبل (بلغة التطبيق) في أي مكان في العالم — وخارج المملكة يُضاف اسم الدولة.
    /// بلا إنترنت: أقرب مدينة سعودية إن كانت على بُعد ٤٠ كم أو أقل، وإلا «موقعك الحالي»
    static func name(for loc: CLLocation) async -> String {
        let locale = Locale(identifier: Lang.isEN ? "en_US" : "ar_SA")
        if let pm = try? await CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: locale).first,
           let n = pm.locality ?? pm.subAdministrativeArea ?? pm.administrativeArea, !n.isEmpty {
            if let cc = pm.isoCountryCode, cc != "SA", let country = pm.country, !country.isEmpty, country != n {
                return n + (Lang.isEN ? ", " : "، ") + country
            }
            return n
        }
        if let near = nearest(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude),
           CLLocation(latitude: near.lat, longitude: near.lng).distance(from: loc) < 40_000 {
            return near.name
        }
        return L("موقعك الحالي")
    }
}

// MARK: - تحديد الموقع مرة وحدة (يشتغل في التطبيق والويدجت)

final class OneShotLocator: NSObject, CLLocationManagerDelegate {
    private let m = CLLocationManager()
    private var cont: CheckedContinuation<CLLocation?, Never>?

    private override init() {
        super.init()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    @MainActor
    static func fetch(timeout: Double = 8) async -> CLLocation? {
        let l = OneShotLocator()
        return await withCheckedContinuation { c in
            l.cont = c
            l.m.requestLocation()
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { l.finish(nil) }
        }
    }

    private func finish(_ loc: CLLocation?) {
        cont?.resume(returning: loc)
        cont = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { finish(locations.last) }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finish(nil) }
}

enum LocationSync {
    /// في الوضع التلقائي: يحدّث الإحداثيات واسم المكان (كل ١٥ دقيقة كحد أدنى)
    @discardableResult
    static func refreshIfNeeded(force: Bool = false, inWidget: Bool = false) async -> Bool {
        guard Settings.isAuto else { return false }
        if !force && Date().timeIntervalSince(Settings.lastFix) < 15 * 60 { return false }
        let ok: Bool = await MainActor.run {
            let m = CLLocationManager()
            let st = m.authorizationStatus
            guard st == .authorizedWhenInUse || st == .authorizedAlways else { return false }
            return inWidget ? m.isAuthorizedForWidgetUpdates : true
        }
        guard ok, let loc = await OneShotLocator.fetch() else { return false }
        let c = loc.coordinate
        let moved = abs(c.latitude - Settings.lat) > 0.02 || abs(c.longitude - Settings.lng) > 0.02
        Settings.lat = c.latitude
        Settings.lng = c.longitude
        Settings.lastFix = Date()
        if moved || Settings.placeName.isEmpty {
            Settings.placeName = await Places.name(for: loc)
            AppGroup.defaults.removeObject(forKey: "wx")
            if Notify.enabled { await Notify.reschedule() }
        }
        return moved
    }
}
