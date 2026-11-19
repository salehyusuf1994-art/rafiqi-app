import Foundation
import Security

/// سلسلة المفاتيح: مكان واحد لحفظ الأسرار (كلمات سر الخوادم، ترويسات القنوات)، مع تأكيد الحفظ بالقراءة
enum SecureStore {
    private static func base(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    /// نتيجة القراءة: موجود، أو غير موجود فعلًا، أو تعذّرت القراءة (مثلًا قبل أول فتح للجوال بعد التشغيل)
    enum Read { case found(Data), missing, failed }
    static func read(service: String, account: String) -> Read {
        var q = base(service, account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        if st == errSecSuccess, let d = out as? Data { return .found(d) }
        return st == errSecItemNotFound ? .missing : .failed
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
        guard let value else {
            let st = SecItemDelete(b as CFDictionary)
            return st == errSecSuccess || st == errSecItemNotFound
        }
        // تحديث القيمة الموجودة أولًا؛ لا نحذف القديمة قبل أن تُحفظ الجديدة (فشل الإضافة كان يضيّع السر السابق)
        let attrs: [String: Any] = [kSecValueData as String: value, kSecAttrAccessible as String: accessible]
        var st = SecItemUpdate(b as CFDictionary, attrs as CFDictionary)
        if st == errSecItemNotFound {
            var add = b
            add[kSecValueData as String] = value
            add[kSecAttrAccessible as String] = accessible
            st = SecItemAdd(add as CFDictionary, nil)
        }
        guard st == errSecSuccess else { return false }
        return data(service: service, account: account) == value
    }
}
