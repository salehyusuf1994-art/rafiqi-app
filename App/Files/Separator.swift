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

    /// standard: الطريقة الأولى (قطع متتالية، تمريرة واحدة) — تبقى للمقارنة في الفحص الآلي فقط.
    /// high: قطع متداخلة يُؤخذ وسطها النظيف (حواف القطع كانت تترك عيوبًا خفيفة كل ٦ ثوانٍ تقريبًا)،
    /// وتمريرتان للمقطع وعكسه ثم المتوسط (يلغي التشويش الذي يتركه النموذج) — نفس طريقة برنامج UVR
    enum Quality { case standard, high }

    static var modelURL: URL? { Bundle.main.url(forResource: "UVR_MDXNET_9482", withExtension: "mlmodelc") }
    static var available: Bool { modelURL != nil }

    /// يرجع ملف M4A فيه الجزء المطلوب
    /// auto: النموذج عالي الدقة (BS-RoFormer) إن كان منزّلًا، وإلا النموذج المضمّن
    enum Engine { case auto, builtIn, roformer }

    static func separate(_ src: URL, keep: Keep, quality: Quality = .high, engine: Engine = .auto,
                         progress: @escaping (Double) -> Void) async throws -> URL {
        if engine == .roformer || (engine == .auto && SepModelStore.isReady) {
            return try await Roformer.separate(src, keep: keep, progress: progress).0
        }
        guard let murl = modelURL else { throw ToolError.failed(L("نموذج الفصل غير موجود في هذه النسخة.")) }
        progress(0.01)
        // المعالج الرسومي لا المحرك العصبي: تجهيز هذا النموذج الكبير للمحرك العصبي في أول مرة يأخذ دقائق
        // (تبقى النسبة ٠٪ ويسخن الجوال). المعالج الرسومي يبدأ فورًا، وإن تعذّر نرجع للمعالج العادي
        let model: MLModel
        do {
            let cfg = MLModelConfiguration(); cfg.computeUnits = .cpuAndGPU
            model = try MLModel(contentsOf: murl, configuration: cfg)
        } catch {
            let cfg = MLModelConfiguration(); cfg.computeUnits = .cpuOnly
            model = try MLModel(contentsOf: murl, configuration: cfg)
        }
        try Task.checkCancellation()
        progress(0.02)
        let inName = model.modelDescription.inputDescriptionsByName.keys.first ?? "input"
        let outName = model.modelDescription.outputDescriptionsByName.keys.first ?? "output"

        // ١) قراءة الصوت ستيريو ٤٤١٠٠ هرتز
        let (lch, rch) = try await readPCM(src)
        try Task.checkCancellation()
        progress(0.05)
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
        // هامش كل قطعة (إطارات تُحسب للسياق ولا تُستخدم) والإشارات: ‎+١ للمقطع و‎−١ لعكسه
        let margin = quality == .high ? 16 : 0
        let keepFrames = frames - 2 * margin
        let signs: [Float] = quality == .high ? [1, -1] : [1]
        let plane = bins * frames
        // طيف القطعة مرة واحدة لكل قناة (يُعاد استخدامه للتمريرتين)، وناتج النموذج المتوسط
        var spec = [Float](repeating: 0, count: 4 * plane)
        var acc = [Float](repeating: 0, count: 4 * plane)
        var chunkStart = 0
        while chunkStart < totalFrames {
            try Task.checkCancellation()
            let t0 = chunkStart - margin
            let count = min(keepFrames, totalFrames - chunkStart)
            // الإطارات المحسوبة: من t0 حتى آخر إطار مستخدم + الهامش (ما بعد نهاية المقطع يبقى صفرًا كما كان)
            let used = min(frames, count + 2 * margin)
            for k in 0..<spec.count { spec[k] = 0; acc[k] = 0 }
            for f in 0..<used {
                for (c, x) in [lch, rch].enumerated() {
                    frame(x, t0 + f, &tmp)
                    forward(fwd, tmp, &re, &im)
                    for b in 0..<bins {
                        // الصندوق ٠: الجزء الحقيقي هو DC، والتخيلي صفر (المكان المحزوم فيه Nyquist يُهمل)
                        spec[((c * 2) * bins + b) * frames + f] = re[b] / 2
                        spec[((c * 2 + 1) * bins + b) * frames + f] = b == 0 ? 0 : im[b] / 2
                    }
                }
            }
            for sign in signs {
                try Task.checkCancellation()
                let input = try MLMultiArray(shape: [1, 4, NSNumber(value: bins), NSNumber(value: frames)], dataType: .float16)
                let ip = input.dataPointer.bindMemory(to: Float16.self, capacity: 4 * plane)
                for k in 0..<(4 * plane) { ip[k] = Float16(spec[k] * sign) }
                let out = try await model.prediction(from: MLDictionaryFeatureProvider(dictionary: [inName: input]))
                guard let y = out.featureValue(for: outName)?.multiArrayValue, y.count >= 4 * plane else { throw ToolError.failed(L("تعذّرت المعالجة.")) }
                // ربط الذاكرة مرة واحدة لكل دفعة (كان يتكرر لكل قيمة: ملايين المرات)
                let w = sign / Float(signs.count)
                if y.dataType == .float16 {
                    let p16 = y.dataPointer.bindMemory(to: Float16.self, capacity: y.count)
                    for k in 0..<(4 * plane) { acc[k] += Float(p16[k]) * w }
                } else {
                    let p32 = y.dataPointer.bindMemory(to: Float.self, capacity: y.count)
                    for k in 0..<(4 * plane) { acc[k] += p32[k] * w }
                }
            }
            // التركيب العكسي للإطارات الوسطى فقط (كل إطار يأتي من قطعة واحدة)
            for f in margin..<(margin + count) {
                let t = t0 + f
                for c in 0..<2 {
                    for b in 0..<bins {
                        re[b] = acc[((c * 2) * bins + b) * frames + f] * 2
                        im[b] = b == 0 ? 0 : acc[((c * 2 + 1) * bins + b) * frames + f] * 2
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
    static func calibrate(_ fwd: vDSP_DFT_Setup, _ inv: vDSP_DFT_Setup) -> Float {
        var x = [Float](repeating: 0, count: nfft)
        for i in 0..<nfft { x[i] = Float(sin(Double(i) * 0.37) + 0.5 * cos(Double(i) * 1.3)) }
        var re = [Float](repeating: 0, count: nfft / 2), im = re, y = x
        forward(fwd, x, &re, &im)
        inverse(inv, re, im, &y)
        var num: Float = 0, den: Float = 0
        for i in 0..<nfft { num += x[i] * x[i]; den += x[i] * y[i] }
        return den != 0 ? num / den : 1
    }

    static func forward(_ s: vDSP_DFT_Setup, _ x: [Float], _ re: inout [Float], _ im: inout [Float]) {
        let half = nfft / 2
        var er = [Float](repeating: 0, count: half), ei = er
        for k in 0..<half { er[k] = x[2 * k]; ei[k] = x[2 * k + 1] }
        vDSP_DFT_Execute(s, er, ei, &re, &im)
    }

    static func inverse(_ s: vDSP_DFT_Setup, _ re: [Float], _ im: [Float], _ x: inout [Float]) {
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
            let len = CMBlockBufferGetDataLength(bb) / 8 * 8   // عيّنات كاملة لقناتين فقط
            guard len > 0 else { continue }
            var data = [Float](repeating: 0, count: len / 4)
            data.withUnsafeMutableBytes { if let p = $0.baseAddress { _ = CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: len, destination: p) } }
            var i = 0
            while i + 1 < data.count { lch.append(data[i]); rch.append(data[i + 1]); i += 2 }
        }
        guard r.status == .completed || !lch.isEmpty else { throw ToolError.failed(L("تعذّرت قراءة الصوت.")) }
        return (lch, rch)
    }

    static func writeM4A(_ lch: [Float], _ rch: [Float], to out: URL) throws {
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

    // MARK: اختبار ذاتي (للفحص الآلي فقط): كلام + موسيقى (وتر، نغمات، باص، طبول) ← فصل ← قياس النقاء

    private static func dot(_ a: [Float], _ b: [Float], _ shift: Int, _ step: Int) -> (Double, Double, Double) {
        let n = min(a.count - shift, b.count)
        guard n > 1000 else { return (0, 0, 0) }
        var ab = 0.0, aa = 0.0, bb = 0.0
        for i in stride(from: 0, to: n, by: step) { let x = Double(a[i + shift]), y = Double(b[i]); ab += x * y; aa += x * x; bb += y * y }
        return (ab, aa, bb)
    }

    /// كم بقي من المرجع داخل الناتج (١ = كاملًا، ٠ = لا شيء)، بنفس محاذاة التأخير
    static func share(_ est: [Float], _ ref: [Float], shift: Int) -> Double {
        let (ab, _, bb) = dot(est, ref, shift, 1)
        return bb > 0 ? ab / bb : 0
    }

    /// تأخير الترميز بين الناتج والمرجع
    static func align(_ est: [Float], _ ref: [Float]) -> Int {
        var best = 0, bestC = -1.0
        for sh in stride(from: 0, through: 4096, by: 32) {
            let (ab, aa, bb) = dot(est, ref, sh, 4)
            if aa > 0, bb > 0, ab / sqrt(aa * bb) > bestC { bestC = ab / sqrt(aa * bb); best = sh }
        }
        for sh in max(0, best - 32)...(best + 32) {
            let (ab, aa, bb) = dot(est, ref, sh, 2)
            if aa > 0, bb > 0, ab / sqrt(aa * bb) > bestC { bestC = ab / sqrt(aa * bb); best = sh }
        }
        return best
    }

    /// SI-SDR بالديسيبل بعد محاذاة التأخير (كلما زاد كان الفصل أنقى)
    static func sdr(_ est: [Float], _ ref: [Float]) -> Double {
        // تأخير الترميز: بحث خشن ثم دقيق
        var best = 0, bestC = -1.0
        for sh in stride(from: 0, through: 4096, by: 32) {
            let (ab, aa, bb) = dot(est, ref, sh, 4)
            if aa > 0, bb > 0, ab / sqrt(aa * bb) > bestC { bestC = ab / sqrt(aa * bb); best = sh }
        }
        for sh in max(0, best - 32)...(best + 32) {
            let (ab, aa, bb) = dot(est, ref, sh, 2)
            if aa > 0, bb > 0, ab / sqrt(aa * bb) > bestC { bestC = ab / sqrt(aa * bb); best = sh }
        }
        let (ab, aa, bb) = dot(est, ref, best, 1)
        guard bb > 0, aa > 0 else { return -99 }
        // الهدف = إسقاط التقدير على المرجع؛ والباقي تشويش
        let alpha = ab / bb
        let target = alpha * alpha * bb
        let noise = max(1e-12, aa - 2 * alpha * ab + alpha * alpha * bb)
        return 10 * log10(target / noise)
    }

    static func selfTest() async -> String {
        do {
            let tmp = FileManager.default.temporaryDirectory
            // ١) كلام مولّد (أطول من قطعتين ليظهر أثر حواف القطع)
            let speechURL = tmp.appendingPathComponent("sep_speech.caf")
            try? FileManager.default.removeItem(at: speechURL)
            let synth = AVSpeechSynthesizer()
            let u = AVSpeechUtterance(string: "بسم الله الرحمن الرحيم. هذا اختبار لفصل الصوت البشري عن الموسيقى في تطبيق رفيقي. نقرأ جملة طويلة حتى نتأكد أن الفصل نظيف من البداية إلى النهاية، وأن الانتقال بين أجزاء المقطع لا يترك أي أثر. الحمد لله رب العالمين.")
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
            // ٢) موسيقى بطول الكلام: وتر بتوافقيات، نغمات متقطعة، باص، طبل وصنج (ستيريو)
            let speechDur = (try? await AVURLAsset(url: speechURL).load(.duration).seconds) ?? 12
            let toneURL = tmp.appendingPathComponent("sep_tone.caf")
            try? FileManager.default.removeItem(at: toneURL)
            let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
            let tf = try AVAudioFile(forWriting: toneURL, settings: fmt.settings)
            let total = Int(speechDur * rate)
            let tb = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(total))!
            tb.frameLength = AVAudioFrameCount(total)
            let chords: [[Double]] = [[220, 261.6, 329.6], [174.6, 220, 261.6], [261.6, 329.6, 392], [196, 246.9, 293.7]]
            var seed: UInt32 = 12345
            for i in 0..<total {
                let t = Double(i) / rate
                let ch = chords[Int(t / 2) % chords.count]
                var pad = 0.0
                for f in ch { for k in 1...6 { pad += sin(2 * .pi * f * Double(k) * t) / Double(k * k) } }
                pad *= 0.05
                let beat = t.truncatingRemainder(dividingBy: 0.25)
                let note = ch[Int(t / 0.25) % 3] * 2
                let pluck = 0.10 * sin(2 * .pi * note * t) * exp(-beat * 12)
                let bass = 0.10 * (sin(2 * .pi * ch[0] / 2 * t) + 0.4 * sin(2 * .pi * ch[0] * t))
                let kt = t.truncatingRemainder(dividingBy: 0.5)
                let kick = 0.25 * sin(2 * .pi * (50 + 70 * exp(-kt * 30)) * kt) * exp(-kt * 9)
                seed = seed &* 1664525 &+ 1013904223
                let noise = Double(Int32(bitPattern: seed)) / Double(Int32.max)
                let hat = 0.05 * noise * exp(-beat * 60)
                let l = pad * 1.1 + pluck * 0.7 + bass + kick + hat * 0.6
                let r = pad * 0.9 + pluck * 1.3 + bass + kick + hat * 1.4
                tb.floatChannelData![0][i] = Float(l); tb.floatChannelData![1][i] = Float(r)
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
            try? FileManager.default.removeItem(at: mixURL)
            _ = try await MediaTools.export(comp, preset: AVAssetExportPresetAppleM4A, to: mixURL, type: .m4a, progress: { _ in })
            // ٤) الفصل بالطريقتين والقياس
            let (sp, _) = try await readPCM(speechURL)
            let (tn, _) = try await readPCM(toneURL)
            var res: [String: Double] = [:]
            var clean: [URL] = [mixURL, speechURL, toneURL]
            // old: الأداة كما كانت عند المستخدم، mdx: نفس النموذج بالتحسينات،
            // rof: النموذج عالي الدقة بالتداخل الخفيف (الأسرع)، rofh: بتداخل النصف (كل ثانية مرتين) للمقارنة
            try await SepModelStore.shared.ensureReady()
            for name in ["old", "mdx", "rof", "rofh"] {
                let voc: URL, mus: URL
                let t0 = Date()
                if name.hasPrefix("rof") {
                    let (v, m) = try await Roformer.separate(mixURL, keep: .vocals, alsoOther: true, overlap: name == "rof" ? .edges : .half, progress: { _ in })
                    voc = v; mus = m ?? v
                } else {
                    let q: Quality = name == "old" ? .standard : .high
                    voc = try await separate(mixURL, keep: .vocals, quality: q, engine: .builtIn, progress: { _ in })
                    mus = try await separate(mixURL, keep: .music, quality: q, engine: .builtIn, progress: { _ in })
                }
                res["sec_" + name] = Date().timeIntervalSince(t0)
                clean += [voc, mus]
                let (vo, _) = try await readPCM(voc)
                let (mu, _) = try await readPCM(mus)
                res["sdrV_" + name] = sdr(vo, sp)
                res["sdrM_" + name] = sdr(mu, tn)
                // ما يهم المستخدم مباشرة: كم بقي من الصوت البشري، وكم بقي من الموسيقى (طاقة، ٪)
                let sv = align(vo, sp)
                res["keepV_" + name] = 100 * max(0, share(vo, sp, shift: sv))
                res["leakV_" + name] = 100 * pow(share(vo, tn, shift: sv), 2)
                let sm = align(mu, tn)
                res["keepM_" + name] = 100 * max(0, share(mu, tn, shift: sm))
                res["leakM_" + name] = 100 * pow(share(mu, sp, shift: sm), 2)
                if name == "rof" {
                    // التشابه (للتوافق مع الفحص السابق)
                    func corr(_ a: [Float], _ b: [Float]) -> Double {
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
                    res["vs"] = corr(vo, sp); res["mt"] = corr(mu, tn)
                }
            }
            clean.forEach { try? FileManager.default.removeItem(at: $0) }
            var r = String(format: "SEPTEST vocals~speech=%.2f music~tone=%.2f", res["vs"] ?? 0, res["mt"] ?? 0)
            for k in ["sdrV", "sdrM", "keepV", "leakV", "keepM", "leakM", "sec"] {
                for e in ["old", "mdx", "rof", "rofh"] { r += String(format: " %@_%@=%.2f", k, e, res[k + "_" + e] ?? 0) }
            }
            return r
        } catch {
            return "SEPTEST error: \(error.localizedDescription)"
        }
    }
}
