import Foundation
import AVFoundation
import Accelerate
import CoreML
import CryptoKit

// MARK: - فصل الصوت عالي الدقة: BS-RoFormer (viperx، رخصة MIT)
// النموذج يُنزَّل مرة واحدة داخل التطبيق (لا يُضمَّن: حجمه ~٣٢٠ ميغا)، ويُتحقق من بصمة كل ملف قبل استخدامه.
// التحويل الطيفي هنا مطابق لـ torch.stft/istft (n_fft ٢٠٤٨، hop ٤٤١، نافذة Hann دورية، center مع انعكاس)،
// والنموذج يُرجع قناعًا مركّبًا يُضرب في الطيف. التقطيع: ٨ ثوانٍ بتداخل النصف وحواف متلاشية (كما في ZFTurbo).

/// ملفات النموذج المنشورة في صفحة Releases للمستودع
enum SepModelFiles {
    static let tag = "sep-model-v3"
    static let base = "https://github.com/salehyusuf1994-art/rafiqi-app/releases/download/\(tag)/"
    struct Part { let asset: String; let path: String; let sha256: String; let size: Int64 }
    /// تُملأ من files.json الناتج عن التحويل (البصمة تمنع استبدال الملف)
    static let parts: [Part] = [
        Part(asset: "Manifest.json", path: "Manifest.json", sha256: "1785a75736243f1bd90346672c6021e5d7ba6832388dcfd2ddc622ed09b99430", size: 617),
        Part(asset: "model.mlmodel", path: "Data/com.apple.CoreML/model.mlmodel", sha256: "38d78605cb230de699614be7d5b8bd2c5ed07ccc3d9fbc5a588138f351ff4b5a", size: 569_456),
        Part(asset: "weight.bin", path: "Data/com.apple.CoreML/weights/weight.bin", sha256: "61ba536f66eb05ca18bfc4502c66df3ca5a034f6fead89588710acd102c22440", size: 319_758_224),
    ]
    static var totalSize: Int64 { parts.reduce(0) { $0 + $1.size } }
}

/// حالة النموذج عالي الدقة: غير منزّل / يُنزَّل / يُجهَّز / جاهز
@MainActor
final class SepModelStore: NSObject, ObservableObject {
    static let shared = SepModelStore()

    enum State: Equatable { case missing, downloading(Double), preparing, ready, failed(String) }
    /// أين يعمل النموذج (من خطة الحساب): «المحرك العصبي ٩٧٪» — للتشخيص
    @Published var planSummary: String? = UserDefaults.standard.string(forKey: "sepmodel.plan")
    @Published private(set) var state: State = .missing

    nonisolated static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sepmodel", isDirectory: true)
    }
    nonisolated static var compiledURL: URL { dir.appendingPathComponent("BSRoformer-\(SepModelFiles.tag).mlmodelc", isDirectory: true) }
    nonisolated static var isReady: Bool { FileManager.default.fileExists(atPath: compiledURL.appendingPathComponent("coremldata.bin").path) }

    private var task: Task<Void, Never>?
    private var session: URLSession?
    private var current: (done: Int64, cont: CheckedContinuation<URL, Error>?, dest: URL?) = (0, nil, nil)
    private var received: Int64 = 0

    override init() {
        super.init()
        state = Self.isReady ? .ready : .missing
    }

    /// ينزّل الملفات ويتحقق من بصمتها ثم يجهّز النموذج للجوال
    func download() {
        guard task == nil, state != .ready else { return }
        state = .downloading(0)
        KeepAwake.begin()
        let bg = KeepAwake.Background("sepmodel")
        task = Task {
            defer { KeepAwake.end(); bg.finish(); task = nil; session?.invalidateAndCancel(); session = nil }
            do {
                try await run()
                state = .ready
            } catch is CancellationError {
                state = .missing
            } catch {
                state = Task.isCancelled ? .missing : .failed(error.localizedDescription)
            }
        }
    }

    func cancel() { task?.cancel(); session?.invalidateAndCancel() }

    /// حذف النموذج من الجوال (يرجع الفصل للنموذج المضمّن)
    func delete() {
        cancel()
        try? FileManager.default.removeItem(at: Self.dir)
        state = .missing
    }

    /// للفحص الآلي: ينزّل وينتظر حتى الجاهزية
    func ensureReady() async throws {
        if Self.isReady { state = .ready; return }
        download()
        while true {
            try await Task.sleep(nanoseconds: 500_000_000)
            switch state {
            case .ready: return
            case .failed(let m): throw ToolError.failed(m)
            case .missing: throw CancellationError()
            default: continue
            }
        }
    }

    private func run() async throws {
        let fm = FileManager.default
        let work = Self.dir.appendingPathComponent("download", isDirectory: true)
        let pkg = work.appendingPathComponent("BSRoformer.mlpackage", isDirectory: true)
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        // المساحة: الملفات + النسخة المجهّزة
        let need = SepModelFiles.totalSize * 2 + 200_000_000
        if let free = (try? Self.dir.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage,
           free < need {
            throw ToolError.failed(LF("المساحة المتاحة لا تكفي لتنزيل النموذج: يحتاج تقريبًا %@، والمتاح %@.", sizeText(need), sizeText(free)))
        }
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.waitsForConnectivity = true
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        session = s
        received = 0
        for part in SepModelFiles.parts {
            try Task.checkCancellation()
            guard let url = URL(string: SepModelFiles.base + part.asset) else { throw ToolError.failed(L("تعذّر التنزيل.")) }
            let dest = pkg.appendingPathComponent(part.path)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let tmp: URL = try await withCheckedThrowingContinuation { c in
                current = (received, c, dest)
                s.downloadTask(with: url).resume()
            }
            received += part.size
            // البصمة: أي ملف غير مطابق يُرفض (حماية من الاستبدال أو التلف)
            guard try Self.sha256(tmp) == part.sha256 else {
                try? fm.removeItem(at: tmp)
                throw ToolError.failed(L("ملف النموذج المنزّل غير سليم. حاول مرة أخرى."))
            }
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: tmp, to: dest)
        }
        try Task.checkCancellation()
        state = .preparing
        // تجهيز النموذج للجوال (مرة واحدة)، ثم حذف الملفات الخام
        let compiled = try await MLModel.compileModel(at: pkg)
        try? fm.removeItem(at: Self.compiledURL)
        try fm.moveItem(at: compiled, to: Self.compiledURL)
        try? fm.removeItem(at: work)
        // نسخ أقدم من النموذج: تُحذف (لا تبقى مساحة ضائعة)
        for old in (try? fm.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil)) ?? []
        where old.pathExtension == "mlmodelc" && old.lastPathComponent != Self.compiledURL.lastPathComponent {
            try? fm.removeItem(at: old)
        }
        // تجهيز المحرك العصبي مرة واحدة (يحفظه النظام بعدها)، وخطة الحساب للتشخيص
        await Roformer.Runner.warmUp()
        var u = Self.dir
        var rv = URLResourceValues(); rv.isExcludedFromBackup = true
        try? u.setResourceValues(rv)
    }

    nonisolated static func sha256(_ u: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: u)
        defer { try? h.close() }
        var hasher = SHA256()
        while let d = try h.read(upToCount: 4 << 20), !d.isEmpty { hasher.update(data: d) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension SepModelStore: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            let total = max(1, SepModelFiles.totalSize)
            let v = Double(self.current.done + totalBytesWritten) / Double(total)
            // تحديث كل ١٪ تقريبًا فقط
            if case .downloading(let old) = self.state, v - old < 0.01, v < 1 { return }
            if case .downloading = self.state { self.state = .downloading(min(1, v)) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // الملف المؤقت يُحذف بعد عودة هذه الدالة: يُنقل فورًا
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sepmodel-\(UUID().uuidString)")
        let ok = (downloadTask.response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        let moved = ok && (try? FileManager.default.moveItem(at: location, to: tmp)) != nil
        Task { @MainActor in
            let c = self.current.cont; self.current.cont = nil
            if moved { c?.resume(returning: tmp) } else { c?.resume(throwing: ToolError.failed(L("تعذّر التنزيل."))) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            let c = self.current.cont; self.current.cont = nil
            if (error as? URLError)?.code == .cancelled { c?.resume(throwing: CancellationError()) }
            else { c?.resume(throwing: error) }
        }
    }
}

// MARK: - المحرّك

enum Roformer {
    static let nfft = 2048, hop = 441, bins = 1025, frames = 801, chunk = 352_800, rate = 44_100.0

    /// يفصل المقطع ويرجع ملف M4A بالجزء المطلوب (والآخر عند الطلب)
    /// تقرير آخر فصل: المدة ووقت كل قطعة وأين عمل النموذج (يظهر للمستخدم بعد الفصل)
    @MainActor static var lastReport: String?

    /// edges: تداخل عند الحواف فقط (كل ثانية تُحسب مرة واحدة تقريبًا)، half: تداخل النصف (كل ثانية مرتين)
    enum Overlap { case edges, half }

    static func separate(_ src: URL, keep: Separator.Keep, alsoOther: Bool = false, overlap: Overlap = .edges,
                         progress: @escaping (Double) -> Void) async throws -> (URL, URL?) {
        let t0 = Date()
        guard SepModelStore.isReady else { throw ToolError.failed(L("نموذج الفصل عالي الدقة غير منزّل.")) }
        progress(0.01)
        let model = try await Runner.make()
        try Task.checkCancellation()
        let (lch, rch) = try await Separator.readPCM(src)
        let n = lch.count
        guard n > nfft else { throw ToolError.failed(L("المقطع قصير جدًا.")) }
        guard Double(n) / rate <= 20 * 60 else { throw ToolError.failed(L("المقطع أطول من ٢٠ دقيقة.")) }
        progress(0.04)
        var chunks = 0
        let (vl, vr) = try await vocals(model: model, lch, rch, overlap: overlap, chunks: &chunks, progress: { progress(0.04 + 0.9 * $0) })
        var ml = [Float](repeating: 0, count: n), mr = ml
        for i in 0..<n { ml[i] = lch[i] - vl[i]; mr[i] = rch[i] - vr[i] }
        let vName = L("بدون موسيقى"), mName = L("بدون صوت بشري")
        let mainOut = MediaTools.output(for: src, suffix: keep == .vocals ? vName : mName, ext: "m4a")
        if keep == .vocals { try Separator.writeM4A(vl, vr, to: mainOut) } else { try Separator.writeM4A(ml, mr, to: mainOut) }
        var other: URL?
        if alsoOther {
            let o = MediaTools.output(for: src, suffix: keep == .vocals ? mName : vName, ext: "m4a")
            if keep == .vocals { try Separator.writeM4A(ml, mr, to: o) } else { try Separator.writeM4A(vl, vr, to: o) }
            other = o
        }
        progress(1)
        let secs = Date().timeIntervalSince(t0)
        let plan = await MainActor.run { SepModelStore.shared.planSummary }
        var report = LF("استغرق الفصل %@ (%@ ثانية لكل ٨ ثوانٍ من المقطع).", durationText(secs),
                        ar(String(format: "%.1f", secs / Double(max(1, chunks)))))
        if let plan { report += " " + LF("يعمل على: %@.", plan) }
        if model.fallbacks > 0 { report += " " + LF("%@ من الأجزاء عملت على بديل أبطأ (خرجت من التطبيق؟).", ar(model.fallbacks)) }
        await MainActor.run { lastReport = report }
        return (mainOut, other)
    }

    /// الصوت البشري للمقطع كاملًا: قطع ٨ ثوانٍ بتداخل النصف، وحواف متلاشية، وانعكاس عند طرفي المقطع
    static func vocals(model: Runner, _ lch: [Float], _ rch: [Float], overlap: Overlap, chunks: inout Int,
                       progress: @escaping (Double) -> Void) async throws -> ([Float], [Float]) {
        let n = lch.count
        let fade = chunk / 10
        // الحواف: القطع تتداخل بطول التلاشي فقط (مجموع النافذتين ١)، النصف: كما في البرنامج الأصلي
        let step = overlap == .half ? chunk / 2 : chunk - fade
        let border = chunk - step
        // الحشو بالانعكاس كي تأخذ الأطراف تغطية كاملة (بلا نسخ المقطع: قراءة مباشرة بالانعكاس)
        let padded = n > 2 * border
        let off = padded ? border : 0
        let len = n + 2 * off
        @inline(__always) func at(_ x: [Float], _ i: Int) -> Float {
            var j = i - off
            if j < 0 { j = -j }
            if j >= n { j = 2 * (n - 1) - j }
            return j >= 0 && j < n ? x[j] : 0
        }
        var win = [Float](repeating: 1, count: chunk)
        for i in 0..<fade { win[i] = Float(i) / Float(fade - 1); win[chunk - 1 - i] = Float(i) / Float(fade - 1) }
        var accL = [Float](repeating: 0, count: len), accR = accL, cnt = accL

        let stft = STFT()
        var starts: [Int] = []
        var i = 0
        while i < len { starts.append(i); i += step }
        chunks = starts.count
        for (ci, s) in starts.enumerated() {
            try Task.checkCancellation()
            let length = min(chunk, len - s)
            // القطعة (الأخيرة تُكمل بالانعكاس أو بالأصفار)
            var pl = [Float](repeating: 0, count: chunk), pr = pl
            for k in 0..<length { pl[k] = at(lch, s + k); pr[k] = at(rch, s + k) }
            if length < chunk && length > chunk / 2 + 1 {
                for k in length..<chunk { let j = 2 * (length - 1) - k; if j >= 0 { pl[k] = pl[j]; pr[k] = pr[j] } }
            }
            let (yl, yr) = try await separateChunk(model: model, stft: stft, pl, pr)
            var w = win
            if s == 0 { for k in 0..<fade { w[k] = 1 } }
            if s + chunk >= len { for k in 0..<fade { w[chunk - 1 - k] = 1 } }
            for k in 0..<length {
                accL[s + k] += yl[k] * w[k]; accR[s + k] += yr[k] * w[k]; cnt[s + k] += w[k]
            }
            progress(Double(ci + 1) / Double(starts.count))
        }
        var outL = [Float](repeating: 0, count: n), outR = outL
        for k in 0..<n {
            let c = cnt[off + k]
            if c > 1e-6 { outL[k] = accL[off + k] / c; outR[k] = accR[off + k] / c }
        }
        return (outL, outR)
    }

    /// قطعة واحدة (٨ ثوانٍ): STFT ← النموذج ← قناع مركّب ← iSTFT
    static func separateChunk(model: Runner, stft: STFT, _ l: [Float], _ r: [Float]) async throws -> ([Float], [Float]) {
        let input = try MLMultiArray(shape: [1, NSNumber(value: 2 * bins), NSNumber(value: frames), 2], dataType: .float32)
        let ip = input.dataPointer.bindMemory(to: Float.self, capacity: 2 * bins * frames * 2)
        // الطيف لكل قناة: [frames][bins] حقيقي/تخيلي
        let sl = stft.forward(l), sr = stft.forward(r)
        for (s, sp) in [sl, sr].enumerated() {
            for t in 0..<frames {
                for f in 0..<bins {
                    let fs = f * 2 + s
                    let o = (fs * frames + t) * 2
                    ip[o] = sp.re[t * bins + f]; ip[o + 1] = sp.im[t * bins + f]
                }
            }
        }
        let out = try await model.predict(MLDictionaryFeatureProvider(dictionary: ["spec": input]))
        guard let m = out.featureValue(for: "mask")?.multiArrayValue, m.count >= 2 * bins * frames * 2 else {
            throw ToolError.failed(L("تعذّرت المعالجة."))
        }
        let total = 2 * bins * frames * 2
        var mask = [Float](repeating: 0, count: total)
        if m.dataType == .float16 {
            let p = m.dataPointer.bindMemory(to: Float16.self, capacity: total)
            for k in 0..<total { mask[k] = Float(p[k]) }
        } else {
            let p = m.dataPointer.bindMemory(to: Float.self, capacity: total)
            for k in 0..<total { mask[k] = p[k] }
        }
        var res: [[Float]] = []
        for (s, sp) in [sl, sr].enumerated() {
            var yr = [Float](repeating: 0, count: bins * frames), yi = yr
            for t in 0..<frames {
                for f in 1..<bins {     // DC = صفر (كما في النموذج الأصلي)
                    let o = ((f * 2 + s) * frames + t) * 2
                    let a = sp.re[t * bins + f], b = sp.im[t * bins + f], c = mask[o], d = mask[o + 1]
                    yr[t * bins + f] = a * c - b * d
                    yi[t * bins + f] = a * d + b * c
                }
            }
            res.append(stft.inverse(re: yr, im: yi, length: chunk))
        }
        return (res[0], res[1])
    }

    /// النموذج على المحرك العصبي وكرت الشاشة (الأسرع)، وبدائل تلقائية لكل قطعة:
    /// iOS يمنع كرت الشاشة حين يخرج المستخدم من التطبيق (رسالة «Unable to compute…»)، فتُعاد القطعة نفسها
    /// على كرت الشاشة ثم المعالج العادي ويكمل الفصل
    final class Runner {
        private var tiers: [(units: MLComputeUnits, model: MLModel?)] = [(.all, nil), (.cpuAndGPU, nil), (.cpuOnly, nil)]
        /// عدد القطع التي احتاجت بديلًا (للتشخيص)
        private(set) var fallbacks = 0
        /// بدائل جُرّب تحميلها (لا يُعاد التحميل المكلف مع كل قطعة)
        private var tried: Set<Int> = []

        static func make() async throws -> Runner {
            let r = Runner()
            if UserDefaults.standard.string(forKey: "sepmodel.plan") == nil, let p = await planSummary() {
                UserDefaults.standard.set(p, forKey: "sepmodel.plan")
                await MainActor.run { SepModelStore.shared.planSummary = p }
            }
            for k in r.tiers.indices {
                r.tried.insert(k)
                if let m = try? await load(r.tiers[k].units) { r.tiers[k].model = m; return r }
            }
            throw ToolError.failed(L("تعذّرت المعالجة."))
        }

        private static func load(_ units: MLComputeUnits) async throws -> MLModel {
            let cfg = MLModelConfiguration(); cfg.computeUnits = units
            return try await MLModel.load(contentsOf: SepModelStore.compiledURL, configuration: cfg)
        }

        func predict(_ input: MLFeatureProvider) async throws -> MLFeatureProvider {
            // كل قطعة تبدأ بالأسرع (قد يعود المستخدم للتطبيق)، وعند الفشل تنتقل للبديل التالي
            for k in tiers.indices {
                if tiers[k].model == nil && !tried.contains(k) {
                    tried.insert(k)
                    tiers[k].model = try? await Self.load(tiers[k].units)
                }
                guard let m = tiers[k].model else { continue }
                do {
                    let out = try await m.prediction(from: input)
                    if k > 0 && tiers[0].model != nil { fallbacks += 1 }
                    return out
                } catch {
                    try Task.checkCancellation()
                }
            }
            throw ToolError.failed(L("تعذّرت المعالجة. أبقِ التطبيق مفتوحًا أثناء الفصل وحاول مرة أخرى."))
        }

        /// بعد التنزيل: تحميل على المحرك العصبي وتنبؤ واحد (تجهيز يحفظه النظام)، وحساب أين يعمل كل جزء من النموذج
        static func warmUp() async {
            if let m = try? await load(.all),
               let input = try? MLMultiArray(shape: [1, NSNumber(value: 2 * bins), NSNumber(value: frames), 2], dataType: .float32) {
                _ = try? await m.prediction(from: MLDictionaryFeatureProvider(dictionary: ["spec": input]))
            }
            let summary = await planSummary()
            UserDefaults.standard.set(summary, forKey: "sepmodel.plan")
            await MainActor.run { SepModelStore.shared.planSummary = summary }
        }

        /// «المحرك العصبي ٩٥٪ · كرت الشاشة ٥٪» حسب الكلفة التقديرية لكل عملية
        static func planSummary() async -> String? {
            guard #available(iOS 17.4, *) else { return nil }
            let cfg = MLModelConfiguration(); cfg.computeUnits = .all
            guard let plan = try? await MLComputePlan.load(contentsOf: SepModelStore.compiledURL, configuration: cfg),
                  case .program(let program) = plan.modelStructure,
                  let main = program.functions["main"] else { return nil }
            var ane = 0.0, gpu = 0.0, cpu = 0.0
            for op in main.block.operations {
                guard let use = plan.deviceUsage(for: op) else { continue }
                let w = plan.estimatedCost(of: op)?.weight ?? 0
                switch use.preferred {
                case .neuralEngine: ane += w
                case .gpu: gpu += w
                case .cpu: cpu += w
                @unknown default: cpu += w
                }
            }
            let total = ane + gpu + cpu
            guard total > 0 else { return nil }
            var parts: [String] = []
            for (name, v) in [(L("المحرك العصبي"), ane), (L("كرت الشاشة"), gpu), (L("المعالج"), cpu)] where v / total >= 0.01 {
                parts.append("\(name) \(ar(Int((100 * v / total).rounded())))٪")
            }
            return parts.joined(separator: " · ")
        }
    }

    /// STFT/iSTFT مطابقان لـ torch (center=True بانعكاس، نافذة Hann دورية، بلا تطبيع)
    final class STFT {
        let fwd: vDSP_DFT_Setup, inv: vDSP_DFT_Setup
        let win: [Float]
        let scale: Float
        init() {
            fwd = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(nfft), .FORWARD)!
            inv = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(nfft), .INVERSE)!
            win = (0..<nfft).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(nfft))) }
            // معامل الرجوع للإشارة بعد تحويل ذهابًا وإيابًا (اصطلاح vDSP)
            var x = [Float](repeating: 0, count: nfft)
            for i in 0..<nfft { x[i] = Float(sin(Double(i) * 0.37) + 0.5 * cos(Double(i) * 1.3)) }
            var re = [Float](repeating: 0, count: nfft / 2), im = re, y = x
            STFT.dft(fwd, x, &re, &im)
            STFT.idft(inv, re, im, &y)
            var num: Float = 0, den: Float = 0
            for i in 0..<nfft { num += x[i] * x[i]; den += x[i] * y[i] }
            scale = den != 0 ? num / den : 1
        }
        deinit { vDSP_DFT_DestroySetup(fwd); vDSP_DFT_DestroySetup(inv) }

        static func dft(_ s: vDSP_DFT_Setup, _ x: [Float], _ re: inout [Float], _ im: inout [Float]) {
            let half = nfft / 2
            var er = [Float](repeating: 0, count: half), ei = er
            for k in 0..<half { er[k] = x[2 * k]; ei[k] = x[2 * k + 1] }
            vDSP_DFT_Execute(s, er, ei, &re, &im)
        }
        static func idft(_ s: vDSP_DFT_Setup, _ re: [Float], _ im: [Float], _ x: inout [Float]) {
            let half = nfft / 2
            var orr = [Float](repeating: 0, count: half), oi = orr
            vDSP_DFT_Execute(s, re, im, &orr, &oi)
            for k in 0..<half { x[2 * k] = orr[k]; x[2 * k + 1] = oi[k] }
        }

        /// الطيف: re/im بحجم frames × bins (القيمة الحقيقية لتحويل فورييه، كما في torch.stft)
        func forward(_ x: [Float]) -> (re: [Float], im: [Float]) {
            let n = x.count, half = nfft / 2
            var re = [Float](repeating: 0, count: frames * bins), im = re
            var buf = [Float](repeating: 0, count: nfft)
            var pr = [Float](repeating: 0, count: half), pi = pr
            for t in 0..<frames {
                let start = t * hop - half
                for i in 0..<nfft {
                    var j = start + i
                    if j < 0 { j = -j }
                    if j >= n { j = 2 * (n - 1) - j }
                    buf[i] = (j >= 0 && j < n ? x[j] : 0) * win[i]
                }
                STFT.dft(fwd, buf, &pr, &pi)
                // vDSP يعطي ضعف القيمة، والمكان ٠ يحمل DC (حقيقي) و Nyquist (في التخيلي)
                re[t * bins] = pr[0] / 2
                im[t * bins] = 0
                re[t * bins + half] = pi[0] / 2
                im[t * bins + half] = 0
                for k in 1..<half { re[t * bins + k] = pr[k] / 2; im[t * bins + k] = pi[k] / 2 }
            }
            return (re, im)
        }

        /// العكس مع قسمة مجموع مربعات النافذة (كما في torch.istft)
        func inverse(re: [Float], im: [Float], length: Int) -> [Float] {
            let half = nfft / 2
            let total = nfft + hop * (frames - 1)
            var acc = [Float](repeating: 0, count: total), ws = acc
            var pr = [Float](repeating: 0, count: half), pi = pr, y = [Float](repeating: 0, count: nfft)
            for t in 0..<frames {
                pr[0] = re[t * bins] * 2
                pi[0] = re[t * bins + half] * 2
                for k in 1..<half { pr[k] = re[t * bins + k] * 2; pi[k] = im[t * bins + k] * 2 }
                STFT.idft(inv, pr, pi, &y)
                let s = t * hop
                for i in 0..<nfft {
                    acc[s + i] += y[i] * scale * win[i]
                    ws[s + i] += win[i] * win[i]
                }
            }
            var out = [Float](repeating: 0, count: length)
            for i in 0..<length {
                let j = i + half
                if j < total, ws[j] > 1e-8 { out[i] = acc[j] / ws[j] }
            }
            return out
        }
    }
}
