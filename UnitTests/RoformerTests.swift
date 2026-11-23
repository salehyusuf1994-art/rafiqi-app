import XCTest
@testable import Hilal

/// التحويل الطيفي للنموذج عالي الدقة يطابق torch.stft/istft
final class RoformerTests: XCTestCase {
    /// ذهاب وإياب بلا قناع يعيد الإشارة نفسها
    func testSTFTRoundTrip() {
        let n = Roformer.chunk
        var x = [Float](repeating: 0, count: n)
        var seed: UInt32 = 7
        for i in 0..<n {
            seed = seed &* 1664525 &+ 1013904223
            x[i] = 0.3 * Float(sin(Double(i) * 0.031)) + 0.1 * (Float(Int32(bitPattern: seed)) / Float(Int32.max))
        }
        let s = Roformer.STFT()
        let sp = s.forward(x)
        let y = s.inverse(re: sp.re, im: sp.im, length: n)
        var err: Float = 0
        for i in 0..<n { err = max(err, abs(x[i] - y[i])) }
        XCTAssertLessThan(err, 1e-3, "round trip error \(err)")
    }

    /// المقياس مطابق لـ torch: جيب تمام بسعة ١ على التردد k يعطي |X[k]| = مجموع النافذة ÷ ٢ = ٥١٢
    func testSTFTScaleMatchesTorch() {
        let n = Roformer.chunk, k0 = 100
        let x = (0..<n).map { Float(cos(2 * Double.pi * Double(k0) * Double($0) / Double(Roformer.nfft))) }
        let sp = Roformer.STFT().forward(x)
        let t = 400, b = Roformer.bins
        let mag = (sp.re[t * b + k0] * sp.re[t * b + k0] + sp.im[t * b + k0] * sp.im[t * b + k0]).squareRoot()
        XCTAssertEqual(mag, 512, accuracy: 1)
        XCTAssertEqual(sp.re[t * b + 300], 0, accuracy: 0.5)
    }

    /// المسار السريع (vDSP، في تخطيط دخل النموذج) يطابق المسار المرجعي بالضبط: الطيف، وضرب القناع، والعكس
    func testFastPathMatchesReference() {
        let n = Roformer.chunk, F = Roformer.frames, B = Roformer.bins
        var seed: UInt32 = 11
        func rnd() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(Int32(bitPattern: seed)) / Float(Int32.max) }
        let xl = (0..<n).map { i in 0.3 * Float(sin(Double(i) * 0.013)) + 0.05 * rnd() }
        let xr = (0..<n).map { i in 0.2 * Float(cos(Double(i) * 0.007)) + 0.05 * rnd() }
        var spec = [Float](repeating: 0, count: 2 * B * F * 2)
        spec.withUnsafeMutableBufferPointer { sp in
            xl.withUnsafeBufferPointer { Roformer.FastSTFT.shared.analyze($0.baseAddress!, n: n, channel: 0, into: sp.baseAddress!) }
            xr.withUnsafeBufferPointer { Roformer.FastSTFT.shared.analyze($0.baseAddress!, n: n, channel: 1, into: sp.baseAddress!) }
        }
        let ref = Roformer.STFT()
        let rl = ref.forward(xl), rr = ref.forward(xr)
        var specErr: Float = 0
        for (s, r) in [rl, rr].enumerated() {
            for t in stride(from: 0, to: F, by: 37) {
                for f in 0..<B {
                    let o = ((f * 2 + s) * F + t) * 2
                    specErr = max(specErr, abs(spec[o] - r.re[t * B + f]), abs(spec[o + 1] - r.im[t * B + f]))
                }
            }
        }
        XCTAssertLessThan(specErr, 1e-3, "spectrum mismatch \(specErr)")
        // قناع عشوائي: المسار السريع = المرجع (ضرب مركّب، DC صفر، iSTFT)
        let mask = (0..<spec.count).map { _ in rnd() }
        for (s, r) in [rl, rr].enumerated() {
            let fast = spec.withUnsafeBufferPointer { sp in mask.withUnsafeBufferPointer { mp in
                Roformer.FastSTFT.shared.synthesize(spec: sp.baseAddress!, mask: mp.baseAddress!, channel: s) } }
            var yr = [Float](repeating: 0, count: B * F), yi = yr
            for t in 0..<F { for f in 1..<B {
                let o = ((f * 2 + s) * F + t) * 2
                let a = r.re[t * B + f], b = r.im[t * B + f], c = mask[o], d = mask[o + 1]
                yr[t * B + f] = a * c - b * d; yi[t * B + f] = a * d + b * c
            } }
            let slow = ref.inverse(re: yr, im: yi, length: n)
            var err: Float = 0, mag: Float = 0
            for i in 0..<n { err = max(err, abs(fast[i] - slow[i])); mag = max(mag, abs(slow[i])) }
            XCTAssertLessThan(err, 1e-4 * max(1, mag), "synthesis mismatch \(err) (scale \(mag))")
        }
    }

    /// ملفات النموذج المنشورة: البصمات والأحجام مكتملة
    func testModelFilesDeclared() {
        XCTAssertEqual(SepModelFiles.parts.count, 3)
        for p in SepModelFiles.parts {
            XCTAssertEqual(p.sha256.count, 64)
            XCTAssertGreaterThan(p.size, 0)
        }
        XCTAssertGreaterThan(SepModelFiles.totalSize, 300_000_000)
    }
}
