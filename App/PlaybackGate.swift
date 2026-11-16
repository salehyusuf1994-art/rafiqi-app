import AVKit
import UIKit

/// مشغّل واحد فقط يعمل في كل وقت: الصوت (قرآن/إذاعة/ملفات)، أو قناة تلفزيونية، أو فيديو من الملفات.
/// أي مشغّل يبدأ يوقف البقية، ومن ذلك ما يعمل في النافذة العائمة.
@MainActor
enum PlaybackGate {
    enum Owner { case audio, tv, video }
    /// آخر مشغّل بدأ (لتوجيه أزرار شاشة القفل والسماعات إليه)
    private(set) static var owner: Owner = .audio

    static func claim(_ o: Owner, tv: TVPlayback? = nil, video: VideoController? = nil) {
        NSLog("RFDBG gate claim %@", String(describing: o))
        owner = o
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
        NSLog("RFDBG tv pip end")
        vc?.player = nil
        t.stop()
        clear()
    }

    static func clear() {
        active = false; restored = false
        vc = nil; tv = nil; coordinator = nil
    }
}
