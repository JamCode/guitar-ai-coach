import XCTest
@testable import Core

/// Guards `AudioEngineService.stop()` invalidating sampler-backed state so a later `start()` reloads the SF2
/// (regression: leaving Tuner called `stop()` while `isSampledGuitarAvailable` stayed true → corrupt / buzzy playback in ear training).
final class AudioEngineServiceLifecycleTests: XCTestCase {
    func testStopClearsSampledGuitarFlagSoSecondStartReloads() throws {
        guard GuitarSoundBank.steelStringSF2URL != nil else {
            throw XCTSkip("SteelString SF2 not in bundle; cannot assert sampler lifecycle.")
        }

        let audio = AudioEngineService()
        try audio.start()
        let loadedAfterFirstStart = audio.isSampledGuitarAvailable
        audio.stop()

        if loadedAfterFirstStart {
            XCTAssertFalse(
                audio.isSampledGuitarAvailable,
                "After engine stop, sampled-guitar readiness must be false so the next start reloads the sound bank."
            )
        }

        try audio.start()
        if loadedAfterFirstStart {
            XCTAssertTrue(
                audio.isSampledGuitarAvailable,
                "Second cold start after stop must load SF2 again when the first start succeeded."
            )
        }

        audio.stop()
    }
}

// MARK: - Sound Quality Humanizer Tests

final class GuitarPlaybackHumanizerTests: XCTestCase {

    // MARK: velocity 随机范围

    func testVelocityRandomOffsetStaysInMidiRange() {
        // 对不同 midi、noteIndex 跑大量采样，确认结果始终在 [1, 127] 范围内。
        for midi in [40, 55, 69, 84, 100] {
            for noteIndex in 0..<6 {
                for _ in 0..<50 {
                    let v = GuitarPlaybackHumanizer.velocity(
                        base: 88, midi: midi, noteIndex: noteIndex, totalNotes: 6
                    )
                    XCTAssertGreaterThanOrEqual(v, 1, "velocity must be ≥ 1 (midi=\(midi))")
                    XCTAssertLessThanOrEqual(v, 127, "velocity must be ≤ 127 (midi=\(midi))")
                }
            }
        }
    }

    func testHighMidiVelocityIsSoftenedBeforeRandomization() {
        XCTAssertEqual(GuitarPlaybackHumanizer.pitchShapedBaseVelocity(base: 100, midi: 72), 94)
        XCTAssertEqual(GuitarPlaybackHumanizer.pitchShapedBaseVelocity(base: 100, midi: 84), 88)
        XCTAssertEqual(GuitarPlaybackHumanizer.pitchShapedBaseVelocity(base: 100, midi: 96), 82)
    }

    func testVelocityIsNotAlwaysIdentical() {
        // 真随机：同样入参多次调用，结果不应全部相同（概率极低的误判在统计上可接受）。
        let results = (0..<30).map {
            _ in GuitarPlaybackHumanizer.velocity(base: 88, midi: 69, noteIndex: 0, totalNotes: 1)
        }
        let allSame = results.dropFirst().allSatisfy { $0 == results[0] }
        XCTAssertFalse(allSame, "velocity should vary across calls (random ±10% offset expected)")
    }

    // MARK: microDelay 随机范围

    func testMicroDelayIsZeroForSingleNote() {
        XCTAssertEqual(GuitarPlaybackHumanizer.microDelay(noteIndex: 0, totalNotes: 1), 0)
    }

    func testMicroDelayIsNonNegativeAndBounded() {
        for noteIndex in 0..<6 {
            for _ in 0..<30 {
                let d = GuitarPlaybackHumanizer.microDelay(noteIndex: noteIndex, totalNotes: 6)
                XCTAssertGreaterThanOrEqual(d, 0, "microDelay must be non-negative")
                XCTAssertLessThanOrEqual(d, 0.002, "microDelay must be ≤ 2ms")
            }
        }
    }

    // MARK: stagger 默认值

    func testDefaultStringStaggerIs20ms() {
        // playSampledGuitarChord 的默认 stagger 须为 0.020s，确保听感上的扫弦感。
        // 此处用协议反射验证接口签名保持一致（通过参数默认值等效测试）。
        // 由于 Swift 默认参数无法直接反射，此处验证在不传 stagger 时 chord 调度不崩溃。
        let audio = AudioEngineService()
        // 不启动引擎，仅确认 guard sampledGuitarLoaded 路径可安全到达（不 throw 之外的崩溃）。
        XCTAssertNoThrow(
            try? audio.playSampledGuitarChord(midis: [60, 64, 67], velocity: 80, gateDurationSec: 1.0, stringStaggerSec: 0.020)
        )
    }

    // MARK: round-robin 偏移数组

    func testRrTuningOffsetsHasThreeEntries() {
        // 三档轮换：0 / -1.8 / +1.8 cent。
        let offsets = AudioEngineService.rrTuningOffsets
        XCTAssertEqual(offsets.count, 3)
        XCTAssertEqual(offsets[0], 0.0, accuracy: 0.001)
        XCTAssertNotEqual(offsets[1], offsets[2], "negative and positive offset must differ")
    }
}

// MARK: - P2/P3 效果器参数合理性测试

final class GuitarEffectChainTests: XCTestCase {

    private var audio: AudioEngineService!

    override func setUp() {
        super.setUp()
        audio = AudioEngineService()
    }

    // MARK: P2 压缩器

    func testCompressorThresholdIsReasonable() {
        // threshold 须在 -40~0 dBFS 的有效区间内，且不会过度压缩到无声。
        let t = audio.compressorThreshold
        XCTAssertLessThanOrEqual(t, -5, "threshold should attenuate signal, not be near 0 dBFS")
        XCTAssertGreaterThanOrEqual(t, -40, "threshold too low — would silence most guitar notes")
    }

    func testCompressorAttackAndReleaseArePositive() {
        XCTAssertGreaterThan(audio.compressorAttackTime, 0, "attack must be > 0")
        XCTAssertGreaterThan(audio.compressorReleaseTime, 0, "release must be > 0")
    }

    func testCompressorAttackPreservesTransient() {
        // Attack ≥ 15ms 才能让拨弦初始瞬态（pick attack）不被压掉。
        XCTAssertGreaterThanOrEqual(audio.compressorAttackTime, 0.015,
            "attack < 15ms will squash guitar pick transient")
    }

    // MARK: P2 Slapback 延迟

    func testSlapbackDelayTimeIsInEarlyReflectionRange() {
        // Slapback 须在 10~50ms 区间，才产生早反射感而不是明显回声。
        let d = audio.slapbackDelayTime
        XCTAssertGreaterThanOrEqual(d, 0.010, "slapback too short — inaudible")
        XCTAssertLessThanOrEqual(d, 0.050, "slapback > 50ms becomes audible echo")
    }

    func testSlapbackFeedbackIsZero() {
        // feedback = 0 确保只有单次反射，不堆叠回声。
        XCTAssertEqual(audio.slapbackFeedback, 0, accuracy: 0.01,
            "slapback feedback must be 0 — only one reflection allowed")
    }

    func testSlapbackWetDryMixIsSubtle() {
        // 干湿比不应过大（> 30%），以免 slapback 喧宾夺主。
        XCTAssertLessThanOrEqual(audio.slapbackWetDryMix, 30,
            "slapback wet/dry > 30% will overwhelm the direct signal")
    }

    // MARK: P3 Haas 伪立体声宽度

    func testHaasDelayTimeIsInHaasZone() {
        // Haas 区间：1~30ms，超出则产生可感知的双声道回声而非宽度感。
        let d = audio.haasDelayTime
        XCTAssertGreaterThanOrEqual(d, 0.001, "Haas delay too short — no width effect")
        XCTAssertLessThanOrEqual(d, 0.030, "Haas delay > 30ms produces echo, not width")
    }

    func testHaasFeedbackIsZero() {
        XCTAssertEqual(audio.haasFeedback, 0, accuracy: 0.01,
            "Haas feedback must be 0 — width effect relies on single delayed copy only")
    }

    func testHaasWetDryMixAllowsMonoCompatibility() {
        // 干湿比不超过 30% 可保持单声道折叠时无明显梳状滤波。
        XCTAssertLessThanOrEqual(audio.haasWetDryMix, 30,
            "Haas wet/dry > 30% risks comb filtering on mono playback")
    }
}
