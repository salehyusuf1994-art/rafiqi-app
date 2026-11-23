import XCTest
import AVFoundation
@testable import Hilal

/// أداة «تقسيم المقطع»: حساب الأجزاء، وتقسيم ملف حقيقي على الجهاز
final class SplitTests: XCTestCase {

    private func lengths(_ r: [ClosedRange<Double>]) -> [Double] { r.map { ($0.upperBound - $0.lowerBound).rounded() } }

    /// فيديو ساعة وعشرين دقيقة (المثال الذي طلبه المستخدم)
    func testRangesForEightyMinutes() {
        let total = 80.0 * 60
        XCTAssertEqual(lengths(MediaTools.splitRanges(total: total, every: 600)), Array(repeating: 600, count: 8))
        XCTAssertEqual(lengths(MediaTools.splitRanges(total: total, every: 1200)), Array(repeating: 1200, count: 4))
        XCTAssertEqual(lengths(MediaTools.splitRanges(total: total, every: 1800)), [1800, 1800, 1200])
        XCTAssertEqual(MediaTools.splitRanges(total: total, every: 60).count, 80)
        XCTAssertEqual(MediaTools.splitRanges(total: total, every: 3600).count, 2)
    }

    /// الأجزاء متصلة بلا فجوة ولا تداخل وتغطي المقطع كاملًا
    func testRangesAreContiguousAndComplete() {
        for (total, seg) in [(4800.0, 600.0), (4823.7, 300.0), (61.0, 60.0), (3599.2, 120.0)] {
            let r = MediaTools.splitRanges(total: total, every: seg)
            XCTAssertEqual(r.first?.lowerBound, 0)
            XCTAssertEqual(r.last?.upperBound ?? 0, total, accuracy: 1e-9)
            for (a, b) in zip(r, r.dropFirst()) { XCTAssertEqual(a.upperBound, b.lowerBound, accuracy: 1e-9) }
        }
    }

    /// بقية أقل من ثانية تُضم للجزء السابق؛ ومدة أطول من المقطع جزء واحد؛ والمدد غير الصالحة لا شيء
    func testRangesEdgeCases() {
        let r = MediaTools.splitRanges(total: 600.4, every: 60)
        XCTAssertEqual(r.count, 10)
        XCTAssertEqual(r.last!.upperBound - r.last!.lowerBound, 60.4, accuracy: 1e-9)
        XCTAssertEqual(MediaTools.splitRanges(total: 50, every: 60).count, 1)
        XCTAssertEqual(MediaTools.splitRanges(total: 120, every: 60).count, 2)
        XCTAssertTrue(MediaTools.splitRanges(total: 100, every: 0).isEmpty)
        XCTAssertTrue(MediaTools.splitRanges(total: 100, every: 0.5).isEmpty)
        XCTAssertTrue(MediaTools.splitRanges(total: .nan, every: 60).isEmpty)
        XCTAssertTrue(MediaTools.splitRanges(total: 0, every: 60).isEmpty)
    }

    /// الترقيم بأصفار بادئة يحفظ الترتيب في القائمة
    func testPartNamesSortInOrder() {
        let names = (1...80).map { MediaTools.splitPartName(base: "درس", index: $0, count: 80) }
        XCTAssertEqual(names, names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertEqual(Set(names).count, 80)
    }

    /// ملف صوتي ٥ ثوانٍ يُقسَّم كل ثانيتين: ٣ أجزاء (٢، ٢، ١) داخل مجلد جديد، بالطريقتين
    func testSplitRealFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("split-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("tone.m4a")
        try makeTone(src, seconds: 5)

        for exact in [false, true] {
            var steps: [Int] = []
            var folder: URL?
            let parts = try await MediaTools.split(src, every: 2, exact: exact,
                                                   folderReady: { folder = $0 },
                                                   part: { i, _ in steps.append(i) },
                                                   progress: { _ in })
            XCTAssertEqual(parts.count, 3)
            XCTAssertEqual(steps, [1, 2, 3])
            XCTAssertEqual(parts.map { $0.deletingLastPathComponent().lastPathComponent }, Array(repeating: folder?.lastPathComponent, count: 3))
            var durations: [Double] = []
            for p in parts {
                XCTAssertTrue(FileManager.default.fileExists(atPath: p.path))
                durations.append(try await AVURLAsset(url: p).load(.duration).seconds)
            }
            XCTAssertEqual(durations[0], 2, accuracy: 0.3, "exact=\(exact)")
            XCTAssertEqual(durations[1], 2, accuracy: 0.3, "exact=\(exact)")
            XCTAssertEqual(durations[2], 1, accuracy: 0.3, "exact=\(exact)")
        }
        // تقسيم ثانٍ لا يكتب داخل المجلد الأول
        let dirs = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0 != "tone.m4a" }
        XCTAssertEqual(dirs.count, 2)
    }

    /// أجزاء التقسيم تُدمج سريعًا (بلا إعادة ترميز) وبالترتيب المعطى، والناتج بطول الأصل
    func testMergeSplitPartsFast() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("merge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("tone.m4a")
        try makeTone(src, seconds: 6)
        let parts = try await MediaTools.split(src, every: 2, exact: false, part: { _, _ in }, progress: { _ in })
        XCTAssertEqual(parts.count, 3)
        let fast = await MediaTools.canMergeFast(parts)
        XCTAssertTrue(fast, "split parts should merge without re-encoding")
        let out = try await MediaTools.merge(parts, fast: fast, progress: { _ in })
        let d = try await AVURLAsset(url: out).load(.duration).seconds
        XCTAssertEqual(d, 6, accuracy: 0.3)
        // ملف مختلف الصيغة: لا دمج سريع
        let other = dir.appendingPathComponent("other.wav")
        try makeTone(other, seconds: 1, wav: true)
        let mixed = await MediaTools.canMergeFast([parts[0], other])
        XCTAssertFalse(mixed)
    }

    /// مدة أطول من المقطع: خطأ واضح، ولا يُنشأ مجلد
    func testSplitRejectsTooLongSegment() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("split-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("tone.m4a")
        try makeTone(src, seconds: 3)
        do {
            _ = try await MediaTools.split(src, every: 60, exact: false, part: { _, _ in }, progress: { _ in })
            XCTFail("expected error")
        } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["tone.m4a"])
    }

    /// نغمة AAC قصيرة
    private func makeTone(_ url: URL, seconds: Double, wav: Bool = false) throws {
        let rate = 44_100.0
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let settings: [String: Any] = wav
            ? [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
               AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            : [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frames = AVAudioFrameCount(rate * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames
        let p = buf.floatChannelData![0]
        for i in 0..<Int(frames) { p[i] = 0.3 * sinf(2 * .pi * 440 * Float(i) / Float(rate)) }
        try file.write(from: buf)
    }
}
