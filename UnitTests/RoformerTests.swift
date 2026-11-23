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
