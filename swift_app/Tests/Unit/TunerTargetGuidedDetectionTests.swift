import XCTest
@testable import Core
@testable import Tuner

/// PR2 新增：目标优先窗口 + 连续帧一致性过滤 的回归。
///
/// 1. 合成一段「基频 + 强 2× 倍频」的信号，验证调音器 preset 设置目标 Hz 后，
///    最终检出频率应**接近基频**而非被 2× 分量带到高八度。
/// 2. VM 层的 `acceptSample` 在孤立八度跳变时先挂候选、连续两帧相同才采纳。
final class TunerTargetGuidedDetectionTests: XCTestCase {
    // MARK: - Offline pitch estimation against synthetic signals

    /// 纯基频正弦：tunerGuitar preset 应能在 E2 上给出 <5 cent 的精度。
    func testPureSineAtE2IsDetectedAccuratelyByTunerPreset() {
        let sr = 44_100.0
        let f0 = 82.41
        let frame = synthesizeSine(frequency: f0, sampleRate: sr, seconds: 0.3, amplitude: 0.3)
        let hz = estimate(samples: frame, sampleRate: sr, targetHz: nil)
        guard let hz else {
            XCTFail("纯基频信号应被识别")
            return
        }
        let centsDiff = abs(1200.0 * log2(hz / f0))
        XCTAssertLessThan(centsDiff, 5, "纯 E2 应在 5 cent 内识别，实测 \(centsDiff) cent")
    }

    /// 目标优先窗口对"基频 + 较强 2× 分量"的复合信号，能够稳定输出基频而非倍频。
    /// 这是工程上的防御性测试：即便朴素自相关在边界情况下选错，窗口也会兜住。
    func testTargetWindowLocksOntoFundamentalWithStrongSecondHarmonic() {
        let sr = 44_100.0
        let f0 = 82.41
        let frame = synthesizeHarmonicBiased(fundamental: f0, sampleRate: sr, seconds: 0.3)
        let hz = estimate(samples: frame, sampleRate: sr, targetHz: f0)
        guard let hz else {
            XCTFail("含倍频的信号应被识别")
            return
        }
        let centsDiff = abs(1200.0 * log2(hz / f0))
        XCTAssertLessThan(centsDiff, 50, "目标窗内应稳定指向基频，实测差 \(centsDiff) cent")
    }

    // MARK: - Consistency filter

    @MainActor
    func testIsolatedOctaveJumpIsRejectedByConsistencyFilter() async throws {
        let vm = TunerViewModel(audio: NoopAudioEngine(), detector: NoopPitchDetector())
        vm.setSelectedString(0) // 低 E
        let stableHz = 82.41
        vm.updateFrequencySample(stableHz)
        for _ in 0..<10 {
            vm.updateFrequencySample(stableHz)
        }
        let centsBefore = vm.cents
        // 单帧跳到高八度（164.82Hz，相对 82.41Hz 约 +1200 cent）：
        // 应被一致性过滤器视为孤立跳变，不更新 `frequencyHz`，也不影响显示 cents。
        vm.updateFrequencySample(164.82)
        let hz = try XCTUnwrap(vm.frequencyHz, "应已有稳定基频；孤立跳后仍保留原值。")
        XCTAssertEqual(hz, stableHz, accuracy: 1e-6, "孤立八度跳应被连续帧过滤器拦截")
        XCTAssertEqual(vm.cents, centsBefore, accuracy: 1e-6, "被拦截帧不应影响 cents 显示")
    }

    @MainActor
    func testTwoConsecutiveLargeJumpsAreAccepted() async {
        let vm = TunerViewModel(audio: NoopAudioEngine(), detector: NoopPitchDetector())
        vm.setSelectedString(2) // D3 (146.83)
        vm.updateFrequencySample(146.83)
        for _ in 0..<5 {
            vm.updateFrequencySample(146.83)
        }
        // 连续两帧都跳到 196Hz（G3，约 +498 cent）：视为用户真的换了一根弦拨，应被接纳。
        vm.updateFrequencySample(196)
        vm.updateFrequencySample(196)
        XCTAssertEqual(vm.frequencyHz ?? 0, 196, accuracy: 1e-6, "连续两帧远离旧值的同簇样本应被接纳")
    }

    @MainActor
    func testViewModelForwardsSelectedStringTargetToDetector() async {
        let recorder = TargetRecordingDetector()
        let vm = TunerViewModel(audio: NoopAudioEngine(), detector: recorder)
        XCTAssertNil(recorder.lastTarget)
        vm.setSelectedString(0)
        XCTAssertEqual(recorder.lastTarget ?? 0, 82.41, accuracy: 1e-6)
        vm.setSelectedString(5)
        XCTAssertEqual(recorder.lastTarget ?? 0, 329.63, accuracy: 1e-6)
    }

    // MARK: - Helpers

    /// 合成一段基频 + 强 2× 倍频的信号：2× 分量幅度 1.8 倍于基频。
    private func synthesizeHarmonicBiased(fundamental f0: Double, sampleRate sr: Double, seconds: Double) -> [Float] {
        let n = Int(sr * seconds)
        var out = [Float](repeating: 0, count: n)
        let twoPi = 2 * Double.pi
        for i in 0..<n {
            let t = Double(i) / sr
            let s = sin(twoPi * f0 * t) + 1.8 * sin(twoPi * 2 * f0 * t + 0.3)
            out[i] = Float(s * 0.25)
        }
        return out
    }

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

    /// 用离线估计入口跑一帧并解包为 Hz（方便断言）。
    private func estimate(samples: [Float], sampleRate: Double, targetHz: Double?) -> Double? {
        let result = TunerPitchEstimator.estimate(
            samples: samples,
            sampleRate: sampleRate,
            config: .tunerGuitar,
            targetHz: targetHz
        )
        if case let .pitch(hz, _, _) = result { return hz }
        return nil
    }
}

private final class NoopAudioEngine: AudioEngineServing {
    let quality = AudioQualityBaseline()
    var isSampledGuitarAvailable: Bool = false
    func start() throws {}
    func stop() {}
    func playSine(frequencyHz: Double, durationSec: Double) throws {}
    func playPluckedGuitarString(frequencyHz: Double, durationSec: Double) throws {}
    func playSampledGuitarNote(midi: Int, velocity: UInt8, gateDurationSec: Double) throws {}
    func playSampledGuitarChord(
        midis: [Int],
        velocity: UInt8,
        gateDurationSec: Double,
        stringStaggerSec: Double
    ) throws {}
    func stopSampledGuitarNotes(midis: [Int]) {}
    func stopAllSampledGuitarNotes() {}
    func stopPluckedGuitarVoices() {}
}

private final class NoopPitchDetector: PitchDetecting {
    func start(callback: @escaping (PitchFrameResult) -> Void) throws {}
    func stop() {}
}

private final class TargetRecordingDetector: PitchDetecting {
    var lastTarget: Double?
    func start(callback: @escaping (PitchFrameResult) -> Void) throws {}
    func stop() {}
    func setTargetHz(_ hz: Double?) { lastTarget = hz }
}
