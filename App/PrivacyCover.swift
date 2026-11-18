import UIKit

/// غطاء خصوصية فوق كل شيء (حتى الصفحات المنبثقة ومشغّل الملفات) حين يخرج المستخدم من التطبيق وهو في «إدارة الملفات»
/// وهي مقفلة أو فيها مجلد مقفل مفتوح؛ فلا تظهر الملفات في صورة التطبيق داخل مبدّل التطبيقات.
@MainActor
enum PrivacyCover {
    private static var window: UIWindow?

    static func show() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        let vc = UIViewController()
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.frame = vc.view.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        vc.view.addSubview(blur)
        vc.view.backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 0.92)
        let icon = UIImageView(image: UIImage(systemName: "lock.fill"))
        icon.tintColor = UIColor(white: 1, alpha: 0.85)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 44), icon.heightAnchor.constraint(equalToConstant: 44),
        ])
        w.rootViewController = vc
        w.isHidden = false
        window = w
    }

    static func hide() {
        window?.isHidden = true
        window = nil
    }
}
