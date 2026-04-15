import XCTest
@testable import Core
@testable import ChordsLive

final class LiveChordStateMachineTests: XCTestCase {
    func testStableModeNeedsTwoHits() {
        let machine = LiveChordStateMachine()
        var state = LiveChordUiState.initial().copyWith(mode: .stable, stableChord: "Unknown", timeline: ["C", "G"])
        let frame = LiveChordFrame(
            best: "Am",
            topK: [LiveChordCandidate(label: "Am", score: 0.8)],
            confidence: 0.9,
            status: "🎵 Listening…",
            timestampMs: 1
        )

        state = machine.applyFrame(current: state, frame: frame)
        XCTAssertEqual(state.stableChord, "Unknown")
        state = machine.applyFrame(current: state, frame: frame)
        XCTAssertEqual(state.stableChord, "Am")
    }

    func testFastModeSwitchesImmediately() {
        let machine = LiveChordStateMachine()
        let state = LiveChordUiState.initial().copyWith(mode: .fast, stableChord: "Unknown")
        let frame = LiveChordFrame(
            best: "F",
            topK: [LiveChordCandidate(label: "F", score: 0.8)],
            confidence: 0.9,
            status: "🎵 Listening…",
            timestampMs: 1
        )
        let next = machine.applyFrame(current: state, frame: frame)
        XCTAssertEqual(next.stableChord, "F")
    }
}

