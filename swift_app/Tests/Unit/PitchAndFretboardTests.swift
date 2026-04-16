import XCTest
@testable import Core
@testable import Fretboard
@testable import Chords

final class PitchAndFretboardTests: XCTestCase {
    func testFrequencyToMidi() {
        XCTAssertEqual(PitchMath.frequencyToMidi(440), 69)
        XCTAssertEqual(PitchMath.midiToNoteName(69), "A")
        XCTAssertEqual(PitchMath.midiToPitchLabel(69), "a4")
        XCTAssertEqual(PitchMath.midiToPitchLabel(60), "c4")
        XCTAssertEqual(PitchMath.midiToPitchLabel(61), "c#4")
    }

    func testCentsBetween() {
        let cents = PitchMath.centsBetween(actualHz: 445, targetHz: 440)
        XCTAssertGreaterThan(cents, 0)
    }

    func testFretboardMidiAndPitchLabels() {
        XCTAssertEqual(FretboardMath.midiAtFret(stringIndex: 0, fret: 0, capo: 0), 40)
        XCTAssertEqual(FretboardMath.labelForCell(stringIndex: 0, fret: 0, capo: 0), "e2")
        XCTAssertEqual(FretboardMath.labelForCell(stringIndex: 0, fret: 1, capo: 0), "f2")
        XCTAssertEqual(FretboardMath.labelForCell(stringIndex: 0, fret: 2, capo: 0), "f#2")
    }

    func testFretboardMidiWithCapoUsesAbsoluteFrets() {
        XCTAssertEqual(FretboardMath.midiAtFret(stringIndex: 0, fret: 0, capo: 2), 42)
        XCTAssertEqual(FretboardMath.midiAtFret(stringIndex: 0, fret: 5, capo: 2), 45)
        XCTAssertEqual(FretboardMath.midiAtFret(stringIndex: 5, fret: 0, capo: 0), 64)
    }

    func testChordSymbolBuild() {
        XCTAssertEqual(ChordSymbolBuilder.build(root: "C", qualityId: "maj7", bassId: ""), "Cmaj7")
        XCTAssertEqual(ChordSymbolBuilder.build(root: "D", qualityId: "m", bassId: "5"), "Dm/5")
    }

    func testChordTransposeAndOfflinePayload() {
        let transposed = ChordTransposeLocal.transposeChordSymbol("Cmaj7", from: "C", to: "D")
        XCTAssertEqual(transposed, "Dmaj7")
        let payload = OfflineChordBuilder.buildPayload(displaySymbol: "C")
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.voicings.count, 2)
    }

    func testAudioQualityBaselineSnapshot() {
        let baseline = AudioQualityBaseline()
        baseline.markStart()
        baseline.markCallback(renderCostMs: 0.2)
        baseline.markCallback(renderCostMs: 0.3)
        baseline.markStop()
        let snapshot = baseline.snapshot()
        XCTAssertEqual(snapshot.startCount, 1)
        XCTAssertEqual(snapshot.stopCount, 1)
        XCTAssertEqual(snapshot.callbackCount, 2)
        XCTAssertGreaterThan(snapshot.averageRenderCostMs, 0)
    }
}

