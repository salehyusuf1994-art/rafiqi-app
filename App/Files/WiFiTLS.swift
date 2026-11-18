import Foundation
import Security
import CryptoKit

// MARK: - تشفير النقل عبر الواي فاي (HTTPS)
// شهادة ذاتية التوقيع (ECDSA P-256 / SHA-256) تُنشأ على الجوال ويبقى مفتاحها الخاص في سلسلة المفاتيح
// (لا يغادر الجهاز). صلاحيتها ٣٩٧ يومًا، وفيها عنوان الجوال في الشبكة (SAN) واستخدام «خادم TLS» كما تشترط أبل والمتصفحات.
// تُجدَّد تلقائيًا إذا تغيّر عنوان الجوال أو قاربت على الانتهاء. بصمتها (SHA-256) تظهر في الجوال ليطابقها المستخدم في المتصفح.

enum WiFiTLS {
    private static let label = "rafiqi.wifi.tls"
    private static let tag = Data("rafiqi.wifi.tls.key".utf8)
    private static let ipKey = "wifi_tls_ip", untilKey = "wifi_tls_until"

    struct Identity {
        let identity: SecIdentity
        /// بصمة الشهادة SHA-256 مقسّمة (للمطابقة في المتصفح)
        let fingerprint: String
    }

    /// الهوية الحالية، أو تُنشأ جديدة. ترجع nil إن تعذّر ذلك (لا يُشغَّل النقل بدون تشفير).
    static func identity(ip: String) -> Identity? {
        let d = UserDefaults.standard
        let fresh = d.string(forKey: ipKey) == ip && d.double(forKey: untilKey) > Date().addingTimeInterval(7 * 86400).timeIntervalSince1970
        if fresh, let id = load() { return id }
        remove()
        guard create(ip: ip) else { return nil }
        d.set(ip, forKey: ipKey)
        d.set(Date().addingTimeInterval(397 * 86400).timeIntervalSince1970, forKey: untilKey)
        return load()
    }

    // MARK: سلسلة المفاتيح

    private static func load() -> Identity? {
        let q: [String: Any] = [kSecClass as String: kSecClassIdentity, kSecAttrLabel as String: label,
                                kSecReturnRef as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let ref = out,
              CFGetTypeID(ref) == SecIdentityGetTypeID() else { return nil }
        let id = ref as! SecIdentity
        var cert: SecCertificate?
        guard SecIdentityCopyCertificate(id, &cert) == errSecSuccess, let cert else { return nil }
        return Identity(identity: id, fingerprint: fingerprint(SecCertificateCopyData(cert) as Data))
    }

    private static func remove() {
        SecItemDelete([kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: label] as CFDictionary)
        SecItemDelete([kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag] as CFDictionary)
    }

    private static func create(ip: String) -> Bool {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrLabel as String: label,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ] as [String: Any],
        ]
        var err: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(attrs as CFDictionary, &err),
              let pub = SecKeyCopyPublicKey(priv),
              let pubData = SecKeyCopyExternalRepresentation(pub, &err) as Data? else { return false }
        let tbs = tbsCertificate(publicKey: pubData, ip: ip)
        guard let sig = SecKeyCreateSignature(priv, .ecdsaSignatureMessageX962SHA256, tbs as CFData, &err) as Data? else { return false }
        let der = DER.seq([tbs, ecdsaSHA256, DER.bitString(sig)])
        guard let cert = SecCertificateCreateWithData(nil, der as CFData) else { return false }
        let add: [String: Any] = [kSecClass as String: kSecClassCertificate, kSecValueRef as String: cert,
                                  kSecAttrLabel as String: label,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func fingerprint(_ der: Data) -> String {
        let h = SHA256.hash(data: der).map { String(format: "%02X", $0) }
        // أول ٨ بايتات تكفي للمطابقة بالعين، مقسّمة بنقطتين كما تعرضها المتصفحات
        return h.prefix(8).joined(separator: ":")
    }

    // MARK: بناء الشهادة (X.509 v3)

    private static let ecdsaSHA256 = DER.seq([DER.oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02])])

    private static func tbsCertificate(publicKey: Data, ip: String) -> Data {
        var serial = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial)
        serial[0] = (serial[0] & 0x7F) | 0x01   // موجب وغير صفري
        let name = DER.seq([DER.set([DER.seq([DER.oid([0x55, 0x04, 0x03]), DER.utf8("Rafiqi Wi-Fi")])])])
        let now = Date()
        let validity = DER.seq([DER.utcTime(now.addingTimeInterval(-86400)), DER.utcTime(now.addingTimeInterval(397 * 86400))])
        let spki = DER.seq([
            DER.seq([DER.oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]), DER.oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07])]),
            DER.bitString(publicKey),
        ])
        // SAN: عنوان IP للجوال + localhost
        var san: [Data] = [DER.tagged(0x82, Data("localhost".utf8))]
        if let ipBytes = ipv4(ip) { san.insert(DER.tagged(0x87, ipBytes), at: 0) }
        let exts = DER.seq([
            DER.seq([DER.oid([0x55, 0x1D, 0x11]), DER.octet(DER.seq(san))]),
            DER.seq([DER.oid([0x55, 0x1D, 0x25]), DER.octet(DER.seq([DER.oid([0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01])]))]),
            DER.seq([DER.oid([0x55, 0x1D, 0x0F]), DER.bool(true), DER.octet(DER.bitString(Data([0x80]), unused: 7))]),
            DER.seq([DER.oid([0x55, 0x1D, 0x13]), DER.octet(DER.seq([]))]),
        ])
        return DER.seq([
            DER.tagged(0xA0, DER.integer(Data([0x02]))),
            DER.integer(Data(serial)),
            ecdsaSHA256, name, validity, name, spki,
            DER.tagged(0xA3, exts),
        ])
    }

    private static func ipv4(_ s: String) -> Data? {
        let p = s.split(separator: ".").compactMap { UInt8($0) }
        return p.count == 4 ? Data(p) : nil
    }
}

/// ترميز DER مبسّط (ما تحتاجه الشهادة فقط)
enum DER {
    static func length(_ n: Int) -> Data {
        if n < 0x80 { return Data([UInt8(n)]) }
        var b: [UInt8] = []
        var v = n
        while v > 0 { b.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
        return Data([0x80 | UInt8(b.count)] + b)
    }
    static func tagged(_ tag: UInt8, _ content: Data) -> Data { Data([tag]) + length(content.count) + content }
    static func seq(_ items: [Data]) -> Data { tagged(0x30, items.reduce(Data(), +)) }
    static func set(_ items: [Data]) -> Data { tagged(0x31, items.reduce(Data(), +)) }
    static func oid(_ bytes: [UInt8]) -> Data { tagged(0x06, Data(bytes)) }
    static func utf8(_ s: String) -> Data { tagged(0x0C, Data(s.utf8)) }
    static func octet(_ d: Data) -> Data { tagged(0x04, d) }
    static func bool(_ b: Bool) -> Data { tagged(0x01, Data([b ? 0xFF : 0x00])) }
    static func bitString(_ d: Data, unused: UInt8 = 0) -> Data { tagged(0x03, Data([unused]) + d) }
    static func integer(_ d: Data) -> Data {
        var b = d
        while b.count > 1 && b.first == 0 && (b[b.startIndex + 1] & 0x80) == 0 { b = b.dropFirst() }
        if let f = b.first, f & 0x80 != 0 { b.insert(0, at: b.startIndex) }
        return tagged(0x02, Data(b))
    }
    static func utcTime(_ d: Date) -> Data {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyMMddHHmmss'Z'"
        return tagged(0x17, Data(f.string(from: d).utf8))
    }
}
