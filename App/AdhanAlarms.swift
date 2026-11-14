import Foundation
import SwiftUI
import AlarmKit

// MARK: - الأذان كاملًا: منبّهات النظام (AlarmKit — iOS 26.1 وما بعده)
// يعمل والجوال صامت أو مقفل، ويتكرر الأذان حتى يضغط المستخدم «إيقاف».

@available(iOS 26.0, *)
struct AdhanMetadata: AlarmMetadata {}

enum AdhanAlarms {
    private static let idsKey = "adhan_alarm_ids"

    /// متاح على هذا الجهاز؟
    static var supported: Bool {
        if #available(iOS 26.1, *) { return true }
        return false
    }

    /// يطلب إذن المنبّهات (مرة واحدة)
    static func requestAccess() async -> Bool {
        guard #available(iOS 26.1, *) else { return false }
        let state = try? await AlarmManager.shared.requestAuthorization()
        return state == .authorized
    }

    @MainActor private static var queue: Task<Bool, Never>?

    /// يلغي منبّهات الأذان السابقة ويجدول الجديدة — بالدور (لو طُلبت مرتين معًا ما تتكرر المنبّهات)
    @MainActor
    static func sync(_ items: [Notify.AlarmItem]) async -> Bool {
        let previous = queue
        let task = Task { @MainActor () -> Bool in
            _ = await previous?.value
            return await apply(items)
        }
        queue = task
        return await task.value
    }

    @MainActor
    private static func apply(_ items: [Notify.AlarmItem]) async -> Bool {
        guard #available(iOS 26.1, *) else { return false }
        let d = AppGroup.defaults
        for s in d.stringArray(forKey: idsKey) ?? [] {
            if let id = UUID(uuidString: s) { try? AlarmManager.shared.cancel(id: id) }
        }
        d.set([String](), forKey: idsKey)
        guard !items.isEmpty else { return true }
        let state = AlarmManager.shared.authorizationState
        guard state == .authorized else { return false }
        var ids: [String] = []
        var ok = true
        for it in items {
            let id = UUID()
            let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: it.title))
            let attrs = AlarmAttributes<AdhanMetadata>(presentation: AlarmPresentation(alert: alert),
                                                       metadata: AdhanMetadata(), tintColor: Theme.gold)
            let config = AlarmManager.AlarmConfiguration<AdhanMetadata>.alarm(
                schedule: .fixed(it.date), attributes: attrs, stopIntent: nil, secondaryIntent: nil,
                sound: .named(it.sound))
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
                ids.append(id.uuidString)
            } catch {
                ok = false
            }
        }
        d.set(ids, forKey: idsKey)
        return ok && !ids.isEmpty
    }
}
