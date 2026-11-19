import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

// MARK: - عدّاد الصلاة القادمة في الجزيرة الديناميكية وشاشة القفل (Live Activity)
// يبدأ من زر في مركز التحكم أو من الإشعارات/الرئيسية، ويتحدّث كلما فُتح التطبيق.
// (بدون خادم إشعارات لا يمكن تحديثه للصلاة التالية والتطبيق مغلق: عند دخول الوقت يعرض «حان وقت …»
//  بدل عدّاد واقف على الصفر، ويتجدد للصلاة التالية عند فتح التطبيق)

struct PrayerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var key: String
        var name: String
        var time: Date
        var prev: Date
        var place: String
    }
}

enum PrayerActivity {
    static var enabled: Bool {
        get { AppGroup.defaults.bool(forKey: "la_prayer") }
        set { AppGroup.defaults.set(newValue, forKey: "la_prayer") }
    }

    static func state(at now: Date = Date()) -> PrayerActivityAttributes.ContentState {
        let st = Prayer.prevNext(at: now)
        let name = Lang.isEN ? (Words.prEN[st.next.key.rawValue] ?? "") : (Words.pr[st.next.key.rawValue] ?? "")
        return .init(key: st.next.key.rawValue, name: name, time: st.next.time, prev: st.prev.time, place: Settings.placeName)
    }

    /// يبدأ العدّاد أو يحدّثه للوقت القادم
    @discardableResult
    static func start() async -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        let s = state()
        // يصير «قديمًا» لحظة دخول الوقت، فيعرض الشكلُ «حان وقت …» بدل ٠:٠٠
        let content = ActivityContent(state: s, staleDate: s.time)
        let running = Activity<PrayerActivityAttributes>.activities
        if let first = running.first {
            await first.update(content)
            for extra in running.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            return true
        }
        do {
            _ = try Activity.request(attributes: PrayerActivityAttributes(), content: content, pushType: nil)
            return true
        } catch {
            return false
        }
    }

    static func stop() async {
        for a in Activity<PrayerActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }

    /// عند فتح التطبيق: نحدّث العدّاد للوقت القادم إن كان مفعّلًا
    static func refreshIfEnabled() async {
        guard enabled else { return }
        await start()
    }
}

/// زر «عدّاد الصلاة» في مركز التحكم وشاشة القفل (يعمل والتطبيق مغلق)
struct StartPrayerActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "عدّاد الصلاة القادمة"
    static let description = IntentDescription("يعرض العدّاد التنازلي للصلاة القادمة في الجزيرة الديناميكية وشاشة القفل")
    init() {}
    func perform() async throws -> some IntentResult {
        PrayerActivity.enabled = true
        await PrayerActivity.start()
        return .result()
    }
}

// MARK: - الشكل

struct PrayerActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerActivityAttributes.self) { ctx in
            PrayerActivityLockView(s: ctx.state, stale: ctx.isStale)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "moon.stars.fill").font(.title2).foregroundStyle(GOLD_LA)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if ctx.isStale {
                        Text(Lang.isEN ? "Now" : "حان الوقت").font(.system(size: 18, weight: .bold)).foregroundStyle(GOLD_LA)
                    } else {
                        Text(timerInterval: Date()...max(Date(), s.time), countsDown: true)
                            .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(GOLD_LA)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(verbatim: s.name).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                        Text(s.time, style: .time).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: s.prev...max(s.prev.addingTimeInterval(1), s.time), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(GOLD_LA)
                        .padding(.horizontal, 8)
                }
            } compactLeading: {
                Text(verbatim: s.name).font(.system(size: 13, weight: .bold)).foregroundStyle(GOLD_LA)
            } compactTrailing: {
                if ctx.isStale {
                    Image(systemName: "bell.fill").foregroundStyle(.white)
                } else {
                    Text(timerInterval: Date()...max(Date(), s.time), countsDown: true)
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(maxWidth: 54)
                }
            } minimal: {
                Image(systemName: "moon.stars.fill").foregroundStyle(GOLD_LA)
            }
            .keylineTint(GOLD_LA)
        }
    }
}

let GOLD_LA = Color(red: 0.89, green: 0.76, blue: 0.50)

struct PrayerActivityLockView: View {
    let s: PrayerActivityAttributes.ContentState
    var stale = false
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stale ? (Lang.isEN ? "It's time" : "حان الوقت") : (Lang.isEN ? "Next" : "الوقت القادم"))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                Text(verbatim: s.name).font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                HStack(spacing: 6) {
                    Text(s.time, style: .time)
                    if !s.place.isEmpty { Text(verbatim: "· " + s.place).lineLimit(1) }
                }
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                if stale {
                    // دخل الوقت: لا عدّاد واقف على الصفر
                    Text(Lang.isEN ? "Open Rafiqi to refresh" : "افتح رفيقي للتحديث")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(GOLD_LA)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text(timerInterval: Date()...max(Date(), s.time), countsDown: true)
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(GOLD_LA)
                        .multilineTextAlignment(.trailing)
                }
                ProgressView(timerInterval: s.prev...max(s.prev.addingTimeInterval(1), s.time), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(GOLD_LA)
                    .frame(width: 130)
            }
        }
        .padding(16)
        .environment(\.layoutDirection, Lang.dir)
    }
}

// MARK: - أزرار مركز التحكم (iOS 18)

@available(iOS 18.0, *)
struct RadioControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "rafiqi.control.radio") {
            ControlWidgetButton(action: MediaControlIntent("toggle", source: "radio")) {
                Label("الإذاعة", systemImage: "dot.radiowaves.left.and.right")
            }
        }
        .displayName("تشغيل/إيقاف الإذاعة")
        .description("آخر إذاعة استمعت لها في رفيقي")
    }
}

@available(iOS 18.0, *)
struct QuranControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "rafiqi.control.quran") {
            ControlWidgetButton(action: MediaControlIntent("toggle", source: "quran")) {
                Label("القرآن", systemImage: "book.closed.fill")
            }
        }
        .displayName("تشغيل/إيقاف التلاوة")
        .description("آخر سورة استمعت لها في رفيقي")
    }
}

@available(iOS 18.0, *)
struct SleepControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "rafiqi.control.sleep") {
            ControlWidgetButton(action: MediaControlIntent("sleep30")) {
                Label("مؤقّت النوم", systemImage: "moon.zzz.fill")
            }
        }
        .displayName("مؤقّت النوم ٣٠ دقيقة")
        .description("يوقف ما يعمل في رفيقي بعد نصف ساعة")
    }
}

@available(iOS 18.0, *)
struct PrayerCountdownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "rafiqi.control.prayer") {
            ControlWidgetButton(action: StartPrayerActivityIntent()) {
                Label("عدّاد الصلاة", systemImage: "timer")
            }
        }
        .displayName("عدّاد الصلاة القادمة")
        .description("في الجزيرة الديناميكية وشاشة القفل")
    }
}

@available(iOS 18.0, *)
struct ScannerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "rafiqi.control.scanner") {
            ControlWidgetButton(action: OpenRafiqiIntent(target: "scanner")) {
                Label("الماسح الضوئي", systemImage: "doc.viewfinder")
            }
        }
        .displayName("الماسح الضوئي")
        .description("يفتح ماسح المستندات في رفيقي")
    }
}

@available(iOS 18.0, *)
struct QiblaControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "rafiqi.control.qibla") {
            ControlWidgetButton(action: OpenRafiqiIntent(target: "qibla")) {
                Label("القبلة", systemImage: "location.north.line.fill")
            }
        }
        .displayName("القبلة")
        .description("يفتح بوصلة القبلة في رفيقي")
    }
}

/// يفتح صفحة في التطبيق (الماسح أو القبلة)
struct OpenRafiqiIntent: AppIntent {
    static let title: LocalizedStringResource = "فتح رفيقي"
    static let isDiscoverable = false
    static let openAppWhenRun = true
    @Parameter(title: "الصفحة") var target: String
    init() {}
    init(target: String) { self.target = target }
    func perform() async throws -> some IntentResult {
        AppGroup.defaults.set(target, forKey: "open_target")
        AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: "open_target_at")
        return .result()
    }
}
