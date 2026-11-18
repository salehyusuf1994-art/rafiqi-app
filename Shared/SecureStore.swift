import Foundation
import Security

/// سلسلة المفاتيح: مكان واحد لحفظ الأسرار (كلمات سر الخوادم، ترويسات القنوات)، مع تأكيد الحفظ بالقراءة
enum SecureStore {
    private static func base(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func data(service: String, account: String) -> Data? {
        var q = base(service, account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    /// يحفظ ثم يقرأ للتأكد؛ يرجع false إن لم يُحفظ فعلًا (ولا يترك نسخة ناقصة). nil = حذف
    @discardableResult
    static func set(_ value: Data?, service: String, account: String, accessible: CFString) -> Bool {
        let b = base(service, account)
        SecItemDelete(b as CFDictionary)
        guard let value else { return true }
        var add = b
        add[kSecValueData as String] = value
        add[kSecAttrAccessible as String] = accessible
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return false }
        guard data(service: service, account: account) == value else { SecItemDelete(b as CFDictionary); return false }
        return true
    }
}
