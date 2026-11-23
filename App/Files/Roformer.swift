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
    @Published var planSummary: String? = UserDefaults.standard.string(forKey: SepModelStore.planKey)
    /// مفتاح جديد: الخطة السابقة كانت للمحرك العصبي
    nonisolated static let planKey = "sepmodel.plan.gpu"
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
        vDSP_vsub(vl, 1, lch, 1, &ml, 1, vDSP_Length(n))     // ml = lch − vl
        vDSP_vsub(vr, 1, rch, 1, &mr, 1, vDSP_Length(n))
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
        report += " " + LF("النموذج وحده %@ ثانية لكل جزء.", ar(String(format: "%.1f", model.modelSeconds / Double(max(1, chunks)))))
        if let plan { report += " " + LF("يعمل على: %@.", plan) }
        if model.fallbacks > 0 { report += " " + LF("%@ من الأجزاء عملت على بديل أبطأ (خرجت من التطبيق؟).", ar(model.fallbacks)) }
        let finalReport = report
        await MainActor.run { lastReport = finalReport }
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
        var win = [Float](repeating: 1, count: chunk)
        for i in 0..<fade { win[i] = Float(i) / Float(fade - 1); win[chunk - 1 - i] = Float(i) / Float(fade - 1) }
        let acc = Accum(len: len)
        let src = Source(l: lch, r: rch, off: off)
        var starts: [Int] = []
        var i = 0
        while i < len { starts.append(i); i += step }
        chunks = starts.count
        let total = starts.count

        // خط إنتاج: المعالج يجهّز القطعة التالية ويُنهي السابقة بينما كرت الشاشة يعمل على الحالية.
        // الحساب نفسه بالضبط وبالترتيب نفسه؛ فقط لا ينتظر كرت الشاشة المعالج.
        func prepare(_ ci: Int) -> Task<Prepared, Error> {
            let s0 = starts[ci]
            return Task.detached(priority: .userInitiated) { try Prepared.make(src, start: s0, len: len) }
        }
        var next: Task<Prepared, Error>? = prepare(0)
        var finishing: Task<Void, Error>?
        defer { next?.cancel(); finishing?.cancel() }
        for ci in 0..<total {
            try Task.checkCancellation()
            guard let p = try await next?.value else { break }
            next = ci + 1 < total ? prepare(ci + 1) : nil
            let out = try await model.predict(MLDictionaryFeatureProvider(dictionary: ["spec": p.input]))
            guard let m = out.featureValue(for: "mask")?.multiArrayValue else { throw ToolError.failed(L("تعذّرت المعالجة.")) }
            let mask = try MaskBuffer(m)
            let s0 = starts[ci], length = p.length
            var w = win
            if s0 == 0 { for k in 0..<fade { w[k] = 1 } }
            if s0 + chunk >= len { for k in 0..<fade { w[chunk - 1 - k] = 1 } }
            let weights = w
            let prev = finishing
            finishing = Task.detached(priority: .userInitiated) {
                let yl = FastSTFT.shared.synthesize(spec: p.spec, mask: mask.values, channel: 0)
                let yr = FastSTFT.shared.synthesize(spec: p.spec, mask: mask.values, channel: 1)
                try await prev?.value          // الجمع بالترتيب
                acc.add(yl, yr, at: s0, length: length, weights: weights)
            }
            progress(Double(ci + 1) / Double(total))
        }
        try await finishing?.value
        finishing = nil
        var outL = [Float](repeating: 0, count: n), outR = outL
        for k in 0..<n {
            let c = acc.cnt[off + k]
            if c > 1e-6 { outL[k] = acc.l[off + k] / c; outR[k] = acc.r[off + k] / c }
        }
        return (outL, outR)
    }

    /// المقطع مع الحشو بالانعكاس (قراءة فقط، من عدة مهام)
    final class Source: @unchecked Sendable {
        let l: [Float], r: [Float], off: Int, n: Int
        init(l: [Float], r: [Float], off: Int) { self.l = l; self.r = r; self.off = off; n = l.count }
        @inline(__always) func index(_ i: Int) -> Int {
            var j = i - off
            if j < 0 { j = -j }
            if j >= n { j = 2 * (n - 1) - j }
            return j
        }
    }

    /// مجمّع الناتج (تُضاف إليه القطع بالترتيب، واحدة بعد واحدة)
    final class Accum: @unchecked Sendable {
        var l: [Float], r: [Float], cnt: [Float]
        init(len: Int) { l = [Float](repeating: 0, count: len); r = l; cnt = l }
        func add(_ yl: [Float], _ yr: [Float], at s: Int, length: Int, weights w: [Float]) {
            let n = vDSP_Length(length)
            l.withUnsafeMutableBufferPointer { lp in
                vDSP_vma(yl, 1, w, 1, lp.baseAddress! + s, 1, lp.baseAddress! + s, 1, n)
            }
            r.withUnsafeMutableBufferPointer { rp in
                vDSP_vma(yr, 1, w, 1, rp.baseAddress! + s, 1, rp.baseAddress! + s, 1, n)
            }
            cnt.withUnsafeMutableBufferPointer { cp in
                vDSP_vadd(cp.baseAddress! + s, 1, w, 1, cp.baseAddress! + s, 1, n)
            }
        }
    }

    /// قطعة جاهزة للنموذج: الطيف في دخل النموذج نفسه (يُقرأ لاحقًا لضرب القناع)
    final class Prepared: @unchecked Sendable {
        let input: MLMultiArray
        let length: Int
        var spec: UnsafePointer<Float> { UnsafePointer(input.dataPointer.assumingMemoryBound(to: Float.self)) }
        private init(input: MLMultiArray, length: Int) { self.input = input; self.length = length }

        static func make(_ src: Source, start s: Int, len: Int) throws -> Prepared {
            try Task.checkCancellation()
            let length = min(chunk, len - s)
            // القطعة (الأخيرة تُكمل بالانعكاس أو بالأصفار)
            var pl = [Float](repeating: 0, count: chunk), pr = pl
            for k in 0..<length {
                let j = src.index(s + k)
                if j >= 0 && j < src.n { pl[k] = src.l[j]; pr[k] = src.r[j] }
            }
            if length < chunk && length > chunk / 2 + 1 {
                for k in length..<chunk { let j = 2 * (length - 1) - k; if j >= 0 { pl[k] = pl[j]; pr[k] = pr[j] } }
            }
            let input = try MLMultiArray(shape: [1, NSNumber(value: 2 * bins), NSNumber(value: frames), 2], dataType: .float32)
            let ip = input.dataPointer.bindMemory(to: Float.self, capacity: 2 * bins * frames * 2)
            pl.withUnsafeBufferPointer { FastSTFT.shared.analyze($0.baseAddress!, n: chunk, channel: 0, into: ip) }
            pr.withUnsafeBufferPointer { FastSTFT.shared.analyze($0.baseAddress!, n: chunk, channel: 1, into: ip) }
            return Prepared(input: input, length: length)
        }
    }

    /// قناع النموذج في مصفوفة متصلة Float (يحترم خطوات الذاكرة إن أرجعها كرت الشاشة بحشو)
    final class MaskBuffer: @unchecked Sendable {
        private let ptr: UnsafeMutablePointer<Float>
        var values: UnsafePointer<Float> { UnsafePointer(ptr) }
        deinit { ptr.deallocate() }
        init(_ m: MLMultiArray) throws {
            let total = 2 * bins * frames * 2
            guard m.count >= total, m.shape.count == 4 else { throw ToolError.failed(L("تعذّرت المعالجة.")) }
            let shape = m.shape.map(\.intValue), st = m.strides.map(\.intValue)
            let contiguous = st == [shape[1] * shape[2] * shape[3], shape[2] * shape[3], shape[3], 1]
            let out = UnsafeMutablePointer<Float>.allocate(capacity: total)
            switch (m.dataType, contiguous) {
            case (.float32, true):
                let p = m.dataPointer.bindMemory(to: Float.self, capacity: total)
                out.update(from: p, count: total)
            case (.float16, true):
                let p = m.dataPointer.bindMemory(to: Float16.self, capacity: total)
                for k in 0..<total { out[k] = Float(p[k]) }
            default:
                let f32 = m.dataType == .float32
                let p32 = m.dataPointer.assumingMemoryBound(to: Float.self)
                let p16 = m.dataPointer.assumingMemoryBound(to: Float16.self)
                var k = 0
                for a in 0..<shape[1] { for b in 0..<shape[2] { for c in 0..<shape[3] {
                    let o = a * st[1] + b * st[2] + c * st[3]
                    out[k] = f32 ? p32[o] : Float(p16[o]); k += 1
                } } }
            }
            ptr = out
        }
    }

    /// STFT/iSTFT متجهة (vDSP) بنفس حساب STFT أدناه بالضبط، مكتوبة مباشرة في تخطيط دخل النموذج
    final class FastSTFT: @unchecked Sendable {
        static let shared = FastSTFT()
        let fwd: vDSP_DFT_Setup, inv: vDSP_DFT_Setup
        let win: [Float], winScaled: [Float], envInv: [Float]
        private init() {
            let ref = STFT()
            fwd = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(nfft), .FORWARD)!
            inv = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(nfft), .INVERSE)!
            win = ref.win
            winScaled = ref.win.map { $0 * ref.scale }
            // مجموع مربعات النافذة عبر الإطارات (ثابت)، مقلوبًا لمواضع الناتج
            let total = nfft + hop * (frames - 1)
            var ws = [Float](repeating: 0, count: total)
            for t in 0..<frames { for i in 0..<nfft { ws[t * hop + i] += ref.win[i] * ref.win[i] } }
            var e = [Float](repeating: 0, count: chunk)
            for i in 0..<chunk { let j = i + nfft / 2; if j < total, ws[j] > 1e-8 { e[i] = 1 / ws[j] } }
            envInv = e
        }

        /// طيف القناة s مكتوب في دخل النموذج [1, 2050, 801, 2] (التردد f والقناة s في الموضع f×2+s)
        func analyze(_ x: UnsafePointer<Float>, n: Int, channel s: Int, into ip: UnsafeMutablePointer<Float>) {
            let half = nfft / 2
            let frame = UnsafeMutablePointer<Float>.allocate(capacity: nfft)
            let er = UnsafeMutablePointer<Float>.allocate(capacity: half), ei = UnsafeMutablePointer<Float>.allocate(capacity: half)
            let orr = UnsafeMutablePointer<Float>.allocate(capacity: half), oi = UnsafeMutablePointer<Float>.allocate(capacity: half)
            defer { frame.deallocate(); er.deallocate(); ei.deallocate(); orr.deallocate(); oi.deallocate() }
            var split = DSPSplitComplex(realp: er, imagp: ei)
            let fStride = vDSP_Stride(4 * frames)
            var h: Float = 0.5
            for t in 0..<frames {
                let start = t * hop - half
                if start >= 0 && start + nfft <= n {
                    vDSP_vmul(x + start, 1, win, 1, frame, 1, vDSP_Length(nfft))
                } else {
                    for i in 0..<nfft {
                        var j = start + i
                        if j < 0 { j = -j }
                        if j >= n { j = 2 * (n - 1) - j }
                        frame[i] = (j >= 0 && j < n ? x[j] : 0) * win[i]
                    }
                }
                frame.withMemoryRebound(to: DSPComplex.self, capacity: half) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half)) }
                vDSP_DFT_Execute(fwd, er, ei, orr, oi)
                // vDSP يعطي ضعف القيمة، والمكان ٠ يحمل DC (حقيقي) و Nyquist (في التخيلي)
                let base = ip + (s * frames + t) * 2
                vDSP_vsmul(orr, 1, &h, base, fStride, vDSP_Length(half))
                vDSP_vsmul(oi, 1, &h, base + 1, fStride, vDSP_Length(half))
                base[1] = 0
                let nyq = ip + ((half * 2 + s) * frames + t) * 2
                nyq[0] = oi[0] * 0.5
                nyq[1] = 0
            }
        }

        /// Y = X × القناع (DC صفر كما في الأصل) ثم iSTFT مع قسمة مجموع مربعات النافذة: الناتج بطول القطعة
        func synthesize(spec ip: UnsafePointer<Float>, mask mp: UnsafePointer<Float>, channel s: Int) -> [Float] {
            let half = nfft / 2
            let total = nfft + hop * (frames - 1)
            let acc = UnsafeMutablePointer<Float>.allocate(capacity: total); acc.initialize(repeating: 0, count: total)
            let buf = UnsafeMutablePointer<Float>.allocate(capacity: 6 * bins + 4 * half + nfft)
            defer { acc.deallocate(); buf.deallocate() }
            let xr = buf, xi = buf + bins, mr = buf + 2 * bins, mi = buf + 3 * bins, yr = buf + 4 * bins, yi = buf + 5 * bins
            let pr = buf + 6 * bins, pi = pr + half, orr = pi + half, oi = orr + half, frame = oi + half
            var X = DSPSplitComplex(realp: xr, imagp: xi), M = DSPSplitComplex(realp: mr, imagp: mi)
            var Y = DSPSplitComplex(realp: yr, imagp: yi), O = DSPSplitComplex(realp: orr, imagp: oi)
            var two: Float = 2
            // خطوة vDSP_ctoz بعدد Float (٢ = أعداد مركّبة متتالية): بين ترددين متتاليين لنفس القناة والإطار ٤ × الإطارات
            let cStride = vDSP_Stride(4 * frames)
            for t in 0..<frames {
                let o = (s * frames + t) * 2
                (ip + o).withMemoryRebound(to: DSPComplex.self, capacity: 1) { vDSP_ctoz($0, cStride, &X, 1, vDSP_Length(bins)) }
                (mp + o).withMemoryRebound(to: DSPComplex.self, capacity: 1) { vDSP_ctoz($0, cStride, &M, 1, vDSP_Length(bins)) }
                vDSP_zvmul(&X, 1, &M, 1, &Y, 1, vDSP_Length(bins), 1)
                vDSP_vsmul(yr, 1, &two, pr, 1, vDSP_Length(half))
                vDSP_vsmul(yi, 1, &two, pi, 1, vDSP_Length(half))
                pr[0] = 0                     // DC = صفر
                pi[0] = yr[half] * 2          // Nyquist في مكان التخيلي للـ DC
                vDSP_DFT_Execute(inv, pr, pi, orr, oi)
                frame.withMemoryRebound(to: DSPComplex.self, capacity: half) { vDSP_ztoc(&O, 1, $0, 2, vDSP_Length(half)) }
                let a = acc + t * hop
                vDSP_vma(frame, 1, winScaled, 1, a, 1, a, 1, vDSP_Length(nfft))
            }
            var out = [Float](repeating: 0, count: chunk)
            vDSP_vmul(acc + half, 1, envInv, 1, &out, 1, vDSP_Length(chunk))
            return out
        }
    }

    /// النموذج على المحرك العصبي وكرت الشاشة (الأسرع)، وبدائل تلقائية لكل قطعة:
    /// iOS يمنع كرت الشاشة حين يخرج المستخدم من التطبيق (رسالة «Unable to compute…»)، فتُعاد القطعة نفسها
    /// على كرت الشاشة ثم المعالج العادي ويكمل الفصل
    final class Runner {
        // المحرك العصبي يقبل هذا النموذج في الخطة ثم يرفضه عند التشغيل (جُرّب على الجوال): كرت الشاشة مباشرة
        private var tiers: [(units: MLComputeUnits, model: MLModel?)] = [(.cpuAndGPU, nil), (.cpuOnly, nil)]
        /// وقت النموذج وحده (لفصله عن وقت التحويل الطيفي في التقرير)
        private(set) var modelSeconds = 0.0
        /// عدد القطع التي احتاجت بديلًا (للتشخيص)
        private(set) var fallbacks = 0
        /// بدائل جُرّب تحميلها (لا يُعاد التحميل المكلف مع كل قطعة)
        private var tried: Set<Int> = []

        static func make() async throws -> Runner {
            let r = Runner()
            if UserDefaults.standard.string(forKey: SepModelStore.planKey) == nil, let p = await planSummary() {
                UserDefaults.standard.set(p, forKey: SepModelStore.planKey)
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
                    let t = Date()
                    let out = try await m.prediction(from: input)
                    modelSeconds += Date().timeIntervalSince(t)
                    if k > 0 && tiers[0].model != nil { fallbacks += 1 }
                    return out
                } catch {
                    try Task.checkCancellation()
                }
            }
            throw ToolError.failed(L("تعذّرت المعالجة. أبقِ التطبيق مفتوحًا أثناء الفصل وحاول مرة أخرى."))
        }

        /// بعد التنزيل: حساب أين يعمل كل جزء من النموذج (بلا تجهيز طويل للمحرك العصبي)
        static func warmUp() async {
            let summary = await planSummary()
            UserDefaults.standard.set(summary, forKey: SepModelStore.planKey)
            await MainActor.run { SepModelStore.shared.planSummary = summary }
        }

        /// «كرت الشاشة ٩٥٪ · المعالج ٥٪ (gather ×٢٤ …)» حسب الكلفة التقديرية لكل عملية، مع أسماء ما ينزل على المعالج
        static func planSummary() async -> String? {
            guard #available(iOS 17.4, *) else { return nil }
            let cfg = MLModelConfiguration(); cfg.computeUnits = .cpuAndGPU
            guard let plan = try? await MLComputePlan.load(contentsOf: SepModelStore.compiledURL, configuration: cfg),
                  case .program(let program) = plan.modelStructure,
                  let main = program.functions["main"] else { return nil }
            var gpu = 0.0, cpu = 0.0, nGPU = 0, nCPU = 0
            var cpuOps: [String: (n: Int, w: Double)] = [:]
            for op in main.block.operations {
                guard let use = plan.deviceUsage(for: op) else { continue }
                let w = plan.estimatedCost(of: op)?.weight ?? 0
                switch use.preferred {
                case .gpu: gpu += w; nGPU += 1
                default:
                    cpu += w; nCPU += 1
                    let e = cpuOps[op.operatorName] ?? (0, 0)
                    cpuOps[op.operatorName] = (e.n + 1, e.w + w)
                }
            }
            let total = gpu + cpu
            var s = total > 0
                ? LF("كرت الشاشة %@٪ · المعالج %@٪", ar(Int((100 * gpu / total).rounded())), ar(Int((100 * cpu / total).rounded())))
                : LF("كرت الشاشة %@ عملية · المعالج %@ عملية", ar(nGPU), ar(nCPU))
            if !cpuOps.isEmpty {
                // أكثر ما ينزل على المعالج (بأسماء العمليات كما في Core ML) — لتحديد ما يُعاد كتابته
                let top = cpuOps.sorted { ($0.value.w, $0.value.n) > ($1.value.w, $1.value.n) }.prefix(5)
                    .map { "\($0.key)×\($0.value.n)" }.joined(separator: "، ")
                s += " (" + top + ")"
            }
            return s
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
