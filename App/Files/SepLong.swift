import Foundation
import AVFoundation
import Accelerate
import CryptoKit

/// فصل المقاطع الطويلة (حتى ٤ ساعات) بذاكرة ثابتة:
/// - المقطع يُقرأ تتابعيًا ويُفصل على كتل ٥ دقائق، لكل كتلة ٨ ثوانٍ سياق من كل جهة (لا أثر لحواف الكتل)،
///   والانتقال بين كتلتين بتلاشٍ متقاطع نصف ثانية داخل السياق.
/// - الناتج يُكتب أولًا بأول في ملف مؤقت خام (Float32 بلا ضغط: لا فقد في الجودة)، ثم يُرمَّز مرة واحدة في النهاية.
/// - بعد كل كتلة يُحفظ التقدّم: إن انقطع الفصل (إغلاق، نفاد بطارية…) يكمل من آخر كتلة.
/// - عدد العيّنات الناتجة = عدد عيّنات الأصل بالضبط، وتُحفظ بداية الصوت في الملف الأصلي لمزامنة الفيديو.
enum SepLong {
    static let rate = 44_100.0
    static var block = 5 * 60 * 44_100          // يُصغَّر في الفحص الآلي فقط
    static let ctx = 8 * 44_100
    static let fade = 22_050
    static let maxSeconds = 4.0 * 3600
    /// للفحص الآلي فقط: نسخة من الناتج الخام قبل الترميز (للمقارنة عيّنة بعيّنة)
    static var testRawCopy: URL?

    /// فصل نافذة صوت في الذاكرة: يرجع الصوت البشري بنفس الطول
    typealias Separate = (_ l: [Float], _ r: [Float], _ progress: @escaping (Double) -> Void) async throws -> ([Float], [Float])

    struct Result {
        let main: URL
        let other: URL?
        /// بداية الصوت في الملف الأصلي بالثواني (قد لا تكون صفرًا في بعض الفيديوهات)
        let audioStart: Double
        /// أُكمل من فصل سابق منقطع
        let resumed: Bool
    }

    struct State: Codable {
        var keep: String
        var engine: String
        var alsoOther: Bool
        var block: Int
        var nextBlock: Int
        var written: Int
        var audioStart: Double
        var estTotal: Int
    }

    // MARK: حفظ التقدّم

    static var jobsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sepjobs", isDirectory: true)
    }

    /// مفتاح الفصل: الملف (مساره داخل المستندات، حجمه، تاريخه) + الجزء المطلوب + النموذج
    static func key(_ src: URL, keep: Separator.Keep, engine: String) -> String {
        let rv = try? src.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        var path = src.standardizedFileURL.path
        if let r = path.range(of: "/Documents/") { path = String(path[r.upperBound...]) }
        let id = "\(path)|\(rv?.fileSize ?? 0)|\(Int(rv?.contentModificationDate?.timeIntervalSince1970 ?? 0))|\(keep == .vocals ? "v" : "m")|\(engine)"
        return SHA256.hash(data: Data(id.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func dir(_ key: String) -> URL { jobsDir.appendingPathComponent(key, isDirectory: true) }

    private static func loadState(_ key: String) -> State? {
        guard let d = try? Data(contentsOf: dir(key).appendingPathComponent("state.json")) else { return nil }
        return try? JSONDecoder().decode(State.self, from: d)
    }

    private static func save(_ st: State, _ key: String) throws {
        let d = try JSONEncoder().encode(st)
        try d.write(to: dir(key).appendingPathComponent("state.json"), options: .atomic)
    }

    /// نسبة فصل سابق منقطع لهذا الملف (nil = لا يوجد)
    static func pending(_ src: URL, keep: Separator.Keep, engine: String) -> Double? {
        guard let st = loadState(key(src, keep: keep, engine: engine)), st.written > 0, st.estTotal > 0 else { return nil }
        return min(0.99, Double(st.written) / Double(st.estTotal))
    }

    static func discard(_ src: URL, keep: Separator.Keep, engine: String) {
        try? FileManager.default.removeItem(at: dir(key(src, keep: keep, engine: engine)))
    }

    // MARK: القراءة التتابعية

    /// يقرأ الصوت ستيريو ٤٤١٠٠ هرتز دفعة بعد دفعة (لا يحمّل المقطع كاملًا)
    final class Reader {
        private let reader: AVAssetReader
        private let out: AVAssetReaderTrackOutput
        private(set) var firstPTS: Double?
        private(set) var eof = false
        /// نافذة متحركة من الصوت المقروء: l[0] هو العيّنة رقم base
        private(set) var base = 0
        private(set) var l: [Float] = [], r: [Float] = []
        var end: Int { base + l.count }
        private var data: [Float] = [], bl: [Float] = [], br: [Float] = []

        init(_ url: URL) async throws {
            let a = AVURLAsset(url: url)
            guard let t = try await a.loadTracks(withMediaType: .audio).first else { throw ToolError.failed(L("لا يحتوي الملف على صوت.")) }
            reader = try AVAssetReader(asset: a)
            out = AVAssetReaderTrackOutput(track: t, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
            ])
            out.alwaysCopiesSampleData = false
            reader.add(out)
            guard reader.startReading() else { throw ToolError.failed(L("تعذّرت قراءة الصوت.")) }
        }

        deinit { reader.cancelReading() }

        /// يقرأ حتى تصل النافذة إلى العيّنة target أو ينتهي الملف، ويحذف أولًا بأول ما قبل keepFrom
        /// (الإكمال بعد انقطاع يمر على بداية المقطع دون أن يحمّلها كلها في الذاكرة)
        func fill(to target: Int, keepFrom: Int) throws {
            while end < target && !eof {
                try Task.checkCancellation()
                if l.count > 4_000_000 { drop(before: keepFrom) }
                guard let sb = out.copyNextSampleBuffer() else {
                    eof = true
                    if reader.status == .failed { throw ToolError.failed(L("تعذّرت قراءة الصوت.")) }
                    break
                }
                if firstPTS == nil {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sb)
                    firstPTS = pts.isNumeric ? max(0, pts.seconds) : 0
                }
                guard let bb = CMSampleBufferGetDataBuffer(sb) else { continue }
                let len = CMBlockBufferGetDataLength(bb) / 8 * 8
                guard len > 0 else { continue }
                let frames = len / 8
                if data.count < frames * 2 { data = [Float](repeating: 0, count: frames * 2); bl = [Float](repeating: 0, count: frames); br = bl }
                data.withUnsafeMutableBytes { if let p = $0.baseAddress { _ = CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: len, destination: p) } }
                data.withUnsafeBufferPointer { dp in
                    bl.withUnsafeMutableBufferPointer { lp in
                        br.withUnsafeMutableBufferPointer { rp in
                            var split = DSPSplitComplex(realp: lp.baseAddress!, imagp: rp.baseAddress!)
                            dp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: frames) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(frames)) }
                        }
                    }
                }
                l.append(contentsOf: bl[0..<frames]); r.append(contentsOf: br[0..<frames])
            }
        }

        /// يحذف ما قبل العيّنة idx (لم يعد مطلوبًا)
        func drop(before idx: Int) {
            let k = min(l.count, max(0, idx - base))
            guard k > 0 else { return }
            l.removeFirst(k); r.removeFirst(k); base += k
        }
    }

    // MARK: الفصل

    static func run(_ src: URL, keep: Separator.Keep, engineName: String, alsoOther: Bool = false,
                    separate: Separate, progress: @escaping (Double) -> Void) async throws -> Result {
        let fm = FileManager.default
        let k = key(src, keep: keep, engine: engineName)
        let jd = dir(k)
        let asset = AVURLAsset(url: src)
        let dur = (try? await asset.load(.duration).seconds) ?? 0
        guard dur.isFinite, dur > 0 else { throw ToolError.failed(L("هذا الملف لا يدعم هذه العملية.")) }
        guard dur <= maxSeconds + 1 else { throw ToolError.failed(LF("المقطع أطول من %@.", L("٤ ساعات"))) }
        let est = Int(dur * rate)
        guard est > 4096 else { throw ToolError.failed(L("المقطع قصير جدًا.")) }

        // استئناف فصل منقطع، أو بداية جديدة
        var st: State
        var resumed = false
        if let old = loadState(k), old.alsoOther == alsoOther, old.block == block,
           fm.fileExists(atPath: jd.appendingPathComponent("main.raw").path) {
            st = old; resumed = st.written > 0
        } else {
            try? fm.removeItem(at: jd)
            try fm.createDirectory(at: jd, withIntermediateDirectories: true)
            st = State(keep: keep == .vocals ? "vocals" : "music", engine: engineName, alsoOther: alsoOther, block: block,
                       nextBlock: 0, written: 0, audioStart: 0, estTotal: est)
        }
        var noBackup = URLResourceValues(); noBackup.isExcludedFromBackup = true
        var jdv = jobsDir; try? fm.createDirectory(at: jdv, withIntermediateDirectories: true); try? jdv.setResourceValues(noBackup)

        // المساحة: الملف الخام (٨ بايت لكل عيّنة ستيريو) + الناتج المضغوط
        let rawBytes = Int64(est - st.written) * 8 * (alsoOther ? 2 : 1)
        let need = rawBytes + Int64(dur * 64_000) + 200_000_000
        if let free = (try? jobsDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage,
           free < need {
            throw ToolError.failed(LF("المساحة المتاحة لا تكفي للفصل: يحتاج تقريبًا %@، والمتاح %@.", sizeText(need), sizeText(free)))
        }

        // ملفات الناتج الخام: تُقص إلى آخر ما حُفظ (قد يكون الانقطاع في منتصف كتابة)
        let mainRaw = jd.appendingPathComponent("main.raw"), otherRaw = jd.appendingPathComponent("other.raw")
        func openRaw(_ u: URL) throws -> FileHandle {
            if !fm.fileExists(atPath: u.path) { fm.createFile(atPath: u.path, contents: nil) }
            let h = try FileHandle(forWritingTo: u)
            try h.truncate(atOffset: UInt64(st.written) * 8)
            try h.seekToEnd()
            return h
        }
        let hMain = try openRaw(mainRaw)
        let hOther = alsoOther ? try openRaw(otherRaw) : nil
        defer { try? hMain.close(); try? hOther?.close() }
        // ذيل الكتلة السابقة باسم رقم الكتلة التالية (يطابق حالة الحفظ حتى لو انقطع بين الكتابتين)
        func tailURL(_ next: Int) -> URL { jd.appendingPathComponent("tail-\(next).bin") }
        var tail: ([Float], [Float])? = nil
        if resumed, let d = try? Data(contentsOf: tailURL(st.nextBlock)), d.count == fade * 8 {
            let f = d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            tail = (Array(f[0..<fade]), Array(f[fade..<(2 * fade)]))
        }

        let reader = try await Reader(src)
        let blocksEst = max(1, Int((Double(est) / Double(block)).rounded(.up)))
        var b = st.nextBlock
        while true {
            try Task.checkCancellation()
            let cs = b * block
            let ws = max(0, cs - ctx)
            try reader.fill(to: cs + block + ctx, keepFrom: ws)
            reader.drop(before: ws)
            if b == 0, let p = reader.firstPTS { st.audioStart = p }
            let ce = min(cs + block, reader.end)
            if ce <= cs { break }
            let we = min(cs + block + ctx, reader.end)
            let wl = Array(reader.l[(ws - reader.base)..<(we - reader.base)])
            let wr = Array(reader.r[(ws - reader.base)..<(we - reader.base)])
            let total = Double(max(blocksEst, b + 1))
            let bi = b
            let (vl, vr) = try await separate(wl, wr, { p in progress((Double(bi) + p) / total) })
            try Task.checkCancellation()
            guard vl.count == wl.count, vr.count == wr.count else { throw ToolError.failed(L("تعذّرت المعالجة.")) }

            // وسط الكتلة، مع تلاشٍ متقاطع مع ذيل الكتلة السابقة
            let off = cs - ws, len = ce - cs
            var cl = Array(vl[off..<(off + len)]), cr = Array(vr[off..<(off + len)])
            if let t = tail {
                let m = min(fade, len)
                for i in 0..<m {
                    let w = Float(i + 1) / Float(fade + 1)
                    cl[i] = t.0[i] * (1 - w) + cl[i] * w
                    cr[i] = t.1[i] * (1 - w) + cr[i] * w
                }
            }
            // ذيل هذه الكتلة (تقدير ما بعدها) للتلاشي مع التالية
            if off + len + fade <= vl.count {
                tail = (Array(vl[(off + len)..<(off + len + fade)]), Array(vr[(off + len)..<(off + len + fade)]))
            } else { tail = nil }

            // الكتابة: الصوت البشري، أو الموسيقى = الأصل − الصوت البشري
            func write(_ h: FileHandle, vocals: Bool) throws {
                var inter = [Float](repeating: 0, count: 2 * len)
                for i in 0..<len {
                    let ol = wl[off + i], orr = wr[off + i]
                    inter[2 * i] = vocals ? cl[i] : ol - cl[i]
                    inter[2 * i + 1] = vocals ? cr[i] : orr - cr[i]
                }
                try h.write(contentsOf: inter.withUnsafeBufferPointer { Data(buffer: $0) })
            }
            try write(hMain, vocals: keep == .vocals)
            if let hOther { try write(hOther, vocals: keep != .vocals) }
            try hMain.synchronize(); try hOther?.synchronize()

            // حفظ التقدّم
            st.written += len
            st.nextBlock = b + 1
            if let t = tail {
                var d = Data(capacity: fade * 8)
                t.0.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
                t.1.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
                try d.write(to: tailURL(b + 1), options: .atomic)
            }
            try save(st, k)
            try? fm.removeItem(at: tailURL(b))
            b += 1
            if reader.eof && ce >= reader.end { break }
        }
        guard st.written > 0 else { throw ToolError.failed(L("تعذّرت قراءة الصوت.")) }

        // الترميز النهائي (مرة واحدة)
        progress(0.995)
        let vName = L("بدون موسيقى"), mName = L("بدون صوت بشري")
        let mainOut = MediaTools.output(for: src, suffix: keep == .vocals ? vName : mName, ext: "m4a")
        try encode(mainRaw, to: mainOut)
        var other: URL?
        if alsoOther {
            let o = MediaTools.output(for: src, suffix: keep == .vocals ? mName : vName, ext: "m4a")
            try encode(otherRaw, to: o)
            other = o
        }
        if let t = testRawCopy { try? fm.removeItem(at: t); try? fm.copyItem(at: mainRaw, to: t) }
        try? fm.removeItem(at: jd)
        progress(1)
        return Result(main: mainOut, other: other, audioStart: st.audioStart, resumed: resumed)
    }

    /// الخام (Float32 ستيريو متداخل) ← M4A
    static func encode(_ raw: URL, to out: URL) throws {
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { throw ToolError.failed(L("تعذّر الحفظ.")) }
        let f = try AVAudioFile(forWriting: out, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                                                             AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000])
        let h = try FileHandle(forReadingFrom: raw)
        defer { try? h.close() }
        let frames = 44_100
        while let d = try h.read(upToCount: frames * 8), !d.isEmpty {
            try Task.checkCancellation()
            let c = d.count / 8
            guard c > 0, let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(c)), let ch = b.floatChannelData else { break }
            b.frameLength = AVAudioFrameCount(c)
            d.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: Float.self)
                for i in 0..<c { ch[0][i] = max(-1, min(1, p[2 * i])); ch[1][i] = max(-1, min(1, p[2 * i + 1])) }
            }
            try f.write(from: b)
        }
    }
}
