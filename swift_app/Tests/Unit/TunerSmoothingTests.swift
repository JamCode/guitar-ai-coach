import XCTest
@testable import Core
@testable import Tuner

/// PR1 新增：调音器显示层平滑与滞回逻辑的最小回归。
///
/// 目标：
/// 1. `updateFrequencySample` 注入频率样本后，`cents` 会朝 raw 差值收敛，但不会一步到位（一阶低通）。
/// 2. `isInTune` 的开/关阈值不同（5 / 9 cent），形成滞回，避免临界反复切换。
/// 3. `MeterBar.normalizedPosition(for:)` 在 ±50 cent 边界外会被夹紧。
final class TunerSmoothingTests: XCTestCase {
    @MainActor
    func testCentsLowPassConvergesTowardsRawOffset() async {
        let vm = TunerViewModel(audio: NoopAudioEngine(), detector: NoopPitchDetector())
        vm.setSelectedString(0)
        guard let target = vm.targetHz else {
            XCTFail("target hz missing")
            return
        }
        let offsetCents = 30.0
        let hz = target * pow(2.0, offsetCents / 1200.0)
        // 第一帧注入后，一阶低通只能走 alpha 步长（约 9 cent），远未到位；
        // 这里验证单帧尚未收敛，多帧后才收敛，双向确认低通的存在。
        vm.updateFrequencySample(hz)
        XCTAssertLessThan(abs(vm.cents - offsetCents), offsetCents, "首帧应向目标靠拢但不能一步到位")
        XCTAssertGreaterThan(abs(vm.cents - offsetCents), 5, "首帧不应已经十分接近目标，否则说明低通过于激进")
        for _ in 0..<50 {
            vm.updateFrequencySample(hz)
        }
        XCTAssertEqual(vm.cents, offsetCents, accuracy: 0.5, "经过多帧采样后 cents 应逼近目标偏移")
        XCTAssertFalse(vm.isInTune, "30 cent 偏离不应判为已调准")
    }

    @MainActor
    func testInTuneHysteresisDoesNotChatterNearBoundary() async {
        let vm = TunerViewModel(audio: NoopAudioEngine(), detector: NoopPitchDetector())
        vm.setSelectedString(1)
        guard let target = vm.targetHz else {
            XCTFail("target hz missing")
            return
        }
        // 先把显示 cents 快速稳定在 +3 cent（进入"已调准"）
        let closeHz = target * pow(2.0, 3.0 / 1200.0)
        for _ in 0..<30 {
            vm.updateFrequencySample(closeHz)
        }
        XCTAssertTrue(vm.isInTune)
        // 再给一个 +7 cent 的漂移：在进入阈值 5 之外，但在退出阈值 9 之内，应保持「已调准」不切走。
        let driftedHz = target * pow(2.0, 7.0 / 1200.0)
        for _ in 0..<20 {
            vm.updateFrequencySample(driftedHz)
        }
        XCTAssertTrue(vm.isInTune, "7 cent 偏离仍在滞回退出阈内，不应退出已调准状态")
        // 继续飘到 +12 cent，超出退出阈 9 之外，应退出。
        let farHz = target * pow(2.0, 12.0 / 1200.0)
        for _ in 0..<20 {
            vm.updateFrequencySample(farHz)
        }
        XCTAssertFalse(vm.isInTune)
    }

    @MainActor
    func testSelectingNewStringClearsStaleSamplesAndState() async {
        let vm = TunerViewModel(audio: NoopAudioEngine(), detector: NoopPitchDetector())
        vm.setSelectedString(0)
        guard let firstTarget = vm.targetHz else {
            XCTFail("target hz missing")
            return
        }
        for _ in 0..<30 {
            vm.updateFrequencySample(firstTarget)
        }
        XCTAssertTrue(vm.isInTune)
        // 切到第 1 弦（index 5，E4）：旧 Hz 平滑状态必须被清掉，避免指针先向新目标猛甩。
        vm.setSelectedString(5)
        XCTAssertNil(vm.frequencyHz, "切弦时应立即清理旧频率样本")
        XCTAssertNil(vm.smoothedHz, "切弦时应立即清理旧频率平滑值")
        XCTAssertEqual(vm.cents, 0, accuracy: 1e-6, "无样本时 cents 应回到 0")
        XCTAssertFalse(vm.isInTune, "切弦后在没有新样本之前不应显示已调准")
    }

    func testMeterBarPositionClampsBeyondFiftyCents() {
        XCTAssertEqual(TunerMeterMetrics.normalizedPosition(for: 0), 0.5, accuracy: 1e-6)
        XCTAssertEqual(TunerMeterMetrics.normalizedPosition(for: 50), 1.0, accuracy: 1e-6)
        XCTAssertEqual(TunerMeterMetrics.normalizedPosition(for: -50), 0.0, accuracy: 1e-6)
        XCTAssertEqual(TunerMeterMetrics.normalizedPosition(for: 120), 1.0, accuracy: 1e-6)
        XCTAssertEqual(TunerMeterMetrics.normalizedPosition(for: -120), 0.0, accuracy: 1e-6)
        XCTAssertEqual(TunerMeterMetrics.normalizedPosition(for: 25), 0.75, accuracy: 1e-6)
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
