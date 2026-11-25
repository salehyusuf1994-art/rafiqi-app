import Foundation
import AVFoundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Vision
import Speech
import PDFKit
import SwiftLAME

// MARK: - أدوات الصوت والفيديو والصور (كلها على الجهاز، بدون رفع أي ملف)

enum ToolError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let s) = self { return s }; return nil }
}

/// جلسة التصدير لإيقافها من معالج الإلغاء
private final class ExportBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ s: AVAssetExportSession) { session = s }
}

enum MediaTools {
    // MARK: أساسيات

    /// ملف ناتج بجانب الأصل: «الاسم - وصف.امتداد»
    static func output(for src: URL, suffix: String, ext: String) -> URL {
        let base = src.deletingPathExtension().lastPathComponent
        let dir = src.deletingLastPathComponent()
        var u = dir.appendingPathComponent("\(base) - \(suffix).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: u.path) {
            u = dir.appendingPathComponent("\(base) - \(suffix) (\(n)).\(ext)")
            n += 1
        }
        return u
    }

    static func videoTrack(_ a: AVAsset) async -> AVAssetTrack? { try? await a.loadTracks(withMediaType: .video).first }
    static func audioTracks(_ a: AVAsset) async -> [AVAssetTrack] { (try? await a.loadTracks(withMediaType: .audio)) ?? [] }
    static func duration(_ a: AVAsset) async -> CMTime { (try? await a.load(.duration)) ?? .zero }

    /// الحجم كما يُعرض (بعد التدوير)
    static func displaySize(_ t: AVAssetTrack) async -> CGSize {
        let n = (try? await t.load(.naturalSize)) ?? .zero
        let tr = (try? await t.load(.preferredTransform)) ?? .identity
        let r = CGRect(origin: .zero, size: n).applying(tr)
        return CGSize(width: abs(r.width), height: abs(r.height))
    }

    /// تصدير مع متابعة التقدّم
    static func export(_ asset: AVAsset, preset: String, to out: URL, type: AVFileType,
                       range: CMTimeRange? = nil, video: AVVideoComposition? = nil, mix: AVAudioMix? = nil,
                       pitch: AVAudioTimePitchAlgorithm? = nil, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let s = AVAssetExportSession(asset: asset, presetName: preset) else { throw ToolError.failed(L("هذا الملف لا يدعم هذه العملية.")) }
        try? FileManager.default.removeItem(at: out)
        s.outputURL = out
        s.outputFileType = type
        s.shouldOptimizeForNetworkUse = true
        if let range { s.timeRange = range }
        if let video { s.videoComposition = video }
        if let mix { s.audioMix = mix }
        if let pitch { s.audioTimePitchAlgorithm = pitch }
        let watcher = Task {
            while !Task.isCancelled {
                progress(Double(s.progress))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        // إغلاق الأداة أو «إلغاء» يوقف التصدير فعلًا (لا يبقى يعمل في الخلفية)
        let box = ExportBox(s)
        await withTaskCancellationHandler { await s.export() } onCancel: { box.session.cancelExport() }
        watcher.cancel()
        if Task.isCancelled || s.status == .cancelled {
            try? FileManager.default.removeItem(at: out)
            throw CancellationError()
        }
        progress(1)
        if s.status != .completed {
            try? FileManager.default.removeItem(at: out)
            throw ToolError.failed(s.error?.localizedDescription ?? L("تعذّر إكمال العملية."))
        }
        return out
    }

    static func isVideo(_ u: URL) -> Bool { FileKind.of(u, isDir: false) == .video }

    // MARK: تحويل الصوت

    /// تحويل أو استخراج الصوت إلى M4A (AAC)
    static func toM4A(_ src: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let a = AVURLAsset(url: src)
        guard !(await audioTracks(a)).isEmpty else { throw ToolError.failed(L("لا يحتوي الملف على صوت.")) }
        return try await export(a, preset: AVAssetExportPresetAppleM4A, to: output(for: src, suffix: L("صوت"), ext: "m4a"), type: .m4a, progress: progress)
    }

    /// تحويل إلى MP3 (‏١٩٢ ك.ب/ث)
    static func toMP3(_ src: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        var input = src
        var tmp: URL?
        // الفيديو والصيغ التي لا يقرؤها AVAudioFile تُستخرج أولًا إلى M4A
        if isVideo(src) || (try? AVAudioFile(forReading: src)) == nil {
            let t = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            let a = AVURLAsset(url: src)
            guard !(await audioTracks(a)).isEmpty else { throw ToolError.failed(L("لا يحتوي الملف على صوت.")) }
            _ = try await export(a, preset: AVAssetExportPresetAppleM4A, to: t, type: .m4a, progress: { progress($0 * 0.3) })
            input = t; tmp = t
        }
        defer { if let tmp { try? FileManager.default.removeItem(at: tmp) } }
        let out = output(for: src, suffix: "MP3", ext: "mp3")
        let p = Progress()
        let watcher = Task {
            while !Task.isCancelled {
                if p.totalUnitCount > 0 { progress(0.3 + 0.7 * Double(p.completedUnitCount) / Double(p.totalUnitCount)) }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { watcher.cancel() }
        let enc = try SwiftLameEncoder(sourceUrl: input, configuration: LameConfiguration(sampleRate: .default, bitrateMode: .constant(192), quality: .nearBest),
                                       destinationUrl: out, progress: p)
        try await enc.encode(priority: .userInitiated)
        progress(1)
        return out
    }

    /// تحويل إلى WAV (بدون ضغط)
    static func toWAV(_ src: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let out = output(for: src, suffix: "WAV", ext: "wav")
        let a = AVURLAsset(url: src)
        guard let track = await audioTracks(a).first else { throw ToolError.failed(L("لا يحتوي الملف على صوت.")) }
        let reader = try AVAssetReader(asset: a)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                                       AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2]
        let ro = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(ro)
        let writer = try AVAssetWriter(outputURL: out, fileType: .wav)
        let wi = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        writer.add(wi)
        reader.startReading(); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        let total = (await duration(a)).seconds
        while let buf = ro.copyNextSampleBuffer() {
            while !wi.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 5_000_000) }
            wi.append(buf)
            let t = CMSampleBufferGetPresentationTimeStamp(buf).seconds
            if total > 0 { progress(t / total) }
        }
        wi.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw ToolError.failed(L("تعذّر التحويل.")) }
        return out
    }

    // MARK: القص والنغمة

    static func trim(_ src: URL, start: Double, end: Double, ringtone: Bool = false, progress: @escaping (Double) -> Void) async throws -> URL {
        let a = AVURLAsset(url: src)
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        if ringtone {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            _ = try await export(a, preset: AVAssetExportPresetAppleM4A, to: tmp, type: .m4a, range: range, progress: progress)
            let out = output(for: src, suffix: L("نغمة"), ext: "m4r")
            try FileManager.default.moveItem(at: tmp, to: out)
            return out
        }
        if isVideo(src) {
            return try await export(a, preset: AVAssetExportPresetHighestQuality, to: output(for: src, suffix: L("مقطوع"), ext: "mp4"), type: .mp4, range: range, progress: progress)
        }
        return try await export(a, preset: AVAssetExportPresetAppleM4A, to: output(for: src, suffix: L("مقطوع"), ext: "m4a"), type: .m4a, range: range, progress: progress)
    }

    // MARK: التقسيم

    /// مدد الأجزاء: أجزاء متساوية والأخير هو الباقي؛ بقية أقل من ثانية تُضم للجزء السابق (لا جزء شبه فارغ)
    static func splitRanges(total: Double, every seg: Double) -> [ClosedRange<Double>] {
        guard total.isFinite, total > 0, seg.isFinite, seg >= 1 else { return [] }
        var out: [ClosedRange<Double>] = []
        var t = 0.0
        while t < total - 1e-6 {
            out.append(t...min(total, t + seg))
            t += seg
        }
        if out.count > 1, let last = out.last, last.upperBound - last.lowerBound < 1 {
            out.removeLast()
            out[out.count - 1] = out[out.count - 1].lowerBound...total
        }
        return out
    }

    /// أقصى عدد للأجزاء (حماية من مجلد بآلاف الملفات بسبب مدة قصيرة جدًا)
    static let maxSplitParts = 1000

    /// اسم الجزء: «الاسم - ٠٣ من ٨٠» — الترقيم بأصفار بادئة ليبقى الترتيب صحيحًا في القائمة
    static func splitPartName(base: String, index: Int, count: Int) -> String {
        let w = String(count).count
        let num = String(repeating: "0", count: max(0, w - String(index).count)) + String(index)
        return LF("%@ - %@ من %@", base, ar(num), ar(count))
    }

    /// تقسيم المقطع إلى أجزاء متساوية المدة داخل مجلد جديد بجانبه.
    /// exact = false: بلا إعادة ضغط (سريع وبالجودة نفسها، والقص على أقرب إطار مفتاحي فقد يزيد أو ينقص ثانية أو ثانيتين)؛
    /// exact = true، أو صيغة لا تقبل النسخ المباشر: إعادة ترميز (أبطأ، والقص على الثانية).
    /// عند الإلغاء أو الفشل يُحذف الجزء غير المكتمل فقط، ويُحذف المجلد إن بقي فارغًا.
    static func split(_ src: URL, every seg: Double, exact: Bool,
                      folderReady: @escaping (URL) -> Void = { _ in },
                      part: @escaping (Int, Int) -> Void,
                      progress: @escaping (Double) -> Void) async throws -> [URL] {
        let a = AVURLAsset(url: src)
        let total = await duration(a).seconds
        let ranges = splitRanges(total: total, every: seg)
        guard total.isFinite, total > 0 else { throw ToolError.failed(L("هذا الملف لا يدعم هذه العملية.")) }
        guard ranges.count >= 2 else { throw ToolError.failed(L("المدة المختارة أطول من المقطع أو تساويه، فلن يُقسَّم.")) }
        guard ranges.count <= maxSplitParts else { throw ToolError.failed(LF("عدد الأجزاء كبير جدًا (الحد %@ جزء). اختر مدة أطول.", ar(maxSplitParts))) }
        let video = isVideo(src)
        if video, await videoTrack(a) == nil { throw ToolError.failed(L("لا يحتوي الملف على فيديو.")) }
        if !video, await audioTracks(a).isEmpty { throw ToolError.failed(L("لا يحتوي الملف على صوت.")) }

        // الصيغة: نسخ مباشر بصيغة الملف نفسها إن أمكن، وإلا إعادة ترميز
        var preset = video ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A
        var type: AVFileType = video ? .mp4 : .m4a
        var passthrough = false
        if !exact {
            let byExt: [String: AVFileType] = ["mp4": .mp4, "m4v": .m4v, "mov": .mov, "m4a": .m4a, "aac": .m4a,
                                               "wav": .wav, "caf": .caf, "aif": .aiff, "aiff": .aiff, "3gp": .mobile3GPP]
            var candidates: [AVFileType] = byExt[src.pathExtension.lowercased()].map { [$0] } ?? []
            candidates += video ? [.mp4, .mov] : [.m4a, .caf]
            for t in candidates {
                if await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough, with: a, outputFileType: t) {
                    preset = AVAssetExportPresetPassthrough; type = t; passthrough = true; break
                }
            }
        }
        let ext: String = [AVFileType.mp4: "mp4", .m4v: "m4v", .mov: "mov", .m4a: "m4a", .wav: "wav",
                           .caf: "caf", .aiff: "aiff", .mobile3GPP: "3gp"][type] ?? (video ? "mp4" : "m4a")

        // المساحة: النسخ المباشر بحجم الأصل تقريبًا، وإعادة الترميز قد تزيد
        let size = Int64((try? src.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let need = Int64(Double(size) * (passthrough ? 1.05 : 1.3)) + 100_000_000
        let dir = src.deletingLastPathComponent()
        if let free = (try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage,
           free < need {
            throw ToolError.failed(LF("المساحة المتاحة لا تكفي للتقسيم: يحتاج تقريبًا %@، والمتاح %@.", sizeText(need), sizeText(free)))
        }

        let base = src.deletingPathExtension().lastPathComponent
        // اسم مجلد جديد دائمًا (لا يُكتب داخل مجلد سابق)؛ والنقطة في اسم الملف لا تُعامل كامتداد
        let stem = LF("%@ - مقسّم", base)
        var folder = dir.appendingPathComponent(stem, isDirectory: true)
        var k = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = dir.appendingPathComponent("\(stem) (\(k))", isDirectory: true); k += 1
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        // مجلد الأجزاء يُفتح مرتبًا بالاسم: ١، ٢، ٣ … (لا بالتاريخ فيظهر مقلوبًا)
        let made = folder
        await MainActor.run { FilePrefs.setFolderSort(.name, true, for: FileStore.shared.key(made)) }
        folderReady(folder)
        var parts: [URL] = []
        do {
            for (i, r) in ranges.enumerated() {
                try Task.checkCancellation()
                part(i + 1, ranges.count)
                let out = folder.appendingPathComponent(splitPartName(base: base, index: i + 1, count: ranges.count)).appendingPathExtension(ext)
                let range = CMTimeRange(start: CMTime(seconds: r.lowerBound, preferredTimescale: 600),
                                        end: CMTime(seconds: r.upperBound, preferredTimescale: 600))
                let n = Double(ranges.count)
                parts.append(try await export(a, preset: preset, to: out, type: type, range: range,
                                              progress: { v in progress((Double(i) + v) / n) }))
            }
        } catch {
            if parts.isEmpty { try? FileManager.default.removeItem(at: folder) }
            throw error
        }
        progress(1)
        return parts
    }

    // MARK: الفيديو

    /// تركيب يحافظ على اتجاه الفيديو
    private static func composition(_ a: AVAsset, video: Bool = true, audio: Bool = true) async throws -> (AVMutableComposition, AVMutableCompositionTrack?, CGAffineTransform) {
        let c = AVMutableComposition()
        let d = await duration(a)
        var vt: AVMutableCompositionTrack?
        var tr = CGAffineTransform.identity
        if video, let v = await videoTrack(a) {
            vt = c.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            try vt?.insertTimeRange(CMTimeRange(start: .zero, duration: d), of: v, at: .zero)
            tr = (try? await v.load(.preferredTransform)) ?? .identity
            vt?.preferredTransform = tr
        }
        if audio {
            for t in await audioTracks(a) {
                let at = c.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                try at?.insertTimeRange(CMTimeRange(start: .zero, duration: d), of: t, at: .zero)
            }
        }
        return (c, vt, tr)
    }

    static func mute(_ src: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let (c, _, _) = try await composition(AVURLAsset(url: src), audio: false)
        if let out = try await passthrough(c, for: src, suffix: L("بدون صوت"), progress: progress) { return out }
        return try await export(c, preset: AVAssetExportPresetHighestQuality, to: output(for: src, suffix: L("بدون صوت"), ext: "mp4"), type: .mp4, progress: progress)
    }

    static func speed(_ src: URL, factor: Double, progress: @escaping (Double) -> Void) async throws -> URL {
        let a = AVURLAsset(url: src)
        let video = isVideo(src)
        let (c, _, _) = try await composition(a, video: video)
        let d = await duration(a)
        let newD = CMTime(seconds: d.seconds / factor, preferredTimescale: 600)
        for t in c.tracks { t.scaleTimeRange(CMTimeRange(start: .zero, duration: d), toDuration: newD) }
        let suffix = LF("سرعة %@", ar(String(format: "%g", factor)) + "×")
        if video {
            return try await export(c, preset: AVAssetExportPresetHighestQuality, to: output(for: src, suffix: suffix, ext: "mp4"), type: .mp4, pitch: .spectral, progress: progress)
        }
        return try await export(c, preset: AVAssetExportPresetAppleM4A, to: output(for: src, suffix: suffix, ext: "m4a"), type: .m4a, pitch: .spectral, progress: progress)
    }

    /// تدوير ٩٠° مع عقارب الساعة
    static func rotate(_ src: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let a = AVURLAsset(url: src)
        let (c, vt, tr) = try await composition(a)
        guard let vt, let v = await videoTrack(a) else { throw ToolError.failed(L("لا يحتوي الملف على فيديو.")) }
        let size = await displaySize(v)
        let fps = (try? await v.load(.nominalFrameRate)) ?? 30
        let rot = CGAffineTransform(translationX: size.height, y: 0).rotated(by: .pi / 2)
        let vc = AVMutableVideoComposition()
        vc.renderSize = CGSize(width: size.height, height: size.width)
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, fps.rounded())))
        let ins = AVMutableVideoCompositionInstruction()
        ins.timeRange = CMTimeRange(start: .zero, duration: c.duration)
        let li = AVMutableVideoCompositionLayerInstruction(assetTrack: vt)
        li.setTransform(tr.concatenating(rot), at: .zero)
        ins.layerInstructions = [li]
        vc.instructions = [ins]
        return try await export(c, preset: AVAssetExportPresetHighestQuality, to: output(for: src, suffix: L("مدوّر"), ext: "mp4"), type: .mp4, video: vc, progress: progress)
    }

    /// قص الحواف إلى نسبة (عرض:ارتفاع) من المنتصف
    static func crop(_ src: URL, aspect: CGFloat, progress: @escaping (Double) -> Void) async throws -> URL {
        let a = AVURLAsset(url: src)
        let (c, vt, tr) = try await composition(a)
        guard let vt, let v = await videoTrack(a) else { throw ToolError.failed(L("لا يحتوي الملف على فيديو.")) }
        let size = await displaySize(v)
        let fps = (try? await v.load(.nominalFrameRate)) ?? 30
        var w = size.width, h = size.width / aspect
        if h > size.height { h = size.height; w = h * aspect }
        w = floor(w / 2) * 2; h = floor(h / 2) * 2
        let x = (size.width - w) / 2, y = (size.height - h) / 2
        let vc = AVMutableVideoComposition()
        vc.renderSize = CGSize(width: w, height: h)
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, fps.rounded())))
        let ins = AVMutableVideoCompositionInstruction()
        ins.timeRange = CMTimeRange(start: .zero, duration: c.duration)
        let li = AVMutableVideoCompositionLayerInstruction(assetTrack: vt)
        li.setTransform(tr.concatenating(CGAffineTransform(translationX: -x, y: -y)), at: .zero)
        ins.layerInstructions = [li]
        vc.instructions = [ins]
        return try await export(c, preset: AVAssetExportPresetHighestQuality, to: output(for: src, suffix: L("مقصوص الحواف"), ext: "mp4"), type: .mp4, video: vc, progress: progress)
    }

    /// تقليل الحجم
    static func compress(_ src: URL, preset: String, progress: @escaping (Double) -> Void) async throws -> URL {
        try await export(AVURLAsset(url: src), preset: preset, to: output(for: src, suffix: L("مضغوط"), ext: "mp4"), type: .mp4, progress: progress)
    }

    /// كتابة نص على الفيديو
    static func text(_ src: URL, text: String, position: Int, size: CGFloat, color: UIColor, progress: @escaping (Double) -> Void) async throws -> URL {
        let a = AVURLAsset(url: src)
        let (c, vt, tr) = try await composition(a)
        guard let vt, let v = await videoTrack(a) else { throw ToolError.failed(L("لا يحتوي الملف على فيديو.")) }
        let rs = await displaySize(v)
        let fps = (try? await v.load(.nominalFrameRate)) ?? 30
        let vc = AVMutableVideoComposition()
        vc.renderSize = rs
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, fps.rounded())))
        let ins = AVMutableVideoCompositionInstruction()
        ins.timeRange = CMTimeRange(start: .zero, duration: c.duration)
        let li = AVMutableVideoCompositionLayerInstruction(assetTrack: vt)
        li.setTransform(tr, at: .zero)
        ins.layerInstructions = [li]
        vc.instructions = [ins]
        let parent = CALayer(), videoLayer = CALayer(), textLayer = CATextLayer()
        parent.frame = CGRect(origin: .zero, size: rs)
        videoLayer.frame = parent.frame
        let fontSize = rs.width * size
        let font = UIFont(name: "Tajawal-Bold", size: fontSize) ?? .boldSystemFont(ofSize: fontSize)
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.7); shadow.shadowBlurRadius = fontSize * 0.15
        let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para, .shadow: shadow])
        textLayer.string = attr
        textLayer.isWrapped = true
        textLayer.alignmentMode = .center
        textLayer.contentsScale = 2
        let boxH = attr.boundingRect(with: CGSize(width: rs.width * 0.9, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).height + fontSize * 0.4
        // ملاحظة: إحداثيات طبقات الفيديو تبدأ من الأسفل
        let yPos: CGFloat = position == 0 ? rs.height - boxH - rs.height * 0.06 : (position == 1 ? (rs.height - boxH) / 2 : rs.height * 0.06)
        textLayer.frame = CGRect(x: rs.width * 0.05, y: yPos, width: rs.width * 0.9, height: boxH)
        parent.addSublayer(videoLayer)
        parent.addSublayer(textLayer)
        vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
        return try await export(c, preset: AVAssetExportPresetHighestQuality, to: output(for: src, suffix: L("مع نص"), ext: "mp4"), type: .mp4, video: vc, progress: progress)
    }

    /// استبدال صوت الفيديو بملف صوتي (أو مزجه)
    /// audioStart: بداية الصوت في الفيديو الأصلي (تحفظ المزامنة كما كانت)، loop: تكرار الصوت الأقصر حتى نهاية الفيديو
    static func replaceAudio(_ src: URL, with audio: URL, keepOriginal: Bool, audioStart: Double = 0, loop: Bool = true,
                             progress: @escaping (Double) -> Void) async throws -> URL {
        let a = AVURLAsset(url: src), b = AVURLAsset(url: audio)
        let (c, _, _) = try await composition(a, audio: keepOriginal)
        let d = await duration(a)
        guard let bt = await audioTracks(b).first else { throw ToolError.failed(L("الملف الصوتي المختار لا يحتوي على صوت.")) }
        let bd = await duration(b)
        let t = c.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var at = CMTime(seconds: max(0, audioStart), preferredTimescale: 44_100)
        while at < d {
            let len = min(bd, d - at)
            try t?.insertTimeRange(CMTimeRange(start: .zero, duration: len), of: bt, at: at)
            at = at + len
            if bd.seconds <= 0 || !loop { break }
        }
        // الصوت الجديد بدل الأصلي: الفيديو يُنسخ كما هو بلا إعادة ضغط (أسرع بكثير وبجودته الأصلية تمامًا)
        if !keepOriginal, let out = try await passthrough(c, for: src, suffix: L("صوت جديد"), progress: progress) { return out }
        return try await export(c, preset: AVAssetExportPresetHighestQuality, to: output(for: src, suffix: L("صوت جديد"), ext: "mp4"), type: .mp4, progress: progress)
    }

    /// تصدير بلا إعادة ترميز إن قبلته الصيغة (nil = غير ممكن، فيُستخدم التصدير العادي)
    private static func passthrough(_ c: AVAsset, for src: URL, suffix: String, progress: @escaping (Double) -> Void) async throws -> URL? {
        for (t, ext) in [(AVFileType.mp4, "mp4"), (.mov, "mov")] {
            guard await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough, with: c, outputFileType: t) else { continue }
            do { return try await export(c, preset: AVAssetExportPresetPassthrough, to: output(for: src, suffix: suffix, ext: ext), type: t, progress: progress) }
            catch is CancellationError { throw CancellationError() }
            catch { return nil }
        }
        return nil
    }

    /// بصمة المسار: الترميز والمقاس والاتجاه (فيديو) أو التردد والقنوات (صوت)
    private static func trackSignature(_ t: AVAssetTrack?) async -> String {
        guard let t else { return "none" }
        let fds = (try? await t.load(.formatDescriptions)) ?? []
        guard let fd = fds.first, fds.count == 1 else { return "mixed-\(UUID())" }
        var sig = "\(CMFormatDescriptionGetMediaSubType(fd))"
        if t.mediaType == .video {
            let d = CMVideoFormatDescriptionGetDimensions(fd)
            let tr = (try? await t.load(.preferredTransform)) ?? .identity
            sig += "|\(d.width)x\(d.height)|\(tr.a),\(tr.b),\(tr.c),\(tr.d)"
        } else if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
            sig += "|\(asbd.mSampleRate)|\(asbd.mChannelsPerFrame)"
        }
        return sig
    }

    /// تُدمج بلا إعادة ترميز؟ (كلها بنفس الترميز والمقاس والاتجاه والصوت — مثل أجزاء «تقسيم المقطع»): سريع وبالجودة نفسها
    static func canMergeFast(_ urls: [URL]) async -> Bool {
        guard urls.count >= 2 else { return false }
        let video = urls.allSatisfy(isVideo)
        var first: (String, String)?
        for u in urls {
            let a = AVURLAsset(url: u)
            let v = video ? await trackSignature(videoTrack(a)) : "-"
            let tracks = await audioTracks(a)
            guard tracks.count <= 1 else { return false }
            let au = await trackSignature(tracks.first)
            if video, v == "none" { return false }
            if !video, au == "none" { return false }
            if let first { if first != (v, au) { return false } } else { first = (v, au) }
        }
        return true
    }

    /// دمج عدة مقاطع (فيديو أو صوت) بالتتابع وبالترتيب المعطى.
    /// fast: بلا إعادة ترميز (يُتحقق منه بـ canMergeFast)، وإن تعذّر يرجع تلقائيًا لإعادة الترميز.
    static func merge(_ urls: [URL], fast: Bool = false, progress: @escaping (Double) -> Void) async throws -> URL {
        guard urls.count >= 2, let first = urls.first else { throw ToolError.failed(L("اختر ملفين على الأقل.")) }
        let video = urls.allSatisfy(isVideo)
        // المساحة: الناتج بحجم المجموع تقريبًا
        let total = urls.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        let need = total + total / 10 + 100_000_000
        if let free = (try? first.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage,
           free < need {
            throw ToolError.failed(LF("المساحة المتاحة لا تكفي للدمج: يحتاج تقريبًا %@، والمتاح %@.", sizeText(need), sizeText(free)))
        }
        if fast {
            do { return try await mergeFast(urls, video: video, progress: progress) }
            catch is CancellationError { throw CancellationError() }
            catch { progress(0) }   // صيغة لا تقبل النسخ المباشر: إعادة ترميز
        }
        return try await mergeReencode(urls, video: video, progress: progress)
    }

    private static func mergeFast(_ urls: [URL], video: Bool, progress: @escaping (Double) -> Void) async throws -> URL {
        let c = AVMutableComposition()
        let vt = video ? c.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) : nil
        var at: AVMutableCompositionTrack?
        var cursor = CMTime.zero
        for u in urls {
            try Task.checkCancellation()
            let a = AVURLAsset(url: u)
            let d = await duration(a)
            let range = CMTimeRange(start: .zero, duration: d)
            if let vt, let v = await videoTrack(a) {
                if cursor == .zero { vt.preferredTransform = (try? await v.load(.preferredTransform)) ?? .identity }
                try vt.insertTimeRange(range, of: v, at: cursor)
            }
            if let t = await audioTracks(a).first {
                if at == nil { at = c.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) }
                try at?.insertTimeRange(range, of: t, at: cursor)
            }
            cursor = cursor + d
        }
        let first = urls[0]
        let candidates: [AVFileType] = video
            ? (first.pathExtension.lowercased() == "mov" ? [.mov, .mp4] : [.mp4, .mov])
            : [.m4a]
        for t in candidates {
            guard await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough, with: c, outputFileType: t) else { continue }
            let ext = t == .mov ? "mov" : (t == .m4a ? "m4a" : "mp4")
            return try await export(c, preset: AVAssetExportPresetPassthrough, to: output(for: first, suffix: L("مدمج"), ext: ext), type: t, progress: progress)
        }
        throw ToolError.failed(L("تعذّر الدمج."))
    }

    private static func mergeReencode(_ urls: [URL], video: Bool, progress: @escaping (Double) -> Void) async throws -> URL {
        let first = urls[0]
        let c = AVMutableComposition()
        let vt = video ? c.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) : nil
        let at = c.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        var render = CGSize(width: 1280, height: 720)
        var instructions: [AVMutableVideoCompositionInstruction] = []
        if video, let v0 = await videoTrack(AVURLAsset(url: first)) { render = await displaySize(v0) }
        for u in urls {
            try Task.checkCancellation()
            let a = AVURLAsset(url: u)
            let d = await duration(a)
            let range = CMTimeRange(start: .zero, duration: d)
            if video, let v = await videoTrack(a), let vt {
                try vt.insertTimeRange(range, of: v, at: cursor)
                let tr = (try? await v.load(.preferredTransform)) ?? .identity
                let s = await displaySize(v)
                let k = min(render.width / max(1, s.width), render.height / max(1, s.height))
                let fit = tr.concatenating(CGAffineTransform(scaleX: k, y: k))
                    .concatenating(CGAffineTransform(translationX: (render.width - s.width * k) / 2, y: (render.height - s.height * k) / 2))
                let li = AVMutableVideoCompositionLayerInstruction(assetTrack: vt)
                li.setTransform(fit, at: cursor)
                let ins = AVMutableVideoCompositionInstruction()
                ins.timeRange = CMTimeRange(start: cursor, duration: d)
                ins.layerInstructions = [li]
                instructions.append(ins)
            }
            if let t = await audioTracks(a).first { try at?.insertTimeRange(range, of: t, at: cursor) }
            cursor = cursor + d
        }
        if video {
            let vc = AVMutableVideoComposition()
            vc.renderSize = CGSize(width: floor(render.width / 2) * 2, height: floor(render.height / 2) * 2)
            vc.frameDuration = CMTime(value: 1, timescale: 30)
            vc.instructions = instructions
            return try await export(c, preset: AVAssetExportPresetHighestQuality, to: output(for: first, suffix: L("مدمج"), ext: "mp4"), type: .mp4, video: vc, progress: progress)
        }
        return try await export(c, preset: AVAssetExportPresetAppleM4A, to: output(for: first, suffix: L("مدمج"), ext: "m4a"), type: .m4a, progress: progress)
    }

    /// تحويل إلى GIF (حتى ١٥ ثانية، ١٠ إطارات بالثانية)
    static func gif(_ src: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let a = AVURLAsset(url: src)
        let d = min(15, (await duration(a)).seconds)
        guard d > 0 else { throw ToolError.failed(L("لا يحتوي الملف على فيديو.")) }
        let gen = AVAssetImageGenerator(asset: a)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 480)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let out = output(for: src, suffix: "GIF", ext: "gif")
        let fps = 10.0, count = Int(d * fps)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, count, nil) else { throw ToolError.failed(L("تعذّر التحويل.")) }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        for i in 0..<count {
            let t = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            if let img = try? await gen.image(at: t).image { CGImageDestinationAddImage(dest, img, frameProps) }
            progress(Double(i) / Double(count))
        }
        guard CGImageDestinationFinalize(dest) else { throw ToolError.failed(L("تعذّر التحويل.")) }
        return out
    }

    /// عكس الفيديو (يُحذف الصوت) — يُعالج على مقاطع قصيرة حتى لا تمتلئ الذاكرة
    static func reverse(_ src: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let a = AVURLAsset(url: src)
        guard let v = await videoTrack(a) else { throw ToolError.failed(L("لا يحتوي الملف على فيديو.")) }
        let d = (await duration(a)).seconds
        let n = (try? await v.load(.naturalSize)) ?? CGSize(width: 1280, height: 720)
        let tr = (try? await v.load(.preferredTransform)) ?? .identity
        let out = output(for: src, suffix: L("معكوس"), ext: "mp4")
        let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        let wi = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: n.width, AVVideoHeightKey: n.height,
        ])
        wi.transform = tr
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: wi, sourcePixelBufferAttributes: nil)
        writer.add(wi)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        // كل الإطارات المقروءة في الذاكرة معًا: المقطع أقصر كلما كبرت الدقة (4K يبقى في حدود معقولة)
        let px = max(1, abs(n.width * n.height))
        let chunk = min(1.0, max(0.2, Double(1920 * 1080) / Double(px)))
        var segStart = max(0, d - chunk)
        var outTime = 0.0
        var segEnd = d
        while segEnd > 0 {
            let reader = try AVAssetReader(asset: a)
            let ro = AVAssetReaderTrackOutput(track: v, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
            reader.add(ro)
            reader.timeRange = CMTimeRange(start: CMTime(seconds: segStart, preferredTimescale: 600), end: CMTime(seconds: segEnd, preferredTimescale: 600))
            reader.startReading()
            var frames: [(CVPixelBuffer, Double)] = []
            while let b = ro.copyNextSampleBuffer() {
                if let px = CMSampleBufferGetImageBuffer(b) { frames.append((px, CMSampleBufferGetPresentationTimeStamp(b).seconds)) }
            }
            reader.cancelReading()
            let times = frames.map(\.1)
            for (i, f) in frames.reversed().enumerated() {
                while !wi.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 3_000_000) }
                let gap = i == 0 ? 0 : (times[frames.count - i] - times[frames.count - i - 1])
                outTime += max(0, gap)
                adaptor.append(f.0, withPresentationTime: CMTime(seconds: outTime, preferredTimescale: 600))
            }
            if let last = times.first, let first = times.last { outTime += max(1 / 30, (first - last) / Double(max(1, times.count - 1))) }
            progress(1 - segStart / max(d, 0.01))
            segEnd = segStart
            segStart = max(0, segStart - chunk)
        }
        wi.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw ToolError.failed(L("تعذّر عكس الفيديو.")) }
        return out
    }

    // MARK: تعديل الصوت: رفع/خفض المستوى والتلاشي

    static func adjustAudio(_ src: URL, gainDB: Float, fadeIn: Double, fadeOut: Double, progress: @escaping (Double) -> Void) async throws -> URL {
        let input = try AVAudioFile(forReading: src)
        let format = input.processingFormat
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 0)
        eq.globalGain = max(-24, min(24, gainDB))
        engine.attach(node); engine.attach(eq)
        engine.connect(node, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        // جدولة بلا انتظار (التصيير يدوي بعدها؛ النسخة async تنتظر انتهاء التشغيل فتعلق)
        schedule(node, input)
        node.play()
        let out = output(for: src, suffix: L("معدّل"), ext: "m4a")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
                                       AVNumberOfChannelsKey: format.channelCount, AVEncoderBitRateKey: 192_000]
        let file = try AVAudioFile(forWriting: out, settings: settings)
        guard let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw ToolError.failed(L("تعذّر التعديل."))
        }
        let total = input.length
        let sr = format.sampleRate
        while engine.manualRenderingSampleTime < total {
            let left = total - engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(min(Int64(buf.frameCapacity), left))
            let st = try engine.renderOffline(frames, to: buf)
            guard st == .success else { break }
            // التلاشي في البداية والنهاية
            let start = Double(engine.manualRenderingSampleTime) - Double(buf.frameLength)
            if let ch = buf.floatChannelData, fadeIn > 0 || fadeOut > 0 {
                let dur = Double(total) / sr
                for f in 0..<Int(buf.frameLength) {
                    let t = (start + Double(f)) / sr
                    var g = 1.0
                    if fadeIn > 0, t < fadeIn { g = t / fadeIn }
                    if fadeOut > 0, t > dur - fadeOut { g = min(g, max(0, (dur - t) / fadeOut)) }
                    if g < 1 { for c in 0..<Int(buf.format.channelCount) { ch[c][f] *= Float(g) } }
                }
            }
            try file.write(from: buf)
            progress(Double(engine.manualRenderingSampleTime) / Double(total))
        }
        engine.stop()
        return out
    }

    // MARK: التفريغ النصي (على الجهاز)

    static func transcribe(_ src: URL, lang: String, progress: @escaping (Double) -> Void) async throws -> (text: String, srt: [(Double, Double, String)]) {
        let auth = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard auth == .authorized else { throw ToolError.failed(L("اسمح لرفيقي بالتعرّف على الكلام من الإعدادات.")) }
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: lang)), rec.isAvailable else {
            throw ToolError.failed(L("التعرّف على هذه اللغة غير متاح على جهازك الآن."))
        }
        let a = AVURLAsset(url: src)
        let total = (await duration(a)).seconds
        guard total > 0, !(await audioTracks(a)).isEmpty else { throw ToolError.failed(L("لا يحتوي الملف على صوت.")) }
        // مقاطع ٥٠ ثانية (حدود التعرّف لكل طلب)
        let step = 50.0
        var t = 0.0
        var cues: [(Double, Double, String)] = []
        var all: [String] = []
        while t < total {
            let end = min(total, t + step)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            _ = try await export(a, preset: AVAssetExportPresetAppleM4A, to: tmp, type: .m4a,
                                 range: CMTimeRange(start: CMTime(seconds: t, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600)),
                                 progress: { _ in })
            let req = SFSpeechURLRecognitionRequest(url: tmp)
            req.shouldReportPartialResults = false
            if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            req.addsPunctuation = true
            let offset = t
            let res: SFSpeechRecognitionResult? = await withCheckedContinuation { c in
                var done = false
                rec.recognitionTask(with: req) { r, e in
                    if done { return }
                    if let r, r.isFinal { done = true; c.resume(returning: r) }
                    else if e != nil { done = true; c.resume(returning: nil) }
                }
            }
            try? FileManager.default.removeItem(at: tmp)
            if let res {
                all.append(res.bestTranscription.formattedString)
                // جمل كل ~٦ ثوانٍ
                var buf: [String] = [], s0 = -1.0, last = 0.0
                for seg in res.bestTranscription.segments {
                    if s0 < 0 { s0 = seg.timestamp }
                    buf.append(seg.substring)
                    last = seg.timestamp + seg.duration
                    if last - s0 > 6 || buf.count >= 12 {
                        cues.append((offset + s0, offset + last, buf.joined(separator: " "))); buf = []; s0 = -1
                    }
                }
                if !buf.isEmpty { cues.append((offset + max(0, s0), offset + last, buf.joined(separator: " "))) }
            }
            t = end
            progress(t / total)
        }
        let text = all.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError.failed(L("لم يُتعرّف على كلام واضح في المقطع.")) }
        return (text, cues)
    }

    static func srt(_ cues: [(Double, Double, String)]) -> String {
        func ts(_ s: Double) -> String {
            let ms = Int((s * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
        }
        return cues.enumerated().map { "\($0.offset + 1)\n\(ts($0.element.0)) --> \(ts($0.element.1))\n\($0.element.2)\n" }.joined(separator: "\n")
    }

    // MARK: الصور

    static func image(_ u: URL) throws -> UIImage {
        guard let img = UIImage(contentsOfFile: u.path) else { throw ToolError.failed(L("تعذّر فتح الصورة.")) }
        return img
    }

    /// إزالة الخلفية (يُبقي الشخص أو العنصر البارز)
    static func removeBackground(_ src: URL) async throws -> URL {
        guard let ci = CIImage(contentsOf: src, options: [.applyOrientationProperty: true]) else { throw ToolError.failed(L("تعذّر فتح الصورة.")) }
        let req = VNGenerateForegroundInstanceMaskRequest()
        let h = VNImageRequestHandler(ciImage: ci)
        try h.perform([req])
        guard let r = req.results?.first else { throw ToolError.failed(L("لم يُعثر على عنصر بارز في الصورة.")) }
        let px = try r.generateMaskedImage(ofInstances: r.allInstances, from: h, croppedToInstancesExtent: false)
        let out = CIImage(cvPixelBuffer: px)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(out, from: out.extent), let png = UIImage(cgImage: cg).pngData() else { throw ToolError.failed(L("تعذّر الحفظ.")) }
        let dest = output(for: src, suffix: L("بدون خلفية"), ext: "png")
        try png.write(to: dest)
        return dest
    }

    /// ملصق واتساب: العنصر البارز مقصوصًا على خلفية شفافة ٥١٢×٥١٢ (PNG، وWebP إن دعمه النظام)
    static func sticker(_ src: URL) async throws -> URL {
        guard let ci = CIImage(contentsOf: src, options: [.applyOrientationProperty: true]) else { throw ToolError.failed(L("تعذّر فتح الصورة.")) }
        let req = VNGenerateForegroundInstanceMaskRequest()
        let h = VNImageRequestHandler(ciImage: ci)
        try h.perform([req])
        guard let r = req.results?.first else { throw ToolError.failed(L("لم يُعثر على عنصر بارز في الصورة.")) }
        let px = try r.generateMaskedImage(ofInstances: r.allInstances, from: h, croppedToInstancesExtent: true)
        let cut = CIImage(cvPixelBuffer: px)
        guard let cg = CIContext().createCGImage(cut, from: cut.extent) else { throw ToolError.failed(L("تعذّر الحفظ.")) }
        let side: CGFloat = 512, pad: CGFloat = 16
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        let w = CGFloat(cg.width), hgt = CGFloat(cg.height)
        let k = min((side - pad * 2) / w, (side - pad * 2) / hgt)
        let rect = CGRect(x: (side - w * k) / 2, y: (side - hgt * k) / 2, width: w * k, height: hgt * k)
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { _ in
            UIImage(cgImage: cg).draw(in: rect)
        }
        guard let png = img.pngData() else { throw ToolError.failed(L("تعذّر الحفظ.")) }
        let dest = output(for: src, suffix: L("ملصق"), ext: "png")
        try png.write(to: dest)
        // نسخة WebP (صيغة ملصقات واتساب) إن كان النظام يدعم ترميزها
        let webp = "org.webmproject.webp"
        if let types = CGImageDestinationCopyTypeIdentifiers() as? [String], types.contains(webp), let cgOut = img.cgImage {
            let wURL = dest.deletingPathExtension().appendingPathExtension("webp")
            if let d = CGImageDestinationCreateWithURL(wURL as CFURL, webp as CFString, 1, nil) {
                CGImageDestinationAddImage(d, cgOut, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
                if !CGImageDestinationFinalize(d) { try? FileManager.default.removeItem(at: wURL) }
            }
        }
        return dest
    }

    /// استخراج النص من صورة أو PDF
    static func recognizeText(_ src: URL) async throws -> String {
        if src.pathExtension.lowercased() == "pdf" {
            if let doc = PDFDocument(url: src), let s = doc.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
            throw ToolError.failed(L("لا يحتوي الملف على نص قابل للنسخ."))
        }
        let img = try image(src)
        guard let cg = img.cgImage else { throw ToolError.failed(L("تعذّر فتح الصورة.")) }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        // نفس لغات السكانر: العربية فقط إن كان الجهاز يدعمها (iOS 17 لا يدعمها فيفشل الطلب)
        req.recognitionLanguages = ScanProcessor.ocrLanguages
        try VNImageRequestHandler(cgImage: cg, orientation: CGImagePropertyOrientation(img.imageOrientation)).perform([req])
        let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { throw ToolError.failed(L("لم يُعثر على نص في الصورة.")) }
        return lines.joined(separator: "\n")
    }

    static func barcodes(_ src: URL) throws -> [String] {
        let img = try image(src)
        guard let cg = img.cgImage else { throw ToolError.failed(L("تعذّر فتح الصورة.")) }
        let req = VNDetectBarcodesRequest()
        try VNImageRequestHandler(cgImage: cg, orientation: CGImagePropertyOrientation(img.imageOrientation)).perform([req])
        let p = (req.results ?? []).compactMap(\.payloadStringValue)
        guard !p.isEmpty else { throw ToolError.failed(L("لم يُعثر على باركود أو رمز QR في الصورة.")) }
        return p
    }

    /// ضغط الصورة: جودة JPEG وحد أقصى للأبعاد
    static func compressImage(_ src: URL, quality: CGFloat, maxSide: CGFloat) throws -> URL {
        let img = try image(src)
        let s = img.size
        let k = min(1, maxSide / max(s.width, s.height))
        let r = UIGraphicsImageRenderer(size: CGSize(width: s.width * k, height: s.height * k), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let scaled = r.image { _ in img.draw(in: CGRect(origin: .zero, size: CGSize(width: s.width * k, height: s.height * k))) }
        guard let d = scaled.jpegData(compressionQuality: quality) else { throw ToolError.failed(L("تعذّر الضغط.")) }
        let dest = output(for: src, suffix: L("مضغوطة"), ext: "jpg")
        try d.write(to: dest)
        return dest
    }

    static func convertImage(_ src: URL, to ext: String) throws -> URL {
        let img = try image(src)
        let data: Data?
        switch ext {
        case "png": data = img.pngData()
        case "heic": data = img.heicData()
        default: data = img.jpegData(compressionQuality: 0.92)
        }
        guard let data else { throw ToolError.failed(L("تعذّر التحويل.")) }
        let dest = output(for: src, suffix: ext.uppercased(), ext: ext)
        try data.write(to: dest)
        return dest
    }

    static func rotateImage(_ src: URL) throws -> URL {
        let img = try image(src)
        let s = img.size
        let r = UIGraphicsImageRenderer(size: CGSize(width: s.height, height: s.width), format: { let f = UIGraphicsImageRendererFormat(); f.scale = img.scale; return f }())
        let out = r.image { c in
            c.cgContext.translateBy(x: s.height / 2, y: s.width / 2)
            c.cgContext.rotate(by: .pi / 2)
            img.draw(in: CGRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height))
        }
        let ext = src.pathExtension.lowercased() == "png" ? "png" : "jpg"
        guard let d = ext == "png" ? out.pngData() : out.jpegData(compressionQuality: 0.92) else { throw ToolError.failed(L("تعذّر التدوير.")) }
        let dest = output(for: src, suffix: L("مدوّرة"), ext: ext)
        try d.write(to: dest)
        return dest
    }

    /// صور ← PDF
    static func imagesToPDF(_ urls: [URL]) throws -> URL {
        guard let first = urls.first else { throw ToolError.failed(L("اختر صورة.")) }
        let pdf = PDFDocument()
        for u in urls {
            if let img = UIImage(contentsOfFile: u.path), let page = PDFPage(image: img) { pdf.insert(page, at: pdf.pageCount) }
        }
        guard pdf.pageCount > 0 else { throw ToolError.failed(L("تعذّر إنشاء الملف.")) }
        let dest = output(for: first, suffix: "PDF", ext: "pdf")
        guard pdf.write(to: dest) else { throw ToolError.failed(L("تعذّر الحفظ.")) }
        return dest
    }

    /// صورة + صوت ← فيديو (الصورة ثابتة طوال المقطع)
    static func imageWithAudio(_ image: URL, audio: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let img = try self.image(image)
        let a = AVURLAsset(url: audio)
        let d = await duration(a)
        guard d.seconds > 0 else { throw ToolError.failed(L("الملف الصوتي فارغ.")) }
        var size = img.size
        let k = min(1, 1920 / max(size.width, size.height))
        size = CGSize(width: floor(size.width * k / 2) * 2, height: floor(size.height * k / 2) * 2)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let w = try AVAssetWriter(outputURL: tmp, fileType: .mp4)
        let wi = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height])
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: wi, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height])
        w.add(wi); w.startWriting(); w.startSession(atSourceTime: .zero)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, nil, &pb)
        guard let pb else { throw ToolError.failed(L("تعذّر الإنشاء.")) }
        CVPixelBufferLockBaseAddress(pb, [])
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                               bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
            UIGraphicsPushContext(ctx)
            ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
            img.draw(in: CGRect(origin: .zero, size: size))
            UIGraphicsPopContext()
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        // إطار كل ثانية يكفي لصورة ثابتة
        var t = 0.0
        while t <= d.seconds {
            while !wi.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 3_000_000) }
            ad.append(pb, withPresentationTime: CMTime(seconds: t, preferredTimescale: 600))
            t += 1
        }
        wi.markAsFinished()
        await w.finishWriting()
        let c = AVMutableComposition()
        let v = AVURLAsset(url: tmp)
        if let vt = await videoTrack(v) {
            let ct = c.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            try ct?.insertTimeRange(CMTimeRange(start: .zero, duration: min(d, await duration(v))), of: vt, at: .zero)
        }
        if let at = await audioTracks(a).first {
            let ct = c.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try ct?.insertTimeRange(CMTimeRange(start: .zero, duration: d), of: at, at: .zero)
        }
        // بجانب الصورة (قد تكون في مجلد مقفل) لا بجانب الصوت: لا يخرج محتوى مقفل إلى مجلد مفتوح
        let out = try await export(c, preset: AVAssetExportPresetHighestQuality, to: output(for: image, suffix: L("فيديو"), ext: "mp4"), type: .mp4, progress: progress)
        try? FileManager.default.removeItem(at: tmp)
        return out
    }
}

extension MediaTools {
    // MARK: البيانات والصورة المصغّرة

    static func readMetadata(_ u: URL) async -> (title: String?, artist: String?, album: String?, art: UIImage?) {
        let a = AVURLAsset(url: u)
        let items = (try? await a.load(.commonMetadata)) ?? []
        func str(_ k: AVMetadataKey) async -> String? {
            guard let i = AVMetadataItem.metadataItems(from: items, withKey: k, keySpace: .common).first else { return nil }
            return try? await i.load(.stringValue)
        }
        var art: UIImage?
        if let i = AVMetadataItem.metadataItems(from: items, withKey: AVMetadataKey.commonKeyArtwork, keySpace: .common).first,
           let d = try? await i.load(.dataValue) { art = UIImage(data: d) }
        if art == nil, isVideo(u) {
            let g = AVAssetImageGenerator(asset: a); g.appliesPreferredTrackTransform = true; g.maximumSize = CGSize(width: 600, height: 600)
            if let cg = try? await g.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image { art = UIImage(cgImage: cg) }
        }
        return (await str(.commonKeyTitle), await str(.commonKeyArtist), await str(.commonKeyAlbumName), art)
    }

    static func writeMetadata(_ src: URL, title: String, artist: String, album: String, art: UIImage?, progress: @escaping (Double) -> Void) async throws -> URL {
        func item(_ k: AVMetadataIdentifier, _ v: Any) -> AVMetadataItem {
            let m = AVMutableMetadataItem(); m.identifier = k; m.value = v as? NSCopying & NSObjectProtocol; m.extendedLanguageTag = "und"; return m
        }
        var meta: [AVMetadataItem] = []
        if !title.isEmpty { meta.append(item(.commonIdentifierTitle, title as NSString)) }
        if !artist.isEmpty { meta.append(item(.commonIdentifierArtist, artist as NSString)) }
        if !album.isEmpty { meta.append(item(.commonIdentifierAlbumName, album as NSString)) }
        if let art, let d = art.jpegData(compressionQuality: 0.9) {
            let m = AVMutableMetadataItem(); m.identifier = .commonIdentifierArtwork; m.value = d as NSData; m.dataType = kCMMetadataBaseDataType_JPEG as String
            meta.append(m)
        }
        let a = AVURLAsset(url: src)
        let video = isVideo(src)
        let ext = video ? "mp4" : "m4a"
        let fm = FileManager.default
        /// تصدير بإعداد معيّن؛ يرجع الملف المؤقت إن نجح
        func export(_ preset: String) async -> URL? {
            let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            guard let s = AVAssetExportSession(asset: a, presetName: preset) else { return nil }
            s.outputURL = tmp
            s.outputFileType = video ? .mp4 : .m4a
            s.metadata = meta
            await s.export()
            if s.status == .completed { return tmp }
            try? fm.removeItem(at: tmp)
            return nil
        }
        // نسخ مباشر بلا إعادة ترميز أولًا (الجودة كما هي)؛ وإن لم يدعمه نوع الصوت (MP3 وFLAC…) يُعاد ترميزه
        var lossless = true
        var out = await export(AVAssetExportPresetPassthrough)
        if out == nil, !video { out = await export(AVAssetExportPresetAppleM4A); lossless = false }
        progress(1)
        guard let tmp = out else { throw ToolError.failed(L("هذا الملف لا يدعم هذه العملية.")) }
        // نفس النوع ونسخ بلا فقد: يحلّ محل الأصل بأمان (الجديد يُكتب أولًا)
        if lossless, src.pathExtension.lowercased() == ext {
            do { _ = try fm.replaceItemAt(src, withItemAt: tmp) } catch { try? fm.removeItem(at: tmp); throw error }
            return src
        }
        // نوع مختلف أو أعيد ترميزه: ملف جديد بجانب الأصل، ويبقى الأصل كما هو (لا تُفقد جودته ولا تنكسر القوائم)
        let dest = uniqueFileURL(src.deletingPathExtension().appendingPathExtension(ext).lastPathComponent,
                                 in: src.deletingLastPathComponent())
        do { try fm.moveItem(at: tmp, to: dest) } catch { try? fm.removeItem(at: tmp); throw error }
        return dest
    }

    // MARK: دمج الترجمة داخل الصورة

    static func burnSubtitles(_ src: URL, cues: [(Double, Double, String)], progress: @escaping (Double) -> Void) async throws -> URL {
        guard !cues.isEmpty else { throw ToolError.failed(L("لا يوجد ملف ترجمة بنفس اسم الفيديو.")) }
        let a = AVURLAsset(url: src)
        let c = AVMutableComposition()
        let d = await duration(a)
        guard let v = await videoTrack(a), let vt = c.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ToolError.failed(L("لا يحتوي الملف على فيديو."))
        }
        try vt.insertTimeRange(CMTimeRange(start: .zero, duration: d), of: v, at: .zero)
        for t in await audioTracks(a) {
            try c.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?.insertTimeRange(CMTimeRange(start: .zero, duration: d), of: t, at: .zero)
        }
        let tr = (try? await v.load(.preferredTransform)) ?? .identity
        let rs = await displaySize(v)
        let vc = AVMutableVideoComposition()
        vc.renderSize = rs
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        let ins = AVMutableVideoCompositionInstruction()
        ins.timeRange = CMTimeRange(start: .zero, duration: d)
        let li = AVMutableVideoCompositionLayerInstruction(assetTrack: vt)
        li.setTransform(tr, at: .zero)
        ins.layerInstructions = [li]
        vc.instructions = [ins]
        let parent = CALayer(), videoLayer = CALayer()
        parent.frame = CGRect(origin: .zero, size: rs); videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)
        let fs = max(18, rs.width * 0.045)
        let font = UIFont(name: "Tajawal-Bold", size: fs) ?? .boldSystemFont(ofSize: fs)
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let shadow = NSShadow(); shadow.shadowColor = UIColor.black; shadow.shadowBlurRadius = fs * 0.2
        for cue in cues {
            let l = CATextLayer()
            l.string = NSAttributedString(string: cue.2, attributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: para, .shadow: shadow])
            l.isWrapped = true
            l.alignmentMode = .center
            l.contentsScale = 2
            l.frame = CGRect(x: rs.width * 0.05, y: rs.height * 0.05, width: rs.width * 0.9, height: fs * 3.2)
            l.opacity = 0
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1; anim.toValue = 1
            anim.beginTime = AVCoreAnimationBeginTimeAtZero + max(0.001, cue.0)
            anim.duration = max(0.1, cue.1 - cue.0)
            anim.isRemovedOnCompletion = true
            anim.fillMode = .removed
            l.add(anim, forKey: "show")
            parent.addSublayer(l)
        }
        vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
        return try await export(c, preset: AVAssetExportPresetHighestQuality, to: output(for: src, suffix: L("مع الترجمة"), ext: "mp4"), type: .mp4, video: vc, progress: progress)
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// جدولة ملف في مشغّل صوتي دون انتظار انتهائه (للتصيير اليدوي)
private func schedule(_ node: AVAudioPlayerNode, _ file: AVAudioFile) {
    node.scheduleFile(file, at: nil, completionHandler: nil)
}
