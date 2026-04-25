import XCTest
@testable import Core
@testable import Chords

final class CoreAndChordsTests: XCTestCase {
    func testEnvironmentDefaultBaseURL() {
        let env = AppEnvironment()
        XCTAssertEqual(env.apiBaseURL, "http://localhost:18080/api")
    }

    func testChordsServiceHealthMessageContainsBaseURL() {
        let env = AppEnvironment(apiBaseURL: "https://example.com/api")
        let service = ChordsService(environment: env)
        XCTAssertTrue(service.healthMessage().contains("https://example.com/api"))
    }

    func testChordDiagramLayoutOpenCChordShowsNutAndFourFrets() {
        let c = [-1, 3, 2, 0, 1, 0]
        let cfg = ChordDiagramLayout.config(for: c)
        XCTAssertTrue(cfg.showsNut)
        XCTAssertNil(cfg.positionLabel)
        XCTAssertEqual(cfg.startFret, 1)
        XCTAssertEqual(cfg.endFret, 4)
    }

    func testChordDiagramLayoutHighBarreNoNut() {
        let bar = [5, 5, 7, 7, 7, 5]
        let cfg = ChordDiagramLayout.config(for: bar)
        XCTAssertFalse(cfg.showsNut)
        XCTAssertEqual(cfg.positionLabel, 5)
        XCTAssertEqual(cfg.startFret, 5)
        XCTAssertEqual(cfg.endFret, 8)
    }

    func testGuitarStandardTuningMidisFromOpenCChord() {
        let c = [-1, 3, 2, 0, 1, 0]
        let midis = GuitarStandardTuning.midisFromChordFretsSixToOne(c)
        XCTAssertEqual(midis, [48, 52, 55, 60, 64])
    }

    func testGuitarPlaybackHumanizerShapesBassMoreThanTreble() {
        // velocity 含 ±13 的随机层；单点可能反转，用多次采样验证低音弦在 pitch/edge 偏置下更常更强。
        var bassHigherCount = 0
        for _ in 0..<60 {
            let bassVelocity = GuitarPlaybackHumanizer.velocity(base: 88, midi: 40, noteIndex: 0, totalNotes: 5)
            let trebleVelocity = GuitarPlaybackHumanizer.velocity(base: 88, midi: 67, noteIndex: 4, totalNotes: 5)
            if bassVelocity > trebleVelocity { bassHigherCount += 1 }
        }
        XCTAssertGreaterThan(
            bassHigherCount, 40,
            "低把位 MIDI 与先拨弦的 edgeBias 应使力度多数高于高音弦（含随机时亦应稳定占优）。"
        )

        let bassGate = GuitarPlaybackHumanizer.gate(base: 1.35, midi: 40, noteIndex: 0, totalNotes: 5)
        let trebleGate = GuitarPlaybackHumanizer.gate(base: 1.35, midi: 67, noteIndex: 4, totalNotes: 5)
        XCTAssertGreaterThan(bassGate, trebleGate)
    }

    func testGuitarPlaybackHumanizerMicroDelayStaysSubtle() {
        let delays = (0..<5).map { GuitarPlaybackHumanizer.microDelay(noteIndex: $0, totalNotes: 5) }
        XCTAssertTrue(delays.allSatisfy { $0 >= 0 && $0 <= 0.003 })
        XCTAssertTrue(Set(delays).count > 1)
    }
}

