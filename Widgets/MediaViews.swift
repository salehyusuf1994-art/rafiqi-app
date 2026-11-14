import SwiftUI
import WidgetKit
import AppIntents

// MARK: - عناصر ويدجت الوسائط

func mmss(_ s: Double) -> String {
    let t = max(0, Int(s.isFinite ? s : 0))
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
}

/// غلاف المقطع: تدرّج حسب المصدر مع رمزه
struct MediaArt: View {
    let source: MediaSource
    var corner: CGFloat = 14
    /// اسم السورة يُكتب على الغلاف بخط الثلث بدل الرمز
    var label: String? = nil
    /// خلفية فقط (بلا اسم ولا رمز) — حين تكون الأزرار فوق الغلاف
    var plain = false
    var colors: [Color] {
        switch source {
        case .quran: return [Color(red: 0.86, green: 0.70, blue: 0.42), Color(red: 0.42, green: 0.28, blue: 0.14), Color(red: 0.12, green: 0.10, blue: 0.09)]
        case .radio: return [Color(red: 0.20, green: 0.62, blue: 0.70), Color(red: 0.12, green: 0.24, blue: 0.48), Color(red: 0.06, green: 0.08, blue: 0.16)]
        case .music: return [Color(red: 0.93, green: 0.38, blue: 0.56), Color(red: 0.52, green: 0.36, blue: 0.86), Color(red: 0.28, green: 0.62, blue: 0.86)]
        }
    }
    var icon: String {
        switch source {
        case .quran: return "book.closed.fill"
        case .radio: return "dot.radiowaves.left.and.right"
        case .music: return "music.note"
        }
    }
    var body: some View {
        GeometryReader { g in
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                Ellipse().stroke(Color.white.opacity(0.35), lineWidth: max(1, g.size.width * 0.012))
                    .frame(width: g.size.width * 1.3, height: g.size.height * 0.5)
                    .offset(y: -g.size.height * 0.28)
                    .blur(radius: 1)
                if plain {
                    EmptyView()
                } else if let label, source == .quran, g.size.width > 40 {
                    Text(label)
                        .font(.custom("DecoTypeThuluthII", size: min(g.size.width * 0.3, g.size.height * 0.42)))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .padding(.horizontal, g.size.width * 0.08)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: min(g.size.width, g.size.height) * 0.32, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            // الإطار البيضاوي أعرض من الغلاف: نثبّت الحجم قبل القص حتى لا يتمدد الغلاف فوق ما بجانبه
            .frame(width: g.size.width, height: g.size.height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }
}

/// عنوان المقطع بالخط المختار
struct MTitle: View {
    let text: String
    var size: CGFloat = 17
    @Environment(\.wfont) private var wf
    var body: some View {
        Text(text)
            .font(wf == .thuluth ? .custom("DecoTypeThuluthII", size: size * 1.45) : .custom(wf.ps, size: size))
            .foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.5)
    }
}

struct MSub: View {
    let text: String
    var size: CGFloat = 12
    var body: some View {
        Text(text).font(.system(size: size, weight: .medium)).foregroundStyle(TXT.opacity(0.65)).lineLimit(1)
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
                .overlay(RoundedRectangle(cornerRadius: round ? size / 2 : size * 0.28, style: .continuous)
                    .stroke(Color.white.opacity(solid ? 0 : 0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
        .foregroundStyle(TXT.opacity(0.6))
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
        let seed = np.title.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 100_003 }
        let p = np.live ? 1.0 : (np.duration > 0 ? np.elapsed() / np.duration : 0)
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                let r = Double(abs((seed &* (i + 3) &* 7_919) % 97)) / 97
                let h = height * CGFloat(0.18 + 0.82 * abs(sin(Double(i) * 0.55 + r * 3)) * (0.55 + 0.45 * r))
                Capsule().fill(Double(i) < p * Double(count) ? color : color.opacity(0.28))
                    .frame(width: 2.4, height: max(3, h))
            }
        }
        .frame(height: height)
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// أسطوانة
struct Vinyl: View {
    let source: MediaSource
    var size: CGFloat = 110
    var label: String? = nil
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.07))
            ForEach(1..<7, id: \.self) { k in
                Circle().stroke(Color.white.opacity(0.07), lineWidth: 1).padding(CGFloat(k) * size * 0.045)
            }
            MediaArt(source: source, corner: size, label: label).frame(width: size * 0.44, height: size * 0.44).clipShape(Circle())
            Circle().fill(Color(white: 0.06)).frame(width: size * 0.05, height: size * 0.05)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
    }
}

/// شريط كاسيت
struct Cassette: View {
    let np: NowPlaying
    var body: some View {
        VStack(spacing: 5) {
            Text(np.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: MediaArt(source: np.source).colors, startPoint: .leading, endPoint: .trailing)))
            HStack {
                Image(systemName: "gear").font(.system(size: 16)).foregroundStyle(TXT.opacity(0.75))
                Spacer()
                Image(systemName: "gear").font(.system(size: 16)).foregroundStyle(TXT.opacity(0.75))
            }
            .padding(.horizontal, 18).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.35)))
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.14), lineWidth: 1))
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
                    Image(systemName: "headphones").font(.system(size: 16)).foregroundStyle(TXT.opacity(0.6))
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
                            Text("/ " + mmss(np.duration)).font(.system(size: 13).monospacedDigit()).foregroundStyle(TXT.opacity(0.6))
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
                    // ذراع الإبرة
                    VStack(spacing: 0) {
                        Circle().fill(Color(white: 0.75)).frame(width: 12, height: 12)
                        Capsule().fill(Color(white: 0.7)).frame(width: 3, height: 70)
                            .rotationEffect(.degrees(np.playing ? 18 : 6), anchor: .top)
                    }
                    .padding(.top, 10).padding(.trailing, 14)
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
                    Image(systemName: MediaArt(source: np.source).icon).font(.system(size: 14)).foregroundStyle(TXT.opacity(0.6))
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
                    Image(systemName: MediaArt(source: np.source).icon).font(.system(size: 30)).foregroundStyle(TXT.opacity(0.7))
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
                            Text("•").foregroundStyle(TXT.opacity(0.5))
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
