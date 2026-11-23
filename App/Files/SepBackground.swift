import Foundation
import UIKit
import BackgroundTasks

/// هل التطبيق في الخلفية؟ iOS يمنع كرت الشاشة في الخلفية على الآيفون، فيُستخدم المعالج مباشرة
/// (بلا محاولة فاشلة على كرت الشاشة مع كل جزء)، ويرجع كرت الشاشة فور العودة للتطبيق
enum AppActivity {
    nonisolated(unsafe) static var inBackground = false
    @MainActor private static var started = false

    @MainActor static func start() {
        guard !started else { return }
        started = true
        inBackground = UIApplication.shared.applicationState == .background
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in inBackground = true }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in inBackground = false }
    }
}

/// إكمال الفصل بعد الخروج من التطبيق (iOS 26): مهمة يبدأها المستخدم ويعرض النظام تقدّمها.
/// إن لم يسمح النظام (إصدار أقدم، أو معرّف لا يطابق بعد إعادة التوقيع) يتوقف الفصل مؤقتًا ويكمل عند العودة.
@MainActor
final class SepContinued {
    static let shared = SepContinued()
    private var registered = false
    private var current: AnyObject?
    private var last = 0.0

    /// المعرّف من Info.plist (يُكتب وقت البناء بمعرّف التطبيق)
    private var identifier: String? {
        (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])?
            .first { $0.hasSuffix(".separate") }
    }

    func begin(title: String, subtitle: String) {
        AppActivity.start()
        last = 0
        #if compiler(>=6.2)
        guard #available(iOS 26.0, *), let id = identifier else { return }
        if !registered {
            registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { task in
                MainActor.assumeIsolated { SepContinued.shared.attach(task) }
            }
            guard registered else { return }
        }
        let req = BGContinuedProcessingTaskRequest(identifier: id, title: title, subtitle: subtitle)
        req.strategy = .fail
        do { try BGTaskScheduler.shared.submit(req) } catch { NSLog("sep continued: %@", String(describing: error)) }
        #endif
    }

    func update(_ v: Double) {
        last = v
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let t = current as? BGContinuedProcessingTask {
            t.progress.completedUnitCount = Int64(max(0, min(1, v)) * 1000)
        }
        #endif
    }

    func end(success: Bool) {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let t = current as? BGContinuedProcessingTask {
            t.progress.completedUnitCount = 1000
            t.setTaskCompleted(success: success)
        }
        #endif
        current = nil
    }

    private func attach(_ task: BGTask) {
        #if compiler(>=6.2)
        guard #available(iOS 26.0, *), let t = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
        t.progress.totalUnitCount = 1000
        t.progress.completedUnitCount = Int64(last * 1000)
        // انتهاء المهلة: لا يُلغى الفصل؛ يتوقف التطبيق مؤقتًا ويكمل الفصل عند العودة من نفس المكان
        t.expirationHandler = {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let c = SepContinued.shared.current as? BGContinuedProcessingTask, c === t { SepContinued.shared.current = nil }
                }
                t.setTaskCompleted(success: false)
            }
        }
        current = t
        #else
        task.setTaskCompleted(success: false)
        #endif
    }
}
