import SwiftUI
import UIKit
import CryptoKit
import LocalAuthentication
import Security

/// نوع البصمة في الجوال: الوجه (Face ID) أو الإصبع (Touch ID في iPhone SE) — للأيقونة والنص الصحيحين
enum Biometry {
    static let isTouch: Bool = {
        let c = LAContext()
        var e: NSError?
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e)
        return c.biometryType == .touchID
    }()
    static var icon: String { isTouch ? "touchid" : "faceid" }
    /// النص المناسب للجوال (مترجم)
    static func text(face: String, touch: String) -> String { L(isTouch ? touch : face) }
}

// MARK: - قفل المشغّل
// قفل يمنع اللمس أثناء المشاهدة (للأطفال أو الجيب)، بطريقتين:
// • بلا رمز: يُفتح بضغطة مطوّلة على القفل (حلقة ذهبية تمتلئ أثناء الضغط)
// • برمز سري من ٤ أرقام: الضغطة المطوّلة تفتح لوحة الرمز، وبصمة الوجه بديل لصاحب الجوال

enum PlayerLockMode: Equatable {
    case open, hold, code
}

/// الرمز السري: لا يُحفظ نفسه، بل ملح عشوائي + بصمة مكرّرة (SHA-256) في سلسلة المفاتيح على هذا الجهاز فقط
enum PlayerLockCode {
    static let length = 4
    private static let service = "app.rafiqi.playerlock"
    private static let account = "code.v1"
    private static let rounds = 20_000

    static var isSet: Bool { SecureStore.data(service: service, account: account)?.count == 48 }

    @discardableResult
    static func set(_ code: String) -> Bool {
        guard code.count == length, code.allSatisfy(\.isASCII), code.allSatisfy(\.isNumber) else { return false }
        var salt = Data(count: 16)
        let ok = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) } == errSecSuccess
        guard ok else { return false }
        return SecureStore.set(salt + digest(code, salt), service: service, account: account,
                               accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }

    static func clear() {
        SecureStore.set(nil, service: service, account: account, accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }

    static func verify(_ code: String) -> Bool {
        guard let d = SecureStore.data(service: service, account: account), d.count == 48 else { return false }
        let salt = Data(d.prefix(16)), stored = Data(d.suffix(32))
        let given = digest(code, salt)
        // مقارنة بزمن ثابت
        var diff: UInt8 = 0
        for (a, b) in zip(given, stored) { diff |= a ^ b }
        return diff == 0 && given.count == stored.count
    }

    private static func digest(_ code: String, _ salt: Data) -> Data {
        var h = Data(SHA256.hash(data: salt + Data(code.utf8)))
        for _ in 0..<rounds { h = Data(SHA256.hash(data: h + salt)) }
        return h
    }

    // ── المحاولات الخاطئة: بعد ٥ محاولات انتظار ٣٠ ثانية، ويتضاعف مع كل خطأ بعدها (حتى ١٠ دقائق) ──
    @MainActor private(set) static var failures = 0
    @MainActor private(set) static var blockedUntil: Date?

    @MainActor static func registerFailure() {
        failures += 1
        if failures >= 5 {
            let wait = min(600, 30 * pow(2, Double(failures - 5)))
            blockedUntil = Date().addingTimeInterval(wait)
        }
    }
    @MainActor static func registerSuccess() { failures = 0; blockedUntil = nil }

    /// بصمة الوجه متاحة؟ (طريق صاحب الجوال بدل الرمز)
    /// البصمة وحدها لا رمز الجوال: كثير من الأطفال يعرفون رمز الجوال، فلا يصير بابًا خلفيًا لقفل المشغّل
    static var ownerAuthAvailable: Bool {
        var e: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e)
    }
    static func ownerAuth() async -> Bool {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = ""   // لا زر «إدخال رمز الجوال»
        var e: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: L("افتح قفل المشغّل"))) ?? false
    }
}

/// ماذا تفعل لوحة الرمز، وما بعدها
enum PlayerLockFlow {
    enum Purpose: Equatable {
        case create(lockAfter: Bool)   // اختيار رمز جديد (مرتين)
        case unlock                    // فتح المشغّل المقفل
        case verifyToChange            // الرمز الحالي قبل تغييره
        case verifyToRemove            // الرمز الحالي قبل حذفه
    }

    /// نتيجة اللوحة: الوضع الجديد للقفل (إن تغيّر) واللوحة التالية (إن وجدت)
    @MainActor static func after(_ p: Purpose, ok: Bool) -> (mode: PlayerLockMode?, next: Purpose?) {
        guard ok else { return (nil, nil) }
        switch p {
        case .create(let lockAfter): return (lockAfter ? .code : nil, nil)
        case .unlock: return (.open, nil)
        case .verifyToChange: return (nil, .create(lockAfter: false))
        case .verifyToRemove: PlayerLockCode.clear(); return (nil, nil)
        }
    }

    static func hint(_ m: PlayerLockMode) -> String {
        m == .code ? L("اضغط مطوّلًا على القفل ثم أدخل الرمز") : L("اضغط مطوّلًا على القفل لفتحه")
    }
}

// MARK: - لوحة الرمز

struct PasscodePad: View {
    let purpose: PlayerLockFlow.Purpose
    let onFinish: (Bool) -> Void

    @State private var entry = ""
    @State private var first: String?
    @State private var shakes = 0
    @State private var message: String?
    @State private var now = Date()
    @State private var success = false
    /// لحظة الحكم بعد الرقم الرابع: لا يُقبل ضغط حتى تنتهي
    @State private var checking = false
    /// النتيجة تُرسل مرة واحدة فقط (لا «إلغاء» بعد النجاح ولا العكس)
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var blockedFor: Int {
        guard let u = PlayerLockCode.blockedUntil else { return 0 }
        return max(0, Int(ceil(u.timeIntervalSince(now))))
    }
    private var creating: Bool { if case .create = purpose { return true }; return false }

    private var title: String {
        switch purpose {
        case .create: return first == nil ? L("اختر رمزًا سريًا") : L("أكّد الرمز")
        case .unlock: return L("المشغّل مقفل")
        case .verifyToChange, .verifyToRemove: return L("أدخل الرمز الحالي")
        }
    }
    private var subtitle: String {
        switch purpose {
        case .create: return first == nil ? L("٤ أرقام تفتح بها قفل المشغّل") : L("اكتبه مرة ثانية للتأكد")
        case .unlock: return L("أدخل الرمز لفتح القفل")
        case .verifyToChange: return L("لتغيير رمز قفل المشغّل")
        case .verifyToRemove: return L("لحذف رمز قفل المشغّل")
        }
    }

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width > g.size.height
            let key = wide ? min(58, (g.size.height - 40) / 4.7) : min(76, (g.size.width - 96) / 3.2)
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                // توهّج ذهبي خافت خلف القفل
                RadialGradient(colors: [Theme.gold.opacity(0.16), .clear], center: .init(x: 0.5, y: wide ? 0.45 : 0.24),
                               startRadius: 4, endRadius: wide ? 260 : 300)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                if wide {
                    HStack(spacing: 48) {
                        header.frame(maxWidth: 300)
                        keypad(key)
                    }
                } else {
                    VStack(spacing: 0) {
                        Spacer(minLength: 12)
                        header
                        Spacer(minLength: 24)
                        keypad(key)
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 24)
                }

                VStack {
                    HStack {
                        Button(L("إلغاء")) { finish(false) }
                            .disabled(success)
                            .font(Theme.f(.body, .semibold)).foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 20).padding(.vertical, 12)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onReceive(tick) { now = $0 }
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.gold.opacity(0.13)).frame(width: 74, height: 74)
                Circle().stroke(Theme.gold.opacity(0.45), lineWidth: 1).frame(width: 74, height: 74)
                Image(systemName: success ? "lock.open.fill" : (creating ? "lock.shield" : "lock.fill"))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.gold)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(verbatim: title).font(Theme.title(22)).foregroundStyle(.white)
                Text(verbatim: subtitle).font(Theme.f(.subheadline)).foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
            }
            dots
                .modifier(Shake(animatableData: CGFloat(shakes)))
            Text(verbatim: blockedFor > 0 ? LF("حاول بعد %@", secondsText(blockedFor)) : (message ?? " "))
                .font(Theme.f(.footnote, .semibold))
                .foregroundStyle(blockedFor > 0 || message != nil ? Color(red: 1, green: 0.55, blue: 0.5) : .clear)
                .frame(height: 18)
                .accessibilityHidden(blockedFor == 0 && message == nil)
        }
    }

    private var dots: some View {
        HStack(spacing: 20) {
            ForEach(0..<PlayerLockCode.length, id: \.self) { i in
                let on = i < entry.count
                Circle()
                    .fill(on ? Theme.gold : Color.clear)
                    .overlay(Circle().stroke(on ? Theme.gold : Color.white.opacity(0.45), lineWidth: 1.5))
                    .frame(width: 14, height: 14)
                    .scaleEffect(on && !reduceMotion ? 1.12 : 1)
                    .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.55), value: entry.count)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(LF("أُدخل %@ من %@", ar(entry.count), ar(PlayerLockCode.length)))
    }

    private func keypad(_ size: CGFloat) -> some View {
        let rows: [[Int]] = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
        return VStack(spacing: size * 0.24) {
            ForEach(rows, id: \.self) { r in
                HStack(spacing: size * 0.36) { ForEach(r, id: \.self) { digitKey($0, size) } }
            }
            HStack(spacing: size * 0.36) {
                // صاحب الجوال: بصمة الوجه بدل الرمز (لا تظهر عند اختيار رمز جديد)
                if !creating && PlayerLockCode.ownerAuthAvailable {
                    Button { Task { await faceID() } } label: {
                        Image(systemName: Biometry.icon).font(.system(size: size * 0.36, weight: .regular))
                            .foregroundStyle(.white.opacity(0.85)).frame(width: size, height: size)
                    }
                    .buttonStyle(.plain)
                    // تبقى متاحة أثناء مهلة الأخطاء: محاولات طفل لا تمنع صاحب الجوال (النظام يحدّ البصمة بنفسه)
                    .disabled(success || checking)
                    .accessibilityLabel(Biometry.text(face: "فتح ببصمة الوجه", touch: "فتح ببصمة الإصبع"))
                } else {
                    Color.clear.frame(width: size, height: size)
                }
                digitKey(0, size)
                Button {
                    if !entry.isEmpty { entry.removeLast(); message = nil }
                } label: {
                    Image(systemName: "delete.left").font(.system(size: size * 0.32, weight: .regular))
                        .foregroundStyle(.white.opacity(entry.isEmpty ? 0.3 : 0.85)).frame(width: size, height: size)
                }
                .buttonStyle(.plain)
                .disabled(entry.isEmpty || keysOff)
                .opacity(blockedFor > 0 ? 0.4 : 1)
                .accessibilityLabel(L("حذف"))
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    /// أزرار الأرقام والحذف موقوفة: مهلة الأخطاء، أو لحظة الحكم، أو بعد النجاح
    private var keysOff: Bool { blockedFor > 0 || success || checking }

    private func finish(_ ok: Bool) {
        guard !finished else { return }
        finished = true
        onFinish(ok)
    }

    private func digitKey(_ d: Int, _ size: CGFloat) -> some View {
        Button { type(d) } label: {
            Text(verbatim: ar(d))
                .font(Theme.font(size * 0.42, .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
        }
        .buttonStyle(PadKeyStyle())
        .disabled(keysOff)
        .opacity(blockedFor > 0 ? 0.4 : 1)
        .accessibilityLabel(Text(verbatim: "\(d)"))
    }

    private func type(_ d: Int) {
        guard !keysOff, entry.count < PlayerLockCode.length else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        message = nil
        entry.append(String(d))
        guard entry.count == PlayerLockCode.length else { return }
        // الرمز يؤخذ الآن، ولحظة قصيرة حتى تظهر النقطة الأخيرة قبل الحكم
        let code = entry
        checking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { checking = false; evaluate(code) }
    }

    private func evaluate(_ code: String) {
        switch purpose {
        case .create:
            if first == nil {
                first = code; entry = ""
            } else if first == code {
                if PlayerLockCode.set(code) { succeed() } else { fail(L("تعذّر حفظ الرمز، حاول مرة ثانية")); first = nil }
            } else {
                first = nil
                fail(L("الرمزان مختلفان، اختر الرمز من جديد"))
            }
        case .unlock, .verifyToChange, .verifyToRemove:
            if PlayerLockCode.verify(code) {
                PlayerLockCode.registerSuccess(); succeed()
            } else {
                PlayerLockCode.registerFailure()
                fail(L("الرمز غير صحيح"))
            }
        }
    }

    private func fail(_ msg: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        message = msg
        entry = ""
        now = Date()
        if !reduceMotion { withAnimation(.linear(duration: 0.42)) { shakes += 1 } }
    }

    private func succeed() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.2)) { success = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { finish(true) }
    }

    @MainActor private func faceID() async {
        guard !success, !finished else { return }
        if await PlayerLockCode.ownerAuth() {
            PlayerLockCode.registerSuccess()
            succeed()
        }
    }
}

/// مفتاح زجاجي دائري: يتوهّج بالذهبي لحظة الضغط
private struct PadKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(configuration.isPressed ? Theme.gold.opacity(0.32) : Color.white.opacity(0.09)))
            .overlay(Circle().stroke(configuration.isPressed ? Theme.gold.opacity(0.7) : Color.white.opacity(0.16), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// اهتزاز أفقي عند الخطأ
private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 6), y: 0))
    }
}

// MARK: - طبقة القفل للمشغّلات المبنية بـ SwiftUI (التلفزيون)

/// زر القفل: مفتوح ⇠ قائمة (بلا رمز / برمز / تغيير / حذف)، مقفل ⇠ حلقة تمتلئ بالضغط المطوّل
struct PlayerLockKnob: View {
    @Binding var mode: PlayerLockMode
    var onPad: (PlayerLockFlow.Purpose) -> Void
    var size: CGFloat = 44
    @State private var holding = false
    @State private var codeSet = PlayerLockCode.isSet

    var body: some View {
        Group {
            if mode == .open {
                Menu {
                    Button { mode = .hold } label: { Label(L("قفل الشاشة"), systemImage: "lock") }
                    Button {
                        if PlayerLockCode.isSet { mode = .code } else { onPad(.create(lockAfter: true)) }
                    } label: { Label(L("قفل برمز سري"), systemImage: "lock.shield") }
                    if codeSet {
                        Section {
                            Button { onPad(.verifyToChange) } label: { Label(L("تغيير الرمز السري"), systemImage: "key") }
                            Button(role: .destructive) { onPad(.verifyToRemove) } label: { Label(L("حذف الرمز السري"), systemImage: "trash") }
                        }
                    }
                } label: {
                    face("lock.open", tint: .white)
                }
                .onAppear { codeSet = PlayerLockCode.isSet }
                .accessibilityLabel(L("قفل المشغّل"))
            } else {
                face(mode == .code ? "lock.shield.fill" : "lock.fill", tint: Theme.gold)
                    .overlay(
                        Circle().trim(from: 0, to: holding ? 1 : 0)
                            .stroke(Theme.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(-4)
                            .animation(holding ? .linear(duration: 1.2) : .easeOut(duration: 0.2), value: holding)
                    )
                    .onLongPressGesture(minimumDuration: 1.2, perform: {
                        holding = false
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if mode == .code { onPad(.unlock) } else { mode = .open }
                    }, onPressingChanged: { holding = $0 })
                    .accessibilityLabel(L("المشغّل مقفل"))
                    .accessibilityHint(PlayerLockFlow.hint(mode))
                    .accessibilityAction { if mode == .code { onPad(.unlock) } else { mode = .open } }
            }
        }
    }

    private func face(_ icon: String, tint: Color) -> some View {
        Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(.ultraThinMaterial))
            .overlay(Circle().stroke(tint.opacity(0.35), lineWidth: 1))
            .contentShape(Circle())
    }
}

/// تغطي المشغّل كاملًا عند القفل: تمنع اللمس، وتعرض تلميح الفتح ولوحة الرمز
struct PlayerLockLayer: View {
    @Binding var mode: PlayerLockMode
    var knobCenter: CGPoint
    @State private var pad: PlayerLockFlow.Purpose?
    @State private var hint = false
    @State private var hintWork: DispatchWorkItem?
    /// يتجدد زر القفل بعد كل لوحة (فتظهر/تختفي «تغيير الرمز» و«حذف الرمز» حسب الحال الآن)
    @State private var rev = 0

    var body: some View {
        ZStack {
            if mode != .open {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { showHint() }
                    .accessibilityHidden(true)
            }
            PlayerLockKnob(mode: $mode) { pad = $0 }
                .id(rev)
                .position(knobCenter)
            if hint && mode != .open {
                Label(PlayerLockFlow.hint(mode), systemImage: mode == .code ? "lock.shield.fill" : "lock.fill")
                    .font(Theme.f(.subheadline, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().stroke(Theme.gold.opacity(0.35), lineWidth: 1))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .allowsHitTesting(false)
            }
            if let p = pad {
                PasscodePad(purpose: p) { ok in
                    let r = PlayerLockFlow.after(p, ok: ok)
                    if let m = r.mode { mode = m }
                    withAnimation(.easeOut(duration: 0.2)) { pad = r.next }
                    rev += 1
                }
                .id(p == .create(lockAfter: false) ? "create2" : "\(p)")
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.2), value: pad)
        .onChange(of: mode) { _, m in if m == .open { hint = false } }
    }

    private func showHint() {
        hintWork?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { hint = true }
        let w = DispatchWorkItem { withAnimation(.easeIn(duration: 0.3)) { hint = false } }
        hintWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: w)
    }
}

/// مكان مركز زر القفل في المشغّل (منتصف الحافة الجانبية لمنطقة الفيديو)
struct PlayerLockAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

// MARK: - لوحة الرمز فوق مشغّل UIKit (مشغّل فيديو الملفات)

@MainActor
final class PasscodeHost {
    private var host: UIHostingController<PasscodePad>?

    func present(_ p: PlayerLockFlow.Purpose, over vc: UIViewController, done: @escaping (PlayerLockFlow.Purpose, Bool) -> Void) {
        dismiss()
        let h = UIHostingController(rootView: PasscodePad(purpose: p) { ok in done(p, ok) })
        h.view.backgroundColor = .clear
        h.view.translatesAutoresizingMaskIntoConstraints = false
        h.view.alpha = 0
        vc.addChild(h)
        vc.view.addSubview(h.view)
        NSLayoutConstraint.activate([
            h.view.topAnchor.constraint(equalTo: vc.view.topAnchor), h.view.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
            h.view.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor), h.view.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
        ])
        h.didMove(toParent: vc)
        host = h
        UIView.animate(withDuration: 0.2) { h.view.alpha = 1 }
    }

    func dismiss() {
        guard let h = host else { return }
        host = nil
        UIView.animate(withDuration: 0.18, animations: { h.view.alpha = 0 }) { _ in
            h.willMove(toParent: nil); h.view.removeFromSuperview(); h.removeFromParent()
        }
    }
}
