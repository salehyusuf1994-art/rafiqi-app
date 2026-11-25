import SwiftUI
import UIKit

/// ما تعرضه نافذة إدخال نص قصير (اسم ملف، مجلد جديد، اسم قائمة…)
struct TextPromptSpec {
    var title: String
    var message: String? = nil
    var placeholder: String
    var initial: String = ""
    var confirm: String
    /// السماح بالحفظ والحقل فارغ (للإنشاء الذي له اسم افتراضي)
    var allowEmpty = false
    /// تحديد النص كله عند الفتح: الكتابة مباشرة تستبدله، والإبقاء عليه ضغطة واحدة
    var selectAll = true
}

extension View {
    /// بديل «alert + TextField» بحقل يتحكم فيه التطبيق:
    /// • اتجاه النص يتبع أول حرف فيه (عربي من اليمين، لاتيني من اليسار) والمحاذاة ثابتة،
    ///   فلا يقفز النص من جهة لجهة ولا تنقلب الأقواس والأرقام أثناء المسح أو الكتابة
    /// • النص يبقى داخل الحقل نفسه، فلا تُعاد الصفحة التي خلفه مع كل حرف (لا بطء ولا ارتجاف)
    /// • بلا تصحيح تلقائي ولا علامات «ذكية» تغيّر الاسم، وزر الحفظ يتعطّل والاسم فارغ
    /// - spec: يُقرأ لحظة الفتح (فيأخذ الاسم الحالي للعنصر)
    func textPrompt(isPresented: Binding<Bool>, _ spec: @escaping () -> TextPromptSpec,
                    onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void = {}) -> some View {
        background(
            TextPromptHost(isPresented: isPresented, spec: spec, onConfirm: onConfirm, onCancel: onCancel)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }
}

enum TextDirection {
    @MainActor private static var installed = false

    /// كل خانات الكتابة ذات السطر الواحد في التطبيق (البحث، الروابط، الأسماء…):
    /// اتجاه الفقرة يتبع أول حرف في النص، لا لغة لوحة المفاتيح — فلا تظهر مسافة أو قوس في آخر نص إنجليزي على الجهة الغلط.
    /// المحاذاة لا تتغيّر (تبقى بلغة الواجهة)
    @MainActor static func installForAllTextFields() {
        guard !installed else { return }
        installed = true
        for name in [UITextField.textDidBeginEditingNotification, UITextField.textDidChangeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { n in
                guard let tf = n.object as? UITextField else { return }
                MainActor.assumeIsolated { apply(tf) }
            }
        }
    }

    /// يضبط اتجاه فقرة الحقل بأول حرف فيه (بدون لمس المحاذاة ولا موضع المؤشر)
    @MainActor static func apply(_ tf: UITextField) {
        guard tf.markedTextRange == nil else { return }   // لا نلمس الحقل أثناء تركيب حرف (لوحات مفاتيح آسيوية)
        let rtl = firstStrongIsRTL(tf.text ?? "") ?? !Lang.isEN
        let want: NSWritingDirection = rtl ? .rightToLeft : .leftToRight
        // المحاذاة «الطبيعية» تتبع اتجاه الفقرة فيقفز النص يمينًا ويسارًا مع أول حرف: نثبّتها بلغة الواجهة
        // (المحاذاة المقصودة مثل التوسيط تبقى كما هي)
        let fixed: NSTextAlignment = Lang.isEN ? .left : .right
        if tf.textAlignment == .natural { tf.textAlignment = fixed }
        guard tf.baseWritingDirection(for: tf.beginningOfDocument, in: .forward) != want,
              let r = tf.textRange(from: tf.beginningOfDocument, to: tf.endOfDocument) else { return }
        tf.setBaseWritingDirection(want, for: r)
        if tf.textAlignment == .natural { tf.textAlignment = fixed }
    }

    /// اتجاه أول حرف «قوي» في النص: true عربي/عبري، false لاتيني وغيره، nil لا حروف (أرقام ورموز فقط أو فارغ)
    static func firstStrongIsRTL(_ s: String) -> Bool? {
        for u in s.unicodeScalars {
            let v = u.value
            // الأرقام العربية الهندية ضعيفة الاتجاه: لا تحدده
            if (0x0660...0x0669).contains(v) || (0x06F0...0x06F9).contains(v) { continue }
            if (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
                || (0x10800...0x10FFF).contains(v) || (0x1E800...0x1EFFF).contains(v) { return true }
            if u.properties.isAlphabetic { return false }
        }
        return nil
    }
}

private struct TextPromptHost: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let spec: () -> TextPromptSpec
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.isUserInteractionEnabled = false
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        let c = context.coordinator
        c.parent = self
        if isPresented, c.alert == nil { c.open(from: vc) }
        else if !isPresented, c.alert != nil { c.close() }
    }

    static func dismantleUIViewController(_ vc: UIViewController, coordinator: Coordinator) {
        coordinator.close(animated: false)
    }

    @MainActor final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TextPromptHost?
        private(set) var alert: UIAlertController?
        private var confirmAction: UIAlertAction?
        private var allowEmpty = false
        private var finished = false

        func open(from host: UIViewController) {
            guard let p = parent else { return }
            let s = p.spec()
            finished = false
            allowEmpty = s.allowEmpty
            let a = UIAlertController(title: s.title, message: s.message, preferredStyle: .alert)
            a.view.tintColor = UIColor(Theme.gold)
            a.addTextField { [weak self] tf in
                tf.text = s.initial
                tf.placeholder = s.placeholder
                tf.accessibilityIdentifier = "promptField"
                tf.clearButtonMode = .whileEditing
                tf.returnKeyType = .done
                // الأسماء تُكتب كما هي: لا تصحيح ولا اقتراحات ولا تحويل "--" أو علامات التنصيص
                tf.autocorrectionType = .no
                tf.spellCheckingType = .no
                tf.smartDashesType = .no
                tf.smartQuotesType = .no
                tf.smartInsertDeleteType = .no
                tf.delegate = self
                tf.addTarget(self, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
                Coordinator.applyDirection(tf)
            }
            let cancel = UIAlertAction(title: L("إلغاء"), style: .cancel) { [weak self] _ in self?.finish(nil) }
            let ok = UIAlertAction(title: s.confirm, style: .default) { [weak self, weak a] _ in
                self?.finish(a?.textFields?.first?.text ?? "")
            }
            a.addAction(cancel)
            a.addAction(ok)
            a.preferredAction = ok
            confirmAction = ok
            alert = a
            if let tf = a.textFields?.first { updateConfirm(tf) }
            present(a, from: host, selectAll: s.selectAll, attempt: 0)
        }

        /// يُعرض بعد انتهاء أي حركة جارية (إغلاق قائمة الضغط المطوّل أو نافذة أخرى)
        private func present(_ a: UIAlertController, from host: UIViewController, selectAll: Bool, attempt: Int) {
            guard alert === a, !finished else { return }
            var top = host.view.window?.rootViewController
            while let p = top?.presentedViewController, !p.isBeingDismissed { top = p }
            guard let top, top.transitionCoordinator == nil, !top.isBeingPresented, !top.isBeingDismissed else {
                guard attempt < 40 else { finish(nil); return }
                Task { @MainActor [weak self, weak host] in
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    guard let self, let host else { return }
                    self.present(a, from: host, selectAll: selectAll, attempt: attempt + 1)
                }
                return
            }
            top.present(a, animated: true) {
                guard selectAll, let tf = a.textFields?.first, !(tf.text ?? "").isEmpty else { return }
                tf.selectedTextRange = tf.textRange(from: tf.beginningOfDocument, to: tf.endOfDocument)
            }
        }

        /// إغلاق من الخارج (تغيّرت الحالة أو اختفت الصفحة): بلا حفظ
        func close(animated: Bool = true) {
            guard let a = alert else { return }
            finished = true
            alert = nil
            confirmAction = nil
            if a.presentingViewController != nil { a.dismiss(animated: animated) }
        }

        private func finish(_ text: String?) {
            guard !finished else { return }
            finished = true
            alert = nil
            confirmAction = nil
            guard let p = parent else { return }
            // الإجراء أولًا (قد يحتاج العنصر المعروض)، ثم تُغلق الحالة
            if let text { p.onConfirm(text) } else { p.onCancel() }
            if p.isPresented { p.isPresented = false }
        }

        @objc func changed(_ tf: UITextField) {
            Coordinator.applyDirection(tf)
            updateConfirm(tf)
        }

        private func updateConfirm(_ tf: UITextField) {
            confirmAction?.isEnabled = allowEmpty || !(tf.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            guard confirmAction?.isEnabled == true, let a = alert else { return false }
            let text = tf.text ?? ""
            a.dismiss(animated: true)
            finish(text)
            return false
        }

        /// محاذاة ثابتة بلغة الواجهة، واتجاه الفقرة بأول حرف في النص
        static func applyDirection(_ tf: UITextField) {
            guard tf.markedTextRange == nil else { return }
            let rtl = TextDirection.firstStrongIsRTL(tf.text ?? "") ?? !Lang.isEN
            if let r = tf.textRange(from: tf.beginningOfDocument, to: tf.endOfDocument) {
                tf.setBaseWritingDirection(rtl ? .rightToLeft : .leftToRight, for: r)
            }
            tf.textAlignment = Lang.isEN ? .left : .right
        }
    }
}
