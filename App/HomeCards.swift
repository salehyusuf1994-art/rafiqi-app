import SwiftUI

// MARK: - بطاقات الرئيسية: ذكر الوقت، والمناسبة القادمة

/// ذكر يناسب الوقت (الصباح بعد الفجر، المساء بعد العصر) مع عدّاد تسبيح بالضغط،
/// وزر لسماع إذاعة أذكار الصباح/المساء
struct DhikrCard: View {
    let date: Date
    var openAudio: () -> Void = {}
    @State private var index = 0
    @State private var count = 0

    struct Dhikr { let text: String; let times: Int; let source: String }

    /// أذكار ثابتة صحيحة مشهورة
    static let morning: [Dhikr] = [
        Dhikr(text: "أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللهُ وَحْدَهُ لَا شَرِيكَ لَهُ", times: 1, source: "رواه مسلم"),
        Dhikr(text: "بِسْمِ اللهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ وَهُوَ السَّمِيعُ الْعَلِيمُ", times: 3, source: "رواه أبو داود والترمذي"),
        Dhikr(text: "سُبْحَانَ اللهِ وَبِحَمْدِهِ", times: 100, source: "رواه مسلم"),
    ]
    static let evening: [Dhikr] = [
        Dhikr(text: "أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللهُ وَحْدَهُ لَا شَرِيكَ لَهُ", times: 1, source: "رواه مسلم"),
        Dhikr(text: "بِسْمِ اللهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ وَهُوَ السَّمِيعُ الْعَلِيمُ", times: 3, source: "رواه أبو داود والترمذي"),
        Dhikr(text: "سُبْحَانَ اللهِ وَبِحَمْدِهِ", times: 100, source: "رواه مسلم"),
    ]
    static let general: [Dhikr] = [
        Dhikr(text: "لَا إِلَهَ إِلَّا اللهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ، وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ", times: 10, source: "متفق عليه"),
        Dhikr(text: "أَسْتَغْفِرُ اللهَ وَأَتُوبُ إِلَيْهِ", times: 100, source: "رواه البخاري ومسلم"),
        Dhikr(text: "سُبْحَانَ اللهِ، وَالْحَمْدُ لِلَّهِ، وَلَا إِلَهَ إِلَّا اللهُ، وَاللهُ أَكْبَرُ", times: 33, source: "رواه مسلم"),
        Dhikr(text: "اللَّهُمَّ صَلِّ وَسَلِّمْ عَلَى نَبِيِّنَا مُحَمَّدٍ", times: 10, source: ""),
    ]

    /// ٠ صباح، ١ مساء، ٢ عام
    private var period: Int {
        let t = Prayer.times(for: date)   // الفجر، الشروق، الظهر، العصر، المغرب، العشاء
        if date >= t[0] && date < t[2] { return 0 }
        if date >= t[3] && date < t[5] { return 1 }
        return 2
    }
    private var list: [Dhikr] { [Self.morning, Self.evening, Self.general][period] }
    private var dhikr: Dhikr { list[index % list.count] }

    var body: some View {
        let d = dhikr
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Badge(name: period == 0 ? "sun.horizon.fill" : (period == 1 ? "moon.haze.fill" : "sparkles"), size: 36)
                Text(L(["أذكار الصباح", "أذكار المساء", "ذكر"][period])).font(Theme.title(18)).foregroundStyle(.white)
                Spacer(minLength: 0)
                if period < 2 {
                    Button {
                        let url = period == 0 ? "https://backup.qurango.net/radio/athkar_sabah" : "https://backup.qurango.net/radio/athkar_masa"
                        AudioPlayer.shared.playStation(Station(name: L(period == 0 ? "أذكار الصباح" : "أذكار المساء"), url: url))
                    } label: {
                        Label("استمع", systemImage: "headphones").font(Theme.f(.footnote, .bold)).foregroundStyle(Theme.gold)
                            .padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(Theme.cardHi))
                    }
                    .buttonStyle(.plain)
                }
                Button { withAnimation(.snappy) { index += 1; count = 0 } } label: {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(Circle().fill(Theme.cardHi))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("ذكر آخر"))
            }
            Text(verbatim: d.text).font(.custom("Amiri-Bold", size: 21)).foregroundStyle(.white)
                .multilineTextAlignment(.leading).lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .id(d.text)
            HStack {
                if !d.source.isEmpty { Text(verbatim: d.source).font(Theme.f(.caption)).foregroundStyle(Theme.sub) }
                Spacer()
                // عدّاد: اضغط للعدّ، ومطوّلًا للتصفير
                Button {
                    UIImpactFeedbackGenerator(style: count + 1 >= d.times ? .heavy : .light).impactOccurred()
                    withAnimation(.snappy) { count = count + 1 >= d.times ? d.times : count + 1 }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: count >= d.times ? "checkmark.circle.fill" : "hand.tap.fill")
                        Text(verbatim: ar(count) + " / " + ar(d.times)).monospacedDigit()
                    }
                    .font(Theme.f(.subheadline, .bold))
                    .foregroundStyle(count >= d.times ? .black : .white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(count >= d.times ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(Theme.cardHi)))
                }
                .buttonStyle(PressStyle())
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in withAnimation { count = 0 } })
                .accessibilityIdentifier("dhikrCounter")
            }
        }
        .glassCard(padding: 16)
        .onChange(of: period) { _, _ in index = 0; count = 0 }
    }
}

/// أقرب مناسبة قادمة (رمضان، العيدان، عرفة، عاشوراء، رأس السنة، اليوم الوطني…)
struct OccasionCard: View {
    let date: Date
    let open: () -> Void

    private static var cache: (day: Date, item: (Date, String)?)?

    static func next(from now: Date) -> (Date, String)? {
        let g = Cal.gregCal
        let today = g.startOfDay(for: now)
        if let c = cache, c.day == today { return c.item }
        var found: (Date, String)?
        for k in 0..<400 {
            guard let d = g.date(byAdding: .day, value: k, to: today) else { break }
            if let o = UQ.occasion(d), o.1 { found = (d, o.0); break }
        }
        cache = (today, found)
        return found
    }

    var body: some View {
        if let next = Self.next(from: date) {
            let d = next.0, name = next.1
            let g = Cal.gregCal
            let days = g.dateComponents([.day], from: g.startOfDay(for: date), to: d).day ?? 0
            let h = UQ.h(d)
            Button(action: open) {
                HStack(spacing: 12) {
                    Badge(name: "calendar.badge.clock", size: 40, active: days == 0)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L(days == 0 ? "اليوم" : "المناسبة القادمة")).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                        Text(L(name)).font(Theme.title(18)).foregroundStyle(.white)
                        Text(verbatim: "\(ar(h.day ?? 1)) \(UQ.monthName(h.month ?? 1, hijri: true)) · \(DateLine.greg(d))")
                            .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                    }
                    Spacer(minLength: 0)
                    if days == 1 || days == 2 {
                        Text(L(days == 1 ? "غدًا" : "بعد يومين")).font(Theme.title(16)).foregroundStyle(Theme.gold)
                    } else if days > 2 {
                        VStack(spacing: 0) {
                            Digits(text: ar(days), size: 30, color: Theme.gold, bold: true)
                            Text(L(days <= 10 ? "أيام" : "يومًا")).font(Theme.f(.caption2)).foregroundStyle(Theme.sub)
                        }
                    }
                }
                .glassCard(padding: 14)
            }
            .buttonStyle(PressStyle())
        }
    }
}
