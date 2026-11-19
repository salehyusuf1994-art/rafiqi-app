import SwiftUI
import WidgetKit
import AppIntents

// MARK: - عناصر ويدجت الوسائط

func mmss(_ s: Double) -> String {
    let t = max(0, Int(s.isFinite ? s : 0))
    // بأرقام التطبيق (عربية افتراضيًا) مثل بقية الويدجت
    return ar(t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60))
}

/// غلاف المقطع: تدرّج حسب المصدر مع رمزه
struct MediaArt: View {
    let source: MediaSource
    var corner: CGFloat = 14
    /// اسم السورة يُكتب على الغلاف بخط الثلث بدل الرمز
    var label: String? = nil
    /// خلفية فقط (بلا اسم ولا رمز) — حين تكون الأزرار فوق الغلاف
    var plain = false
    /// ألوان هادئة متناسقة لكل مصدر (فاتح، أوسط، داكن) — مثل أغلفة الألبومات الحديثة
    var colors: [Color] {
        switch source {
        case .quran: return [Color(red: 0.89, green: 0.76, blue: 0.52), Color(red: 0.55, green: 0.38, blue: 0.20), Color(red: 0.13, green: 0.10, blue: 0.08)]
        case .radio: return [Color(red: 0.42, green: 0.78, blue: 0.80), Color(red: 0.16, green: 0.33, blue: 0.55), Color(red: 0.06, green: 0.08, blue: 0.15)]
        case .music: return [Color(red: 0.96, green: 0.56, blue: 0.62), Color(red: 0.50, green: 0.36, blue: 0.80), Color(red: 0.10, green: 0.10, blue: 0.22)]
        case .files: return [Color(red: 0.55, green: 0.80, blue: 0.72), Color(red: 0.20, green: 0.38, blue: 0.40), Color(red: 0.06, green: 0.09, blue: 0.11)]
        }
    }
    var icon: String {
        switch source {
        case .quran: return "book.closed.fill"
        case .radio: return "dot.radiowaves.left.and.right"
        case .music: return "music.note"
        case .files: return "waveform"
        }
    }
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, m = min(w, h)
            ZStack {
                // قاعدة داكنة ثم بقعتا ضوء ناعمتان (تدرّج شبكي) — بدل التدرّج الخطي الصارخ
                colors[2]
                RadialGradient(colors: [colors[0].opacity(0.95), colors[0].opacity(0)], center: UnitPoint(x: 0.22, y: 0.18),
                               startRadius: 0, endRadius: m * 0.95)
                RadialGradient(colors: [colors[1].opacity(0.9), colors[1].opacity(0)], center: UnitPoint(x: 0.85, y: 0.9),
                               startRadius: 0, endRadius: m * 1.0)
                // قوس ضوء رفيع يعطي عمقًا
                Circle().stroke(Color.white.opacity(0.16), lineWidth: max(0.8, m * 0.008))
                    .frame(width: m * 1.5, height: m * 1.5)
                    .offset(x: w * 0.42, y: -h * 0.38)
                Circle().stroke(Color.white.opacity(0.09), lineWidth: max(0.8, m * 0.008))
                    .frame(width: m * 1.15, height: m * 1.15)
                    .offset(x: w * 0.42, y: -h * 0.38)
                if plain {
                    EmptyView()
                } else if let label, source == .quran, w > 40 {
                    Text(label)
                        .font(.custom("DecoTypeThuluthII", size: min(w * 0.3, h * 0.42)))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .padding(.horizontal, w * 0.08)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: m * 0.3, weight: .medium))
                        .foregroundStyle(.white.opacity(0.94))
                        .shadow(color: .black.opacity(0.25), radius: m * 0.04, y: m * 0.015)
                }
            }
            // الإطار أعرض من الغلاف: نثبّت الحجم قبل القص حتى لا يتمدد فوق ما بجانبه
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            // حافة زجاجية: لمعة علوية تتلاشى
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8))
        }
    }
}

/// عنوان المقطع بالخط المختار
struct MTitle: View {
    let text: String
    var size: CGFloat = 17
    @Environment(\.wfont) private var wf
    var body: some View {
        // النسخ والنستعليق سطرها أطول بكثير من حروفها: لا تُصغَّر بسبب الارتفاع (كانت تظهر صغيرة جدًا)، بل بالعرض فقط
        let k: CGFloat = wf == .nastaliq ? 1.25 : (wf == .naskh || wf == .ruqaa ? 1.12 : 1)
        Text(text)
            .font(wf == .thuluth ? .custom("DecoTypeThuluthII", size: size * 1.45) : .custom(wf.ps, size: size * k))
            .foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.5)
            .fixedSize(horizontal: false, vertical: true)
            // سطر النستعليق أعلى بكثير من حروفه: يُحجز له ارتفاع الحروف فقط (كان يدفع القرص والأسماء إلى حافة الويدجت)
            .frame(height: wf == .nastaliq ? size * k * 1.45 : nil)
    }
}

struct MSub: View {
    let text: String
    var size: CGFloat = 12
    var body: some View {
        Text(text).font(.system(size: size, weight: .medium)).foregroundStyle(TXT.opacity(0.55)).lineLimit(1)
    }
}

/// زر تحكم يعمل من الويدجت مباشرة
struct MBtn: View {
    let action: String
    let icon: String
    var size: CGFloat = 34
    var fill: Double = 0.14
    var round = true
    var scale: CGFloat = 0.36
    var solid = false
    @Environment(\.mediaSource) private var src
    var body: some View {
        Button(intent: MediaControlIntent(action, source: src)) {
            Image(systemName: icon)
                .font(.system(size: size * scale, weight: .bold))
                .foregroundStyle(solid ? Color.black : Color.white)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: round ? size / 2 : size * 0.28, style: .continuous)
                    .fill(solid ? Color.white : Color.white.opacity(fill)))
                // حافة زجاجية: أفتح من أعلى وتخفت للأسفل
                .overlay(RoundedRectangle(cornerRadius: round ? size / 2 : size * 0.28, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(solid || fill == 0 ? 0 : 0.30), Color.white.opacity(solid || fill == 0 ? 0 : 0.06)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// اسم الزر لقارئ الشاشة
    private var label: String {
        switch action {
        case "next": return L("التالي")
        case "prev": return L("السابق")
        case "repeat": return L("التكرار")
        case "shuffle": return L("تشغيل عشوائي")
        default: return L(icon.contains("pause") || icon.contains("stop") ? "إيقاف" : "تشغيل")
        }
    }
}

/// أزرار السابق / تشغيل / التالي (مع التكرار والعشوائي اختياريًا)
struct MControls: View {
    let np: NowPlaying
    var small: CGFloat = 30
    var big: CGFloat = 42
    var spacing: CGFloat = 10
    var extras = false
    var bigSolid = false
    var body: some View {
        HStack(spacing: spacing) {
            if extras {
                MBtn(action: "shuffle", icon: "shuffle", size: small, fill: 0, scale: 0.42)
                    .opacity(np.shuffle ? 1 : 0.55)
            }
            MBtn(action: "prev", icon: "backward.fill", size: small)
            MBtn(action: "toggle", icon: np.playing ? "pause.fill" : "play.fill", size: big, fill: 0.2, solid: bigSolid)
            MBtn(action: "next", icon: "forward.fill", size: small)
            if extras {
                MBtn(action: "repeat", icon: np.repeatOne ? "repeat.1" : "repeat", size: small, fill: 0, scale: 0.42)
                    .opacity(np.repeatOne ? 1 : 0.55)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// شريط التقدّم (حي أثناء التشغيل) أو «مباشر» للإذاعة
struct MProgress: View {
    let np: NowPlaying
    var body: some View {
        Group {
            if np.live {
                HStack(spacing: 5) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text(Lang.isEN ? "LIVE" : "مباشر").font(.system(size: 10, weight: .bold)).foregroundStyle(TXT)
                    Capsule().fill(Color.white.opacity(0.25)).frame(height: 3)
                }
            } else if np.playing && np.timed {
                ProgressView(timerInterval: np.startDate...np.startDate.addingTimeInterval(np.duration), countsDown: false,
                             label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .progressViewStyle(.linear).tint(.white)
            } else {
                // شريط ثابت مرسوم (يظهر كما هو في كل مكان)
                let p = np.duration > 0 ? min(1, max(0, np.position / np.duration)) : 0
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.white).frame(width: max(0, g.size.width * p))
                    }
                }
                .frame(height: 4)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct MTimes: View {
    let np: NowPlaying
    var body: some View {
        HStack {
            Group {
                if np.playing && np.timed {
                    Text(timerInterval: np.startDate...np.startDate.addingTimeInterval(max(1, np.duration)), countsDown: false)
                } else {
                    Text(mmss(np.position))
                }
            }
            Spacer(minLength: 0)
            Text(np.live ? (Lang.isEN ? "LIVE" : "مباشر") : (np.duration > 0 ? mmss(np.duration) : "--:--"))
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(TXT.opacity(0.5))
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// موجة صوتية ثابتة الشكل حسب العنوان، ملوّنة حتى موضع التشغيل
struct Waveform: View {
    let np: NowPlaying
    var count = 46
    var height: CGFloat = 28
    var color: Color = .white
    var body: some View {
        let seed: Int = np.title.unicodeScalars.reduce(7) { (acc: Int, u: Unicode.Scalar) -> Int in (acc &* 31 &+ Int(u.value)) % 100_003 }
        let p: Double = np.live ? 1.0 : (np.duration > 0 ? np.elapsed() / np.duration : 0)
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(Double(i) < p * Double(count) ? color : color.opacity(0.28))
                    .frame(width: 2.4, height: barHeight(i, seed: seed))
            }
        }
        .frame(height: height)
        .environment(\.layoutDirection, .leftToRight)
    }

    /// ارتفاع العمود رقم i (مفصول في دالة مستقلة لتسريع فحص الأنواع في المترجم)
    private func barHeight(_ i: Int, seed: Int) -> CGFloat {
        let mixed: Int = (seed &* (i + 3) &* 7_919) % 97
        let r: Double = Double(abs(mixed)) / 97
        let wave: Double = abs(sin(Double(i) * 0.55 + r * 3))
        let scale: Double = 0.55 + 0.45 * r
        let h: CGFloat = height * CGFloat(0.18 + 0.82 * wave * scale)
        return max(3, h)
    }
}

/// أسطوانة: أخاديد حقيقية بكثافة متفاوتة، ولمعة ضوء مائلة، وملصق في الوسط بثقب
struct Vinyl: View {
    let source: MediaSource
    var size: CGFloat = 110
    var label: String? = nil
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(white: 0.13), Color(white: 0.05)], center: .center, startRadius: 0, endRadius: size / 2))
            // الأخاديد: حلقات رفيعة متقاربة، مع فواصل أوسع بين «المقاطع»
            ForEach(0..<22, id: \.self) { k in
                let r = size * (0.48 - CGFloat(k) * 0.0118)
                Circle().stroke(Color.white.opacity(k % 6 == 5 ? 0.02 : (k % 2 == 0 ? 0.075 : 0.045)), lineWidth: 0.6)
                    .frame(width: r * 2, height: r * 2)
            }
            // لمعة الضوء على الفينيل (قطاعان متقابلان)
            Circle().fill(AngularGradient(gradient: Gradient(stops: [
                .init(color: .clear, location: 0.0), .init(color: Color.white.opacity(0.16), location: 0.08), .init(color: .clear, location: 0.18),
                .init(color: .clear, location: 0.5), .init(color: Color.white.opacity(0.12), location: 0.58), .init(color: .clear, location: 0.68),
                .init(color: .clear, location: 1.0)]), center: .center, angle: .degrees(-30)))
                .blendMode(.screen)
            // حافة خارجية
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            // الملصق
            MediaArt(source: source, corner: size, label: label, plain: label == nil)
                .frame(width: size * 0.4, height: size * 0.4).clipShape(Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.8))
            // الثقب ومحوره
            Circle().fill(Color(white: 0.85)).frame(width: size * 0.045, height: size * 0.045)
            Circle().fill(Color(white: 0.2)).frame(width: size * 0.02, height: size * 0.02)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
    }
}

/// بكرة الكاسيت: حلقة شريط داكنة وبكرة بستة أسنان
private struct TapeReel: View {
    let tape: CGFloat   // نصف قطر الشريط الملفوف
    let hub: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.22, green: 0.16, blue: 0.12)).frame(width: tape * 2, height: tape * 2)
            Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.6).frame(width: tape * 2, height: tape * 2)
            Circle().fill(Color(white: 0.92)).frame(width: hub * 2, height: hub * 2)
            ForEach(0..<6, id: \.self) { k in
                Capsule().fill(Color(white: 0.55)).frame(width: hub * 0.22, height: hub * 0.5)
                    .offset(y: -hub * 0.62).rotationEffect(.degrees(Double(k) * 60))
            }
            Circle().fill(Color(white: 0.35)).frame(width: hub * 0.55, height: hub * 0.55)
        }
    }
}

/// شريط كاسيت: هيكل ببراغي، ملصق بعنوان المقطع، نافذة ببكرتين وشريط بينهما، وقاعدة شبه منحرفة
struct Cassette: View {
    let np: NowPlaying
    var body: some View {
        let p = np.live ? 0.5 : (np.duration > 0 ? min(1, max(0, np.elapsed() / np.duration)) : 0)
        let cols = MediaArt(source: np.source).colors
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let rMax = h * 0.2, rMin = h * 0.1
            ZStack {
                // الهيكل
                RoundedRectangle(cornerRadius: h * 0.09, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.13)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: h * 0.09, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                // البراغي في الأركان
                ForEach(0..<4, id: \.self) { k in
                    Circle().fill(Color(white: 0.42)).frame(width: h * 0.05, height: h * 0.05)
                        .overlay(Capsule().fill(Color(white: 0.2)).frame(width: h * 0.035, height: 0.8).rotationEffect(.degrees(35)))
                        .position(x: k % 2 == 0 ? h * 0.08 : w - h * 0.08, y: k < 2 ? h * 0.08 : h * 0.92)
                }
                // الملصق
                RoundedRectangle(cornerRadius: h * 0.05, style: .continuous)
                    .fill(LinearGradient(colors: [cols[0], cols[1]], startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * 0.84, height: h * 0.66)
                    .position(x: w / 2, y: h * 0.42)
                Text(np.title).font(.system(size: max(9, h * 0.1), weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: w * 0.74).position(x: w / 2, y: h * 0.17)
                // النافذة
                RoundedRectangle(cornerRadius: h * 0.12, style: .continuous).fill(Color.black.opacity(0.72))
                    .frame(width: w * 0.62, height: h * 0.32).position(x: w / 2, y: h * 0.46)
                // البكرتان: الشريط ينتقل من اليسرى إلى اليمنى مع التقدّم
                TapeReel(tape: rMin + (rMax - rMin) * CGFloat(1 - p), hub: h * 0.075).position(x: w * 0.32, y: h * 0.46)
                TapeReel(tape: rMin + (rMax - rMin) * CGFloat(p), hub: h * 0.075).position(x: w * 0.68, y: h * 0.46)
                RoundedRectangle(cornerRadius: h * 0.12, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 0.6)
                    .frame(width: w * 0.62, height: h * 0.32).position(x: w / 2, y: h * 0.46)
                // القاعدة شبه المنحرفة
                Path { q in
                    q.move(to: CGPoint(x: w * 0.2, y: h)); q.addLine(to: CGPoint(x: w * 0.26, y: h * 0.8))
                    q.addLine(to: CGPoint(x: w * 0.74, y: h * 0.8)); q.addLine(to: CGPoint(x: w * 0.8, y: h))
                }
                .fill(Color(white: 0.1))
                ForEach(0..<2, id: \.self) { k in
                    Circle().fill(Color.black.opacity(0.7)).frame(width: h * 0.06, height: h * 0.06)
                        .position(x: w * (k == 0 ? 0.36 : 0.64), y: h * 0.9)
                }
            }
        }
        .aspectRatio(1.58, contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// مصفوفة نقاط تمتلئ مع التقدّم
struct DotMatrix: View {
    let np: NowPlaying
    var cols = 18
    var rows = 3
    var body: some View {
        let p = np.live ? 1.0 : (np.duration > 0 ? np.elapsed() / np.duration : 0)
        VStack(spacing: 3) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 3) {
                    ForEach(0..<cols, id: \.self) { c in
                        Circle().fill(Double(c) < p * Double(cols) ? Color.white : Color.white.opacity(0.2 - Double(r) * 0.04))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - الويدجت الصغيرة

/// غلاف ويدجت الوسائط: الحالة الحالية + Root
struct MRoot<Content: View>: View {
    let entry: HEntry
    @ViewBuilder let content: (NowPlaying) -> Content
    var body: some View {
        var np = NowPlaying.display(for: entry.media)
        // التقدّم عند وقت المدخل نفسه (الويدجت قد تُرسم مسبقًا)
        if np.playing && !entry.inApp {
            np.position = np.elapsed(at: entry.date)
            np.at = entry.date.timeIntervalSince1970
        }
        return Root(entry: entry) { content(np).environment(\.mediaSource, entry.media) }
    }
}

struct MediaCtrlView: View {          // «تحكم»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                MTitle(text: np.title, size: 19)
                MSub(text: np.subtitle)
                Spacer(minLength: 0)
                MControls(np: np, small: 32, big: 50, spacing: 8)
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }
}

struct MediaCassetteView: View {      // «كاسيت»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            VStack(spacing: 12) {
                Cassette(np: np)
                MControls(np: np, small: 32, big: 42, spacing: 8)
            }
            .padding(14)
        }
    }
}

struct MediaBigButtonView: View {     // «زر كبير»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            VStack(spacing: 6) {
                MTitle(text: np.title, size: 16)
                HStack(spacing: 10) {
                    MBtn(action: "prev", icon: "backward.fill", size: 30, fill: 0)
                    MBtn(action: "toggle", icon: np.playing ? "pause.fill" : "play.fill", size: 66, fill: 0.2, scale: 0.4)
                    MBtn(action: "next", icon: "forward.fill", size: 30, fill: 0)
                }
                .environment(\.layoutDirection, .leftToRight)
                MSub(text: np.subtitle)
            }
            .padding(12)
        }
    }
}

struct MediaCardView: View {          // «بطاقة»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            VStack(spacing: 6) {
                MediaArt(source: np.source, corner: 12, label: np.title).frame(width: 128, height: 40)
                MTitle(text: np.title, size: 15)
                MSub(text: np.subtitle, size: 11)
                MControls(np: np, small: 28, big: 38, spacing: 8)
            }
            .padding(12)
        }
    }
}

struct MediaRingView: View {          // «حلقة»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            ZStack {
                MediaArt(source: np.source, corner: 0, plain: true).opacity(0.85)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        MBtn(action: "prev", icon: "backward.fill", size: 30, fill: 0.22)
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.25), lineWidth: 3)
                            Circle().trim(from: 0, to: np.live ? 1 : (np.duration > 0 ? np.elapsed() / np.duration : 0))
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round)).ringStart()
                            MBtn(action: "toggle", icon: np.playing ? "pause.fill" : "play.fill", size: 40, fill: 0.25)
                        }
                        .frame(width: 50, height: 50)
                        MBtn(action: "next", icon: "forward.fill", size: 30, fill: 0.22)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    MTitle(text: np.title, size: 15)
                    MSub(text: np.subtitle, size: 11)
                }
                .padding(12)
            }
        }
    }
}

struct MediaCoverView: View {         // «غلاف»
    let entry: HEntry
    var body: some View {
        // الغلاف خلفية كاملة، ورمزه صغير في الأعلى؛ والعنوان في سطره بعرض الويدجت، ثم الوصف وزر التشغيل — بلا تداخل
        MRoot(entry: entry) { np in
            ZStack {
                MediaArt(source: np.source, corner: 0, plain: true)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                VStack(spacing: 4) {
                    Image(systemName: MediaArt(source: np.source).icon)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .padding(.top, 16)
                    Spacer(minLength: 0)
                    MTitle(text: np.title, size: 14)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 6)
                    HStack(spacing: 8) {
                        MSub(text: np.subtitle, size: 10)
                        Spacer(minLength: 0)
                        MBtn(action: "toggle", icon: np.playing ? "pause.fill" : "play.fill", size: 34, fill: 0.28)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
    }
}

struct MediaVinylView: View {         // «أسطوانة»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            VStack(spacing: 6) {
                ZStack {
                    Vinyl(source: np.source, size: 96, label: np.title)
                    MBtn(action: "toggle", icon: np.playing ? "pause.fill" : "play.fill", size: 34, fill: 0.3)
                }
                MTitle(text: np.title, size: 15)
                MSub(text: np.subtitle, size: 11)
            }
            .padding(10)
        }
    }
}

struct MediaGlowView: View {          // «وهج»
    let entry: HEntry
    var body: some View {
        // ترتيب ثابت بلا تداخل: نصف أسطوانة أعلى، ثم العنوان بعرض الويدجت، ثم سطر الوصف وزر التشغيل
        MRoot(entry: entry) { np in
            VStack(spacing: 6) {
                Vinyl(source: np.source, size: 116, label: np.title)
                    .frame(width: 116, height: 62, alignment: .bottom)
                    .clipped()
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                MTitle(text: np.title, size: 14)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                HStack(spacing: 8) {
                    MSub(text: np.subtitle, size: 10)
                    Spacer(minLength: 0)
                    MBtn(action: "toggle", icon: np.playing ? "pause.fill" : "play.fill", size: 34, fill: 0.2)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 10).padding(.top, 10)
        }
    }
}

struct MediaPadView: View {           // «لوحة»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            VStack(spacing: 6) {
                MTitle(text: np.title, size: 14)
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        MBtn(action: "repeat", icon: np.repeatOne ? "repeat.1" : "repeat", size: 48, fill: np.repeatOne ? 0.24 : 0.12, round: false, scale: 0.36)
                        MBtn(action: "toggle", icon: np.playing ? "pause.fill" : "play.fill", size: 48, fill: 0.16, round: false, scale: 0.36)
                    }
                    HStack(spacing: 6) {
                        MBtn(action: "prev", icon: "backward.fill", size: 48, fill: 0.12, round: false, scale: 0.32)
                        MBtn(action: "next", icon: "forward.fill", size: 48, fill: 0.12, round: false, scale: 0.32)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                MSub(text: np.subtitle, size: 10)
            }
            .padding(10)
        }
    }
}

struct MediaOrbitView: View {         // «دائري»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 6).frame(width: 140, height: 140)
                Circle().trim(from: 0, to: np.live ? 1 : (np.duration > 0 ? np.elapsed() / np.duration : 0))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .ringStart().frame(width: 140, height: 140)
                HStack(spacing: 4) {
                    MBtn(action: "prev", icon: "backward.end.fill", size: 30, fill: 0)
                    ZStack {
                        Circle().fill(Color.white.opacity(0.12)).frame(width: 58, height: 58)
                        MBtn(action: "toggle", icon: np.playing ? "pause.fill" : "play.fill", size: 58, fill: 0, scale: 0.36)
                    }
                    MBtn(action: "next", icon: "forward.end.fill", size: 30, fill: 0)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
        }
    }
}

struct MediaDotsView: View {          // «نقاط»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            VStack(spacing: 6) {
                MTitle(text: np.title, size: 16)
                MSub(text: np.subtitle, size: 11)
                HStack(spacing: 12) {
                    MBtn(action: "prev", icon: "backward.end.fill", size: 26, fill: 0)
                    MBtn(action: "toggle", icon: np.playing ? "pause.fill" : "play.fill", size: 36, fill: 0, solid: true)
                    MBtn(action: "next", icon: "forward.end.fill", size: 26, fill: 0)
                }
                .environment(\.layoutDirection, .leftToRight)
                DotMatrix(np: np, cols: 17, rows: 3)
            }
            .padding(10)
        }
    }
}

struct MediaBarView: View {           // «شريط»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            VStack(spacing: 8) {
                MTitle(text: np.title, size: 17)
                MSub(text: np.subtitle, size: 11)
                HStack(spacing: 12) {
                    MBtn(action: "prev", icon: "backward.end.fill", size: 28, fill: 0)
                    MBtn(action: "toggle", icon: np.playing ? "pause.fill" : "play.fill", size: 40, fill: 0, solid: true)
                    MBtn(action: "next", icon: "forward.end.fill", size: 28, fill: 0)
                }
                .environment(\.layoutDirection, .leftToRight)
                MProgress(np: np).frame(width: 128)
            }
            .padding(12)
        }
    }
}

// MARK: - الويدجت المتوسطة

struct MediaWaveView: View {          // «موجة»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    MediaArt(source: np.source, corner: 10, label: np.title).frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 1) {
                        MTitle(text: np.title, size: 17)
                        MSub(text: np.subtitle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "headphones").font(.system(size: 16)).foregroundStyle(TXT.opacity(0.5))
                }
                Waveform(np: np, count: 60, height: 26)
                MTimes(np: np)
                MControls(np: np, small: 30, big: 36, spacing: 14, extras: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

struct MediaPlayerView: View {        // «مشغّل»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            HStack(spacing: 14) {
                MediaArt(source: np.source, corner: 18, label: np.title).frame(width: 128, height: 128)
                VStack(alignment: .leading, spacing: 6) {
                    MTitle(text: np.title, size: 18)
                    MSub(text: np.subtitle)
                    Spacer(minLength: 0)
                    MProgress(np: np)
                    MTimes(np: np)
                    MControls(np: np, small: 28, big: 34, spacing: 8, extras: true)
                }
            }
            .padding(14)
        }
    }
}

struct MediaStageView: View {         // «منصة»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            ZStack {
                // الغلاف في الجهة المقابلة للنص (يسار بالعربية، يمين بالإنجليزية) ويتلاشى نحوه
                let artLeft = !Lang.isEN
                HStack(spacing: 0) {
                    if !artLeft { Spacer(minLength: 0) }
                    MediaArt(source: np.source, corner: 0, label: np.title).frame(width: 190)
                        .mask(LinearGradient(colors: artLeft ? [.black, .clear] : [.clear, .black], startPoint: .leading, endPoint: .trailing))
                    if artLeft { Spacer(minLength: 0) }
                }
                .environment(\.layoutDirection, .leftToRight)
                VStack(alignment: .leading, spacing: 2) {
                    MTitle(text: np.title, size: 19)
                    MSub(text: np.subtitle)
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        MBtn(action: "prev", icon: "backward.fill", size: 40, fill: 0.14, round: false)
                        MBtn(action: "toggle", icon: np.playing ? "pause.fill" : "play.fill", size: 40, fill: 0.2, round: false)
                        MBtn(action: "next", icon: "forward.fill", size: 40, fill: 0.14, round: false)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
    }
}

struct MediaConsoleView: View {       // «وحدة تحكم»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        MediaArt(source: np.source, corner: 10, label: np.title).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 1) {
                            MTitle(text: np.title, size: 17)
                            MSub(text: np.subtitle)
                        }
                    }
                    Spacer(minLength: 0)
                    MProgress(np: np)
                    MTimes(np: np)
                }
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Link(destination: URL(string: "miqat://media")!) {
                            Image(systemName: MediaArt(source: np.source).icon).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 54, height: 54)
                                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(0.12)))
                                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
                        }
                        MBtn(action: "toggle", icon: np.playing ? "pause.fill" : "play.fill", size: 54, fill: 0.16, round: false, scale: 0.34)
                    }
                    HStack(spacing: 8) {
                        MBtn(action: "prev", icon: "backward.fill", size: 54, fill: 0.12, round: false, scale: 0.3)
                        MBtn(action: "next", icon: "forward.fill", size: 54, fill: 0.12, round: false, scale: 0.3)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(14)
        }
    }
}

struct MediaOrbitMView: View {        // «مدار»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    MTitle(text: np.title, size: 19)
                    MSub(text: np.subtitle)
                    HStack(spacing: 4) {
                        Group {
                            if np.playing && np.timed {
                                Text(timerInterval: np.startDate...np.startDate.addingTimeInterval(max(1, np.duration)), countsDown: false)
                            } else {
                                Text(np.live ? (Lang.isEN ? "LIVE" : "مباشر") : mmss(np.position))
                            }
                        }
                        .font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                        if np.timed {
                            Text("/ " + mmss(np.duration)).font(.system(size: 13).monospacedDigit()).foregroundStyle(TXT.opacity(0.5))
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.top, 4)
                    MControls(np: np, small: 30, big: 36, spacing: 8)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 5)
                    Circle().trim(from: 0, to: np.live ? 1 : (np.duration > 0 ? np.elapsed() / np.duration : 0))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round)).ringStart()
                    MediaArt(source: np.source, corner: 60, label: np.title).frame(width: 96, height: 96).clipShape(Circle())
                }
                .frame(width: 118, height: 118)
            }
            .padding(16)
        }
    }
}

struct MediaTurntableView: View {     // «جرامافون»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    Vinyl(source: np.source, size: 110, label: np.title).frame(maxWidth: .infinity, maxHeight: .infinity)
                    // ذراع الإبرة: قاعدة دوّارة، ذراع معدني بانحناءة، ورأس الإبرة
                    ZStack(alignment: .top) {
                        Circle().fill(RadialGradient(colors: [Color(white: 0.85), Color(white: 0.45)], center: .topLeading, startRadius: 0, endRadius: 12))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().fill(Color(white: 0.3)).frame(width: 5, height: 5))
                        Path { q in
                            q.move(to: CGPoint(x: 8, y: 8)); q.addLine(to: CGPoint(x: 8, y: 58))
                            q.addQuadCurve(to: CGPoint(x: 0, y: 76), control: CGPoint(x: 8, y: 70))
                        }
                        .stroke(LinearGradient(colors: [Color(white: 0.9), Color(white: 0.55)], startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .frame(width: 16, height: 84)
                        RoundedRectangle(cornerRadius: 1.5).fill(Color(white: 0.8)).frame(width: 7, height: 11)
                            .rotationEffect(.degrees(30)).offset(x: -6, y: 74)
                    }
                    .frame(width: 16, height: 86)
                    .rotationEffect(.degrees(np.playing ? 20 : 4), anchor: UnitPoint(x: 0.5, y: 8 / 86))
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1.5)
                    .padding(.top, 8).padding(.trailing, 10)
                }
                .frame(width: 132, height: 132)
                .environment(\.layoutDirection, .leftToRight)
                VStack(alignment: .leading, spacing: 6) {
                    MTitle(text: np.title, size: 18)
                    MSub(text: np.subtitle)
                    Spacer(minLength: 0)
                    MProgress(np: np)
                    MTimes(np: np)
                    MControls(np: np, small: 28, big: 34, spacing: 8, extras: true)
                }
            }
            .padding(14)
        }
    }
}

struct MediaBookView: View {          // «كتاب»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            HStack(spacing: 14) {
                MediaArt(source: np.source, corner: 20, label: np.title).frame(width: 136, height: 136)
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: MediaArt(source: np.source).icon).font(.system(size: 14)).foregroundStyle(TXT.opacity(0.5))
                    Spacer(minLength: 0)
                    MTitle(text: np.title, size: 19)
                    MSub(text: np.subtitle)
                    HStack(spacing: 10) {
                        Group {
                            if np.playing && np.timed {
                                Text(timerInterval: np.startDate...np.startDate.addingTimeInterval(max(1, np.duration)), countsDown: false)
                            } else {
                                Text(np.live ? (Lang.isEN ? "LIVE" : "مباشر") : mmss(np.position))
                            }
                        }
                        .font(.system(size: 24, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(width: 80, alignment: .leading)
                        MBtn(action: "toggle", icon: np.playing ? "pause.fill" : "play.fill", size: 42, fill: 0.2)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }
}

struct MediaWheelView: View {         // «عجلة»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: MediaArt(source: np.source).icon).font(.system(size: 30)).foregroundStyle(TXT.opacity(0.59))
                    MProgress(np: np)
                    MTitle(text: np.title, size: 17)
                    MSub(text: np.subtitle)
                    MTimes(np: np)
                }
                .padding(12)
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
                ZStack {
                    Circle().fill(Color.white.opacity(0.08))
                    Circle().stroke(Color.white.opacity(0.14), lineWidth: 1)
                    Circle().fill(Color.white.opacity(0.1)).frame(width: 52, height: 52)
                    VStack(spacing: 0) {
                        Link(destination: URL(string: "miqat://media")!) {
                            Image(systemName: "music.note").font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(width: 34, height: 34)
                        }
                        HStack(spacing: 50) {
                            MBtn(action: "prev", icon: "backward.end.fill", size: 34, fill: 0, scale: 0.42)
                            MBtn(action: "next", icon: "forward.end.fill", size: 34, fill: 0, scale: 0.42)
                        }
                        MBtn(action: "toggle", icon: np.playing ? "pause.fill" : "play.fill", size: 34, fill: 0, scale: 0.42)
                    }
                }
                .frame(width: 140, height: 140)
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(12)
        }
    }
}

struct MediaSimpleView: View {        // «الوسائط»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    MTitle(text: np.title, size: 22)
                    MSub(text: np.subtitle, size: 14)
                    Spacer(minLength: 0)
                    MControls(np: np, small: 40, big: 46, spacing: 10)
                }
                Spacer(minLength: 0)
                MediaArt(source: np.source, corner: 24, label: np.title).frame(width: 124, height: 124)
            }
            .padding(16)
        }
    }
}

struct MediaSlimView: View {          // «وسائط موجة»
    let entry: HEntry
    var body: some View {
        MRoot(entry: entry) { np in
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    MediaArt(source: np.source, corner: 40, label: np.title).frame(width: 64, height: 64).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            MTitle(text: np.title, size: 16)
                            Text("•").foregroundStyle(TXT.opacity(0.42))
                            MSub(text: np.subtitle, size: 12)
                        }
                        MControls(np: np, small: 28, big: 34, spacing: 14)
                    }
                    Spacer(minLength: 0)
                }
                Waveform(np: np, count: 70, height: 30, color: Color(red: 0.45, green: 0.85, blue: 0.95))
                MTimes(np: np)
            }
            .padding(14)
        }
    }
}
