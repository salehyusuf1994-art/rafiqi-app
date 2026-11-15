import Foundation
import AVFoundation
import Accelerate
import CoreML

// MARK: - فصل الصوت البشري عن الموسيقى على الجهاز (نموذج UVR MDX-Net — رخصة MIT)
// STFT ‏(n_fft ٤٠٩٦، hop ١٠٢٤، نافذة Hann) ← النموذج يقدّر طيف الصوت البشري ← iSTFT.
// الموسيقى = الأصل − الصوت البشري.

enum Separator {
    static let nfft = 4096, hop = 1024, bins = 2048, frames = 256, rate = 44100.0

    enum Keep { case vocals, music }

    static var modelURL: URL? { Bundle.main.url(forResource: "UVR_MDXNET_9482", withExtension: "mlmodelc") }
    static var available: Bool { modelURL != nil }

    /// يرجع ملف M4A فيه الجزء المطلوب
    static func separate(_ src: URL, keep: Keep, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let murl = modelURL else { throw ToolError.failed(L("نموذج الفصل غير موجود في هذه النسخة.")) }
        let cfg = MLModelConfiguration()
        cfg.computeUnits = .all
        let model = try MLModel(contentsOf: murl, configuration: cfg)
        let inName = model.modelDescription.inputDescriptionsByName.keys.first ?? "input"
        let outName = model.modelDescription.outputDescriptionsByName.keys.first ?? "output"

        // ١) قراءة الصوت ستيريو ٤٤١٠٠ هرتز
        let (lch, rch) = try await readPCM(src)
        let n = lch.count
        guard n > nfft else { throw ToolError.failed(L("المقطع قصير جدًا.")) }
        guard Double(n) / rate <= 20 * 60 else { throw ToolError.failed(L("المقطع أطول من ٢٠ دقيقة.")) }

        // ٢) إعداد التحويل
        let log2n = vDSP_Length(12)
        guard let fwd = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(nfft), .FORWARD),
              let inv = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(nfft), .INVERSE) else { throw ToolError.failed(L("تعذّرت المعالجة.")) }
        _ = log2n
        defer { vDSP_DFT_DestroySetup(fwd); vDSP_DFT_DestroySetup(inv) }
        let win = (0..<nfft).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(nfft))) }
        let invScale = calibrate(fwd, inv)

        let totalFrames = n / hop + 1
        var outL = [Float](repeating: 0, count: n), outR = [Float](repeating: 0, count: n)
        var wsum = [Float](repeating: 0, count: n)
        let half = nfft / 2

        // إطار واحد: يقرأ العيّنات حول t*hop مع انعكاس عند الأطراف
        func frame(_ x: [Float], _ t: Int, _ buf: inout [Float]) {
            let start = t * hop - half
            for i in 0..<nfft {
                var j = start + i
                if j < 0 { j = -j }
                if j >= n { j = max(0, 2 * (n - 1) - j) }
                buf[i] = x[min(max(j, 0), n - 1)] * win[i]
            }
        }

        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        var tmp = [Float](repeating: 0, count: nfft)
        var chunkStart = 0
        while chunkStart < totalFrames {
            try Task.checkCancellation()
            let count = min(frames, totalFrames - chunkStart)
            let input = try MLMultiArray(shape: [1, 4, NSNumber(value: bins), NSNumber(value: frames)], dataType: .float16)
            let ip = input.dataPointer.bindMemory(to: Float16.self, capacity: 4 * bins * frames)
            for k in 0..<(4 * bins * frames) { ip[k] = 0 }
            for f in 0..<count {
                for (c, x) in [lch, rch].enumerated() {
                    frame(x, chunkStart + f, &tmp)
                    forward(fwd, tmp, &re, &im)
                    for b in 0..<bins {
                        // الصندوق ٠: الجزء الحقيقي هو DC، والتخيلي صفر (المكان المحزوم فيه Nyquist يُهمل)
                        let r = re[b] / 2, i = b == 0 ? 0 : im[b] / 2
                        ip[((c * 2) * bins + b) * frames + f] = Float16(r)
                        ip[((c * 2 + 1) * bins + b) * frames + f] = Float16(i)
                    }
                }
            }
            let out = try await model.prediction(from: MLDictionaryFeatureProvider(dictionary: [inName: input]))
            guard let y = out.featureValue(for: outName)?.multiArrayValue else { throw ToolError.failed(L("تعذّرت المعالجة.")) }
            func val(_ idx: Int) -> Float {
                y.dataType == .float16 ? Float(y.dataPointer.bindMemory(to: Float16.self, capacity: y.count)[idx])
                                       : y.dataPointer.bindMemory(to: Float.self, capacity: y.count)[idx]
            }
            for f in 0..<count {
                let t = chunkStart + f
                for c in 0..<2 {
                    for b in 0..<bins {
                        re[b] = val(((c * 2) * bins + b) * frames + f) * 2
                        im[b] = b == 0 ? 0 : val(((c * 2 + 1) * bins + b) * frames + f) * 2
                    }
                    inverse(inv, re, im, &tmp)
                    let start = t * hop - half
                    for i in 0..<nfft {
                        let j = start + i
                        guard j >= 0, j < n else { continue }
                        let v = tmp[i] * invScale * win[i]
                        if c == 0 { outL[j] += v; wsum[j] += win[i] * win[i] } else { outR[j] += v }
                    }
                }
            }
            chunkStart += count
            progress(0.05 + 0.85 * Double(chunkStart) / Double(totalFrames))
        }
        for j in 0..<n where wsum[j] > 1e-6 { outL[j] /= wsum[j]; outR[j] /= wsum[j] }
        if keep == .music {
            for j in 0..<n { outL[j] = lch[j] - outL[j]; outR[j] = rch[j] - outR[j] }
        }
        // ٣) الحفظ
        let out = MediaTools.output(for: src, suffix: keep == .vocals ? L("بدون موسيقى") : L("بدون صوت بشري"), ext: "m4a")
        try writeM4A(outL, outR, to: out)
        progress(1)
        return out
    }

    /// المعامل الذي يعيد الإشارة بعد تحويل ذهابًا وإيابًا (يختلف حسب اصطلاح vDSP)
    private static func calibrate(_ fwd: vDSP_DFT_Setup, _ inv: vDSP_DFT_Setup) -> Float {
        var x = [Float](repeating: 0, count: nfft)
        for i in 0..<nfft { x[i] = Float(sin(Double(i) * 0.37) + 0.5 * cos(Double(i) * 1.3)) }
        var re = [Float](repeating: 0, count: nfft / 2), im = re, y = x
        forward(fwd, x, &re, &im)
        inverse(inv, re, im, &y)
        var num: Float = 0, den: Float = 0
        for i in 0..<nfft { num += x[i] * x[i]; den += x[i] * y[i] }
        return den != 0 ? num / den : 1
    }

    private static func forward(_ s: vDSP_DFT_Setup, _ x: [Float], _ re: inout [Float], _ im: inout [Float]) {
        let half = nfft / 2
        var er = [Float](repeating: 0, count: half), ei = er
        for k in 0..<half { er[k] = x[2 * k]; ei[k] = x[2 * k + 1] }
        vDSP_DFT_Execute(s, er, ei, &re, &im)
    }

    private static func inverse(_ s: vDSP_DFT_Setup, _ re: [Float], _ im: [Float], _ x: inout [Float]) {
        let half = nfft / 2
        var orr = [Float](repeating: 0, count: half), oi = orr
        vDSP_DFT_Execute(s, re, im, &orr, &oi)
        for k in 0..<half { x[2 * k] = orr[k]; x[2 * k + 1] = oi[k] }
    }

    /// قراءة أي ملف صوت أو فيديو إلى عيّنات عائمة ستيريو ٤٤١٠٠
    static func readPCM(_ u: URL) async throws -> ([Float], [Float]) {
        let a = AVURLAsset(url: u)
        guard let t = try await a.loadTracks(withMediaType: .audio).first else { throw ToolError.failed(L("لا يحتوي الملف على صوت.")) }
        let r = try AVAssetReader(asset: a)
        let o = AVAssetReaderTrackOutput(track: t, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
        ])
        r.add(o)
        r.startReading()
        var lch: [Float] = [], rch: [Float] = []
        while let sb = o.copyNextSampleBuffer(), let bb = CMSampleBufferGetDataBuffer(sb) {
            let len = CMBlockBufferGetDataLength(bb)
            var data = [Float](repeating: 0, count: len / 4)
            data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: len, destination: $0.baseAddress!) }
            lch.reserveCapacity(lch.count + data.count / 2); rch.reserveCapacity(rch.count + data.count / 2)
            var i = 0
            while i + 1 < data.count { lch.append(data[i]); rch.append(data[i + 1]); i += 2 }
        }
        guard r.status == .completed || !lch.isEmpty else { throw ToolError.failed(L("تعذّرت قراءة الصوت.")) }
        return (lch, rch)
    }

    private static func writeM4A(_ lch: [Float], _ rch: [Float], to out: URL) throws {
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { throw ToolError.failed(L("تعذّر الحفظ.")) }
        let f = try AVAudioFile(forWriting: out, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                                                             AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000])
        let chunk = 44100
        var pos = 0
        while pos < lch.count {
            let c = min(chunk, lch.count - pos)
            guard let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(c)), let ch = b.floatChannelData else { break }
            b.frameLength = AVAudioFrameCount(c)
            for i in 0..<c { ch[0][i] = max(-1, min(1, lch[pos + i])); ch[1][i] = max(-1, min(1, rch[pos + i])) }
            try f.write(from: b)
            pos += c
        }
    }

    // MARK: اختبار ذاتي (للفحص الآلي فقط): كلام + نغمة ← فصل ← قياس التشابه

    static func selfTest() async -> String {
        do {
            let tmp = FileManager.default.temporaryDirectory
            // ١) كلام مولّد
            let speechURL = tmp.appendingPathComponent("sep_speech.caf")
            try? FileManager.default.removeItem(at: speechURL)
            let synth = AVSpeechSynthesizer()
            let u = AVSpeechUtterance(string: "بسم الله الرحمن الرحيم. هذا اختبار لفصل الصوت البشري عن الموسيقى في تطبيق رفيقي. الحمد لله رب العالمين.")
            u.voice = AVSpeechSynthesisVoice(language: "ar-SA")
            var file: AVAudioFile?
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                var done = false
                synth.write(u) { buf in
                    guard let pcm = buf as? AVAudioPCMBuffer else { return }
                    if pcm.frameLength == 0 { if !done { done = true; c.resume() }; return }
                    if file == nil { file = try? AVAudioFile(forWriting: speechURL, settings: pcm.format.settings, commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved) }
                    try? file?.write(from: pcm)
                }
            }
            file = nil
            // ٢) نغمة (وتر موسيقي بسيط) بطول الكلام
            let speechDur = (try? await AVURLAsset(url: speechURL).load(.duration).seconds) ?? 6
            let toneURL = tmp.appendingPathComponent("sep_tone.caf")
            try? FileManager.default.removeItem(at: toneURL)
            let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
            let tf = try AVAudioFile(forWriting: toneURL, settings: fmt.settings)
            let total = Int(speechDur * rate)
            let tb = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(total))!
            tb.frameLength = AVAudioFrameCount(total)
            for i in 0..<total {
                let t = Double(i) / rate
                let v = Float(0.12 * (sin(2 * .pi * 220 * t) + sin(2 * .pi * 277.2 * t) + sin(2 * .pi * 329.6 * t)) * (0.6 + 0.4 * sin(2 * .pi * 2 * t)))
                tb.floatChannelData![0][i] = v; tb.floatChannelData![1][i] = v
            }
            try tf.write(from: tb)
            // ٣) المزج
            let comp = AVMutableComposition()
            for url in [speechURL, toneURL] {
                let a = AVURLAsset(url: url)
                if let t = try await a.loadTracks(withMediaType: .audio).first {
                    let d = try await a.load(.duration)
                    try comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
                        .insertTimeRange(CMTimeRange(start: .zero, duration: min(d, CMTime(seconds: speechDur, preferredTimescale: 600))), of: t, at: .zero)
                }
            }
            let mixURL = tmp.appendingPathComponent("sep_mix.m4a")
            _ = try await MediaTools.export(comp, preset: AVAssetExportPresetAppleM4A, to: mixURL, type: .m4a, progress: { _ in })
            // ٤) الفصل والقياس
            let voc = try await separate(mixURL, keep: .vocals, progress: { _ in })
            let mus = try await separate(mixURL, keep: .music, progress: { _ in })
            let (sp, _) = try await readPCM(speechURL)
            let (tn, _) = try await readPCM(toneURL)
            let (vo, _) = try await readPCM(voc)
            let (mu, _) = try await readPCM(mus)
            func corr(_ a: [Float], _ b: [Float]) -> Double {
                // AAC يضيف تأخيرًا صغيرًا: نجرّب إزاحات حتى ٤٠٩٦ عيّنة ونأخذ الأعلى
                var best = 0.0
                for shift in stride(from: 0, through: 4096, by: 64) {
                    let n = min(a.count - shift, b.count)
                    guard n > 1000 else { continue }
                    var ab = 0.0, aa = 0.0, bb = 0.0
                    for i in stride(from: 0, to: n, by: 2) { let x = Double(a[i + shift]), y = Double(b[i]); ab += x * y; aa += x * x; bb += y * y }
                    if aa > 0, bb > 0 { best = max(best, abs(ab / sqrt(aa * bb))) }
                }
                return best
            }
            let r = String(format: "SEPTEST vocals~speech=%.2f vocals~tone=%.2f music~tone=%.2f music~speech=%.2f",
                           corr(vo, sp), corr(vo, tn), corr(mu, tn), corr(mu, sp))
            [voc, mus, mixURL, speechURL, toneURL].forEach { try? FileManager.default.removeItem(at: $0) }
            return r
        } catch {
            return "SEPTEST error: \(error.localizedDescription)"
        }
    }
}
