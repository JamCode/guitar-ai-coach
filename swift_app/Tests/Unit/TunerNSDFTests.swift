import XCTest
@testable import Core

/// PR3 新增：NSDF / McLeod Pitch Method 的回归。
///
/// 算法侧重点是"消除八度错"：对吉他常见的"基频较弱 + 2×/3× 谐波较强"场景，
/// 朴素自相关会把峰落在 2T/3T，而 NSDF + 首个过阈值局部极大值应锁定在 1T。
final class TunerNSDFTests: XCTestCase {
    // MARK: - Basic accuracy

    func testNSDFDetectsPureSineE2() {
        let sr = 44_100.0
        let f0 = 82.41
        let frame = synthesizeSine(frequency: f0, sampleRate: sr, seconds: 0.3, amplitude: 0.3)
        guard let hz = detectWith(.tunerGuitar, samples: frame, sampleRate: sr, target: nil) else {
            XCTFail("NSDF 应识别纯 E2 正弦")
            return
        }
        XCTAssertLessThan(abs(centsDiff(hz, f0)), 5)
    }

    func testNSDFDetectsPureSineE4() {
        let sr = 44_100.0
        let f0 = 329.63
        let frame = synthesizeSine(frequency: f0, sampleRate: sr, seconds: 0.3, amplitude: 0.3)
        guard let hz = detectWith(.tunerGuitar, samples: frame, sampleRate: sr, target: nil) else {
            XCTFail("NSDF 应识别纯 E4 正弦")
            return
        }
        XCTAssertLessThan(abs(centsDiff(hz, f0)), 5)
    }

    // MARK: - Octave-error rejection

    /// 关键验证：在"基频 + 强 2× 谐波（2 倍幅度）"的信号上，朴素自相关可能把峰选在 2T 处（高八度），
    /// NSDF + clarity 阈值应稳定锁定在 1T（基频）。
    func testNSDFRejectsOctaveErrorOnRichHarmonicE2() {
        let sr = 44_100.0
        let f0 = 82.41
        let frame = synthesizeHarmonicRich(fundamental: f0, sampleRate: sr, seconds: 0.3, secondHarmonicAmp: 2.0)
        guard let hz = detectWith(.tunerGuitar, samples: frame, sampleRate: sr, target: nil) else {
            XCTFail("NSDF 应识别出复合谐波信号的基频")
            return
        }
        let toFundamental = abs(centsDiff(hz, f0))
        let toOctave = abs(centsDiff(hz, 2 * f0))
        XCTAssertLessThan(toFundamental, 60, "NSDF 应锁定 E2 基频（差 \(toFundamental) cent）")
        XCTAssertGreaterThan(toOctave, 600, "不应被强 2× 谐波带到高八度（差 \(toOctave) cent）")
    }

    /// 无目标 + 复合谐波 A2：确保 clarity 阈值 0.9 能稳定兜住八度错；
    /// 补一个目标优先的情形（设目标 f0 加窗），估计误差应更小。
    func testNSDFWithTargetWindowTightenA2HarmonicEstimate() {
        let sr = 44_100.0
        let f0 = 110.0
        let frame = synthesizeHarmonicRich(fundamental: f0, sampleRate: sr, seconds: 0.3, secondHarmonicAmp: 1.6, thirdHarmonicAmp: 1.2)
        guard let hz = detectWith(.tunerGuitar, samples: frame, sampleRate: sr, target: f0) else {
            XCTFail("NSDF 应识别出 A2 基频")
            return
        }
        XCTAssertLessThan(abs(centsDiff(hz, f0)), 30)
    }

    // MARK: - Legacy autocorrelation unchanged

    /// 回归保护：`sightSinging` preset 仍走自相关分支，结果不应因 NSDF 引入而退化。
    func testAutocorrelationBranchStillWorksForSightSingingPreset() {
        let sr = 44_100.0
        let f0 = 220.0 // A3
        let frame = synthesizeSine(frequency: f0, sampleRate: sr, seconds: 0.3, amplitude: 0.3)
        guard let hz = detectWith(.sightSinging, samples: frame, sampleRate: sr, target: nil) else {
            XCTFail("自相关分支应识别 A3 正弦")
            return
        }
        XCTAssertLessThan(abs(centsDiff(hz, f0)), 10)
    }

    // MARK: - Helpers

    private func synthesizeSine(frequency: Double, sampleRate: Double, seconds: Double, amplitude: Double) -> [Float] {
        let n = Int(sampleRate * seconds)
        var out = [Float](repeating: 0, count: n)
        let twoPi = 2 * Double.pi
        for i in 0..<n {
            let t = Double(i) / sampleRate
            out[i] = Float(amplitude * sin(twoPi * frequency * t))
        }
        return out
    }

    private func synthesizeHarmonicRich(
        fundamental f0: Double,
        sampleRate sr: Double,
        seconds: Double,
        secondHarmonicAmp a2: Double = 1.5,
        thirdHarmonicAmp a3: Double = 0.0
    ) -> [Float] {
        let n = Int(sr * seconds)
        var out = [Float](repeating: 0, count: n)
        let twoPi = 2 * Double.pi
        for i in 0..<n {
            let t = Double(i) / sr
            var s = sin(twoPi * f0 * t)
            s += a2 * sin(twoPi * 2 * f0 * t + 0.3)
            if a3 > 0 { s += a3 * sin(twoPi * 3 * f0 * t + 0.7) }
            out[i] = Float(s * 0.2)
        }
        return out
    }

    private func detectWith(_ config: PitchDetectorConfig, samples: [Float], sampleRate: Double, target: Double?) -> Double? {
        let result = TunerPitchEstimator.estimate(samples: samples, sampleRate: sampleRate, config: config, targetHz: target)
        if case let .pitch(hz, _, _) = result { return hz }
        return nil
    }

    private func centsDiff(_ a: Double, _ b: Double) -> Double {
        1200.0 * log2(a / b)
    }
}
