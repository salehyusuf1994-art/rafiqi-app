import XCTest
import AVFoundation
@testable import Hilal

/// الفصل الطويل على دفعات: الطول بالعيّنة، المزامنة مع الصورة، والإكمال بعد الانقطاع.
/// (فاصل «مطابق» يرجع الصوت كما هو: يختبر القراءة والتقطيع والتلاشي والكتابة والمزامنة، لا النموذج نفسه)
final class SepLongTests: XCTestCase {
    private var dir: URL!
    private let rate = 44_100.0

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("seplong-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: SepLong.jobsDir)
        SepLong.block = 5 * 60 * 44_100
        SepLong.testRawCopy = nil
    }

    private let identity: SepLong.Separate = { l, r, p in p(1); return (l, r) }

    /// صوت ستيريو بنغمات قصيرة (١ كيلوهرتز، ٥٠ ملّي ثانية) عند الأزمنة المعطاة، والباقي ضجيج خفيف مختلف بين القناتين
    private func makeAudio(_ url: URL, seconds: Double, beeps: [Double]) throws {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let f = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                                                             AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000])
        let total = Int(seconds * rate), step = 441_000
        var seed: UInt32 = 3
        var pos = 0
        let beepIdx = beeps.map { Int($0 * rate) }
        while pos < total {
            let c = min(step, total - pos)
            let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(c))!
            b.frameLength = AVAudioFrameCount(c)
            let L = b.floatChannelData![0], R = b.floatChannelData![1]
            for i in 0..<c {
                seed = seed &* 1664525 &+ 1013904223
                let nz = Float(Int32(bitPattern: seed)) / Float(Int32.max) * 0.002
                L[i] = nz; R[i] = -nz
            }
            for bi in beepIdx where bi + 2205 > pos && bi < pos + c {
                for k in max(0, bi - pos)..<min(c, bi + 2205 - pos) {
                    let v = 0.5 * Float(sin(2 * Double.pi * 1000 * Double(pos + k - bi) / rate))
                    L[k] = v; R[k] = v
                }
            }
            try f.write(from: b)
            pos += c
        }
    }

    private func rawFloats(_ u: URL) throws -> [Float] {
        let d = try Data(contentsOf: u)
        return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// كتل متعددة: الناتج الخام = الأصل عيّنة بعيّنة (التلاشي بين الكتل لا يغيّر شيئًا)، والطول مطابق
    func testBlocksReproduceInputExactly() async throws {
        SepLong.block = 20 * 44_100
        let src = dir.appendingPathComponent("a.m4a")
        try makeAudio(src, seconds: 75, beeps: [3, 40, 70])
        let rawOut = dir.appendingPathComponent("out.raw")
        SepLong.testRawCopy = rawOut
        let res = try await SepLong.run(src, keep: .vocals, engineName: "test", separate: identity, progress: { _ in })
        let (l, r) = try await Separator.readPCM(src)
        let raw = try rawFloats(rawOut)
        XCTAssertEqual(raw.count, l.count * 2, "sample count")
        var err: Float = 0
        for i in 0..<l.count { err = max(err, abs(raw[2 * i] - l[i]), abs(raw[2 * i + 1] - r[i])) }
        XCTAssertLessThan(err, 1e-5)
        // الملف المضغوط النهائي بنفس الطول
        let (ol, _) = try await Separator.readPCM(res.main)
        XCTAssertEqual(ol.count, l.count, "encoded length")
        // «إزالة الصوت البشري» مع فاصل مطابق = صمت
        SepLong.testRawCopy = rawOut
        _ = try await SepLong.run(src, keep: .music, engineName: "test", separate: identity, progress: { _ in })
        let m = try rawFloats(rawOut)
        XCTAssertLessThan(m.map(abs).max() ?? 1, 1e-5)
    }

    /// انقطاع في منتصف الفصل ثم إكمال: الناتج مطابق تمامًا لفصل بلا انقطاع
    func testResumeAfterInterruptionIsIdentical() async throws {
        SepLong.block = 15 * 44_100
        let src = dir.appendingPathComponent("b.m4a")
        try makeAudio(src, seconds: 80, beeps: [10, 50])
        // فاصل غير مطابق (يضرب بمعامل يتغير مع الزمن) ليظهر أي خطأ في الإكمال أو التلاشي
        let sep: SepLong.Separate = { l, r, p in
            var a = l, b = r
            for i in a.indices { let g = 0.5 + 0.3 * Float(sin(Double(i) * 0.0003)); a[i] *= g; b[i] *= g * 0.9 }
            p(1); return (a, b)
        }
        let full = dir.appendingPathComponent("full.raw"), resumed = dir.appendingPathComponent("resumed.raw")
        SepLong.testRawCopy = full
        _ = try await SepLong.run(src, keep: .vocals, engineName: "t2", separate: sep, progress: { _ in })
        // انقطاع عند الكتلة الثالثة
        var calls = 0
        let failing: SepLong.Separate = { l, r, p in
            calls += 1
            if calls == 3 { throw CancellationError() }
            return try await sep(l, r, p)
        }
        do {
            _ = try await SepLong.run(src, keep: .vocals, engineName: "t2", separate: failing, progress: { _ in })
            XCTFail("expected interruption")
        } catch is CancellationError {}
        XCTAssertNotNil(SepLong.pending(src, keep: .vocals, engine: "t2"))
        SepLong.testRawCopy = resumed
        let res = try await SepLong.run(src, keep: .vocals, engineName: "t2", separate: sep, progress: { _ in })
        XCTAssertTrue(res.resumed)
        XCTAssertNil(SepLong.pending(src, keep: .vocals, engine: "t2"))
        let a = try rawFloats(full), b = try rawFloats(resumed)
        XCTAssertEqual(a.count, b.count)
        XCTAssertEqual(a, b, "resumed output differs")
    }

    /// فيديو ٣ ساعات (صوته يبدأ بعد نصف ثانية): بعد الفصل وإعادة التركيب، كل نغمة في مكانها مع وميض الصورة
    /// (أول المقطع ووسطه وآخره) بفرق لا يتجاوز ٢٠ ملّي ثانية، وطول الصوت مطابق بالعيّنة
    func testThreeHourVideoStaysInSync() async throws {
        let seconds = 3.0 * 3600, offset = 0.5
        let flashes: [Double] = [2, 5400, 10_790]
        // الصوت: النغمة عند (زمن الوميض − بداية الصوت)
        let audio = dir.appendingPathComponent("long.m4a")
        try makeAudio(audio, seconds: seconds - offset, beeps: flashes.map { $0 - offset })
        // الصورة: ١٦×١٦، إطار كل ثانية، أبيض عند الوميض وأسود غيره
        let vid = dir.appendingPathComponent("frames.mov")
        try await makeVideo(vid, seconds: Int(seconds), flashes: flashes.map { Int($0) })
        // الفيديو المصدر: الصورة + الصوت بدءًا من نصف ثانية
        let comp = AVMutableComposition()
        let va = AVURLAsset(url: vid), aa = AVURLAsset(url: audio)
        let vt = try await va.loadTracks(withMediaType: .video).first!
        let at = try await aa.loadTracks(withMediaType: .audio).first!
        try comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
            .insertTimeRange(CMTimeRange(start: .zero, duration: try await va.load(.duration)), of: vt, at: .zero)
        try comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            .insertTimeRange(CMTimeRange(start: .zero, duration: try await aa.load(.duration)), of: at, at: CMTime(seconds: offset, preferredTimescale: 44_100))
        let src = dir.appendingPathComponent("source.mov")
        _ = try await MediaTools.export(comp, preset: AVAssetExportPresetPassthrough, to: src, type: .mov, progress: { _ in })

        // الفصل (مطابق) ثم إعادة الصوت للفيديو كما يفعل التطبيق
        let res = try await SepLong.run(src, keep: .vocals, engineName: "sync", separate: identity, progress: { _ in })
        // القارئ يُخرج الفراغ قبل بداية الصوت صمتًا (فتبدأ العيّنات من صفر) أو يعطي موضع البداية: المهم أن النغمات تبقى مع الوميض (أدناه)
        XCTAssertLessThanOrEqual(res.audioStart, offset + 0.01, "audio start offset")
        let out = try await MediaTools.replaceAudio(src, with: res.main, keepOriginal: false, audioStart: res.audioStart, loop: false, progress: { _ in })

        // طول الصوت بالعيّنة: الأصل والناتج
        let srcCount = try await countSamples(src), outCount = try await countSamples(res.main)
        XCTAssertEqual(outCount, srcCount, "sample count")

        // مواضع النغمات في الفيديو الناتج ومواضع الوميض
        let onsets = try await beepTimes(out, near: flashes)
        let frames = try await flashTimes(out)
        XCTAssertEqual(frames.count, flashes.count)
        for (k, f) in flashes.enumerated() {
            XCTAssertEqual(frames[safe: k] ?? -1, f, accuracy: 0.001, "flash \(k)")
            XCTAssertEqual(onsets[k], f, accuracy: 0.02, "beep \(k) at \(onsets[k]) vs flash \(f)")
        }
    }

    // MARK: أدوات

    private func makeVideo(_ url: URL, seconds: Int, flashes: [Int]) async throws {
        let w = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16])
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 16, kCVPixelBufferHeightKey as String: 16])
        w.add(input)
        w.startWriting(); w.startSession(atSourceTime: .zero)
        let set = Set(flashes)
        for s in 0..<seconds {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, ad.pixelBufferPool!, &pb)
            CVPixelBufferLockBaseAddress(pb!, [])
            memset(CVPixelBufferGetBaseAddress(pb!), set.contains(s) ? 255 : 0, CVPixelBufferGetDataSize(pb!))
            CVPixelBufferUnlockBaseAddress(pb!, [])
            ad.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(s), timescale: 1))
        }
        input.markAsFinished()
        await w.finishWriting()
        XCTAssertEqual(w.status, .completed)
    }

    private func countSamples(_ url: URL) async throws -> Int {
        let r = try await SepLong.Reader(url)
        var n = 0
        while true {
            try r.fill(to: r.end + 4_410_000, keepFrom: r.end)
            n = r.end
            r.drop(before: r.end)
            if r.eof { break }
        }
        return n
    }

    /// زمن بداية كل نغمة في صوت الملف (بداية الصوت + رقم العيّنة)
    private func beepTimes(_ url: URL, near times: [Double]) async throws -> [Double] {
        let r = try await SepLong.Reader(url)
        var found: [Double] = []
        var k = 0
        while k < times.count {
            try r.fill(to: r.end + 4_410_000, keepFrom: r.end - 10)
            let start = r.firstPTS ?? 0
            let lo = Int((times[k] - 1 - start) * rate)
            if let i = r.l.indices.first(where: { r.base + $0 >= lo && abs(r.l[$0]) > 0.1 }) {
                found.append(start + Double(r.base + i) / rate)
                k += 1
                continue
            }
            if r.eof { break }
            r.drop(before: r.end - 10)
        }
        while found.count < times.count { found.append(-1) }
        return found
    }

    private func flashTimes(_ url: URL) async throws -> [Double] {
        let a = AVURLAsset(url: url)
        let t = try await a.loadTracks(withMediaType: .video).first!
        let rd = try AVAssetReader(asset: a)
        let o = AVAssetReaderTrackOutput(track: t, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        rd.add(o); rd.startReading()
        var out: [Double] = []
        while let sb = o.copyNextSampleBuffer() {
            guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            let p = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
            let bright = p[CVPixelBufferGetBytesPerRow(pb) * 8 + 32] > 128
            CVPixelBufferUnlockBaseAddress(pb, .readOnly)
            if bright { out.append(CMSampleBufferGetPresentationTimeStamp(sb).seconds) }
        }
        return out
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
