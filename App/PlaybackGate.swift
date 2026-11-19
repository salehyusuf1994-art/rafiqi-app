import AVKit
import UIKit

/// مشغّل واحد فقط يعمل في كل وقت: الصوت (قرآن/إذاعة/ملفات)، أو قناة تلفزيونية، أو فيديو من الملفات.
/// أي مشغّل يبدأ يوقف البقية، ومن ذلك ما يعمل في النافذة العائمة.
@MainActor
enum PlaybackGate {
    enum Owner { case audio, tv, video }
    /// آخر مشغّل بدأ (لتوجيه أزرار شاشة القفل والسماعات إليه)
    private(set) static var owner: Owner = .audio

    /// مشغّل «تجربة الرابط» في إضافة قناة: يتوقف إذا بدأ أي مشغّل آخر
    static weak var tester: AVPlayer?

    static func claim(_ o: Owner, tv: TVPlayback? = nil, video: VideoController? = nil, fromTester: Bool = false) {
        owner = o
        if !fromTester, let t = tester { t.pause() }
        if o != .audio {
            let a = AudioPlayer.shared
            if a.state.playing || a.loading { a.pause() }
        }
        // القناة الحالية (أو نافذتها العائمة): تتوقف مؤقتًا للصوت، وتُغلق إن بدأ فيديو أو قناة أخرى
        if let cur = TVPlayback.current, cur !== tv { cur.pause() }
        if o != .audio { TVPiP.end(except: tv) }
        VideoController.stopOthers(except: video, close: o != .audio)
    }

    /// الفيديو الذي تتجه إليه أزرار شاشة القفل الآن (إن كان هو آخر ما بدأ)
    static var activeVideo: VideoController? { owner == .video ? VideoController.active : nil }
}

/// مشغّل مقفل (قفل الأطفال) معروض الآن: لا تغلقه الروابط ولا الويدجت ولا الإشعارات ولا فتح ملف أو قناة أخرى
@MainActor
enum PlayerLockState {
    static var active = false
}

/// القناة التي تعمل في النافذة العائمة: نُبقي مشغّلها حيًّا بعد إغلاق شاشة البث
@MainActor
enum TVPiP {
    static var active = false
    /// المستخدم ضغط «الرجوع إلى ملء الشاشة» فأُعيد فتح الشاشة بالمشغّل نفسه
    static var restored = false
    static var vc: AVPlayerViewController?
    static var tv: TVPlayback?
    static var coordinator: AnyObject?

    /// يغلق النافذة العائمة ويوقف قناتها (عند بدء فيديو أو قناة أخرى)
    static func end(except keep: TVPlayback? = nil) {
        guard let t = tv, t !== keep else { return }
        vc?.player = nil
        t.stop()
        clear()
    }

    static func clear() {
        active = false; restored = false
        vc = nil; tv = nil; coordinator = nil
    }
}
