import SwiftUI

// MARK: - مشغّل عائم واحد فوق شريط التبويب (في كل التطبيق) — مثل Apple Music
// يحل محل المشغّلات المتفرقة (بطاقة القرآن، المشغّل المصغّر في الملفات)؛ الضغط عليه يفتح المشغّل الكامل

@MainActor
final class MiniPlayerState: ObservableObject {
    static let shared = MiniPlayerState()
    /// ارتفاع إضافي أسفل الصفحات حين يظهر المشغّل
    @Published var visible = false
}

struct GlobalMiniPlayer: View {
    @ObservedObject private var p = AudioPlayer.shared
    @State private var showFull = false

    private var visible: Bool { p.sessionActive && p.state.source != .music || (p.state.source == .music && p.state.playing) }

    var body: some View {
        Group {
            if visible {
                let s = p.state
                VStack(spacing: 6) {
                HStack(spacing: 12) {
                    Group {
                        if s.source == .radio, let st = p.station { StationArt(station: st, size: 44) }
                        else { MediaArt(source: s.source, corner: 10, label: s.title).frame(width: 44, height: 44) }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: p.streamTitle ?? s.title).font(Theme.title(15)).foregroundStyle(.white).lineLimit(1)
                        HStack(spacing: 5) {
                            if s.source == .radio { LiveBadge(on: s.playing) }
                            if p.loading { ProgressView().controlSize(.mini).tint(Theme.gold) }
                            Text(verbatim: p.streamTitle != nil ? s.title : s.subtitle).font(Theme.f(.caption)).foregroundStyle(Theme.sub).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        button(s.playing ? "pause.fill" : "play.fill", big: true) { p.toggle() }
                        button("forward.fill") { p.next() }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    button("xmark") { withAnimation(.snappy) { p.endSession() } }
                        .accessibilityLabel(L("إغلاق المشغّل"))
                }
                // شريط التقديم والتأخير للقرآن والملفات (البث المباشر ليس له مدة)
                if (s.source == .quran || s.source == .files) && s.duration > 0 {
                    MiniScrubber(duration: s.duration)
                }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .environment(\.colorScheme, .dark)
                .contentShape(Rectangle())
                .onTapGesture { showFull = true }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("globalMiniPlayer")
            }
        }
        .animation(.snappy, value: visible)
        .onChange(of: visible, initial: true) { _, v in MiniPlayerState.shared.visible = v }
        .sheet(isPresented: $showFull) { NowPlayingSheet() }
    }

    private func button(_ icon: String, big: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: big ? 18 : 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: big ? 40 : 34, height: big ? 40 : 34)
        }
        .buttonStyle(.plain)
    }
}

/// شريط تقديم وتأخير رفيع: يُسحب بالإصبع، ويتحرك مع التشغيل، والوقت المنقضي والمتبقي على طرفيه
struct MiniScrubber: View {
    @ObservedObject private var p = AudioPlayer.shared
    let duration: Double
    @State private var pos: Double = AudioPlayer.shared.position()
    @State private var dragging = false
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        let frac = CGFloat(min(1, max(0, pos / max(1, duration))))
        HStack(spacing: 8) {
            Text(verbatim: durationText(pos)).frame(minWidth: 34, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18)).frame(height: dragging ? 7 : 4)
                    Capsule().fill(Theme.gold).frame(width: max(4, g.size.width * frac), height: dragging ? 7 : 4)
                    Circle().fill(Color.white).frame(width: dragging ? 16 : 10, height: dragging ? 16 : 10)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .offset(x: g.size.width * frac - (dragging ? 8 : 5))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        pos = Double(min(1, max(0, v.location.x / max(1, g.size.width)))) * duration
                    }
                    .onEnded { _ in
                        p.seek(to: pos)
                        dragging = false
                    })
                .animation(.snappy(duration: 0.18), value: dragging)
            }
            .frame(height: 22)
            Text(verbatim: "-" + durationText(max(0, duration - pos))).frame(minWidth: 40, alignment: .trailing)
        }
        .font(Theme.font(11, .medium).monospacedDigit()).foregroundStyle(Theme.sub)
        .environment(\.layoutDirection, .leftToRight)
        .onReceive(tick) { _ in if !dragging { pos = p.position() } }
        .accessibilityElement()
        .accessibilityLabel(L("التقديم والتأخير"))
        .accessibilityValue(durationText(pos))
        .accessibilityAdjustableAction { d in p.seek(by: d == .increment ? 15 : -15); pos = p.position() }
    }
}

/// المشغّل الكامل: للملفات مشغّلها، وللإذاعة بطاقتها بكل أزرارها، وللقرآن غلاف السورة والتحكم
struct NowPlayingSheet: View {
    @ObservedObject private var p = AudioPlayer.shared
    @State private var saved = Stations.saved

    var body: some View {
        switch p.state.source {
        case .files: FilesFullPlayer()
        case .radio:
            ScrollView {
                VStack(spacing: 16) {
                    Capsule().fill(Color.white.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 10)
                    RadioPlayerCard(saved: $saved)
                }
                .padding(16)
            }
            .background(AppBackground())
            .presentationDetents([.medium, .large])
        default:
            QuranFullPlayer()
        }
    }
}

struct QuranFullPlayer: View {
    @ObservedObject private var p = AudioPlayer.shared
    @State private var pos: Double = 0
    @State private var scrubbing = false
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        let s = p.state
        VStack(spacing: 22) {
            Capsule().fill(Color.white.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 10)
            Spacer(minLength: 0)
            MediaArt(source: s.source, corner: 36, label: s.title)
                .frame(width: 260, height: 260)
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            VStack(spacing: 6) {
                Text(verbatim: s.title).font(Theme.title(26)).foregroundStyle(.white)
                Text(verbatim: s.subtitle).font(Theme.f(.subheadline)).foregroundStyle(Theme.sub)
                if s.source == .quran { Text(verbatim: Surahs.info(s.surah)).font(Theme.f(.caption)).foregroundStyle(Theme.sub) }
            }
            if s.duration > 0 {
                VStack(spacing: 4) {
                    Slider(value: Binding(get: { pos }, set: { pos = $0 }), in: 0...max(1, s.duration), onEditingChanged: { e in
                        scrubbing = e
                        if !e { p.seek(to: pos) }
                    })
                    .tint(Theme.gold)
                    HStack {
                        Text(verbatim: durationText(pos))
                        Spacer()
                        Text(verbatim: "-" + durationText(max(0, s.duration - pos)))
                    }
                    .font(Theme.font(12, .medium).monospacedDigit()).foregroundStyle(Theme.sub)
                }
                .environment(\.layoutDirection, .leftToRight)
                .padding(.horizontal, 24)
            }
            HStack(spacing: 34) {
                Button { p.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 26)) }
                Button { p.toggle() } label: {
                    Image(systemName: s.playing ? "pause.fill" : "play.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 74, height: 74).background(Circle().fill(Theme.gold))
                }
                Button { p.next() } label: { Image(systemName: "forward.fill").font(.system(size: 26)) }
            }
            .foregroundStyle(.white).buttonStyle(.plain)
            .environment(\.layoutDirection, .leftToRight)
            HStack(spacing: 14) {
                SleepMenu(label: true, round: false)
                AirPlayButton().frame(width: 40, height: 40)
            }
            Spacer(minLength: 0)
        }
        .background(AppBackground())
        .onReceive(tick) { _ in if !scrubbing { pos = p.position() } }
    }
}
