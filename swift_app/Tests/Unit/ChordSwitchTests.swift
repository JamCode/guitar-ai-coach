import Chords
import XCTest
@testable import Practice

final class ChordSwitchTests: XCTestCase {
    func testBeginnerMaxFourChordsDiatonicAndRomansMatch() {
        var rng = SystemRandomNumberGenerator()
        let ex = ChordSwitchGenerator.buildExercise(difficulty: .初级, using: &rng)
        let pool = Set(ChordSwitchGenerator.beginnerPool)
        XCTAssertEqual(ex.keyZh, ChordSwitchGenerator.defaultKeyZh)
        XCTAssertEqual(ex.beatsPerChord, 2, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(ex.bpmMin, 50)
        XCTAssertLessThanOrEqual(ex.bpmMax, 70)
        XCTAssertEqual(ex.segments.count, 1)
        let flat = ex.flattenedChords
        XCTAssertGreaterThanOrEqual(flat.count, 3)
        XCTAssertLessThanOrEqual(flat.count, 4)
        XCTAssertEqual(ex.romanNumerals.count, flat.count)
        let tonic = ChordSwitchGenerator.parseTonicKey(from: ex.keyZh)
        for ch in flat {
            let back = ChordTransposeLocal.transposeChordSymbol(ch, from: tonic, to: ChordSwitchGenerator.templateTonic)
            XCTAssertTrue(pool.contains(back), "expected C-key diatonic template for \(ch) in \(tonic)")
        }
    }

    func testBeginnerGKeyLabelAndTransposeBackToC() {
        var rng = SystemRandomNumberGenerator()
        let ex = ChordSwitchGenerator.buildExercise(difficulty: .初级, tonic: "G", using: &rng)
        XCTAssertEqual(ex.keyZh, "G 调")
        let pool = Set(ChordSwitchGenerator.beginnerPool)
        for ch in ex.flattenedChords {
            let back = ChordTransposeLocal.transposeChordSymbol(ch, from: "G", to: "C")
            XCTAssertTrue(pool.contains(back))
        }
    }

    func testIntermediateFourToSixChordsSeventhLean() {
        var rng = SystemRandomNumberGenerator()
        let ex = ChordSwitchGenerator.buildExercise(difficulty: .中级, using: &rng)
        let pool = Set(ChordSwitchGenerator.intermediatePool)
        XCTAssertEqual(ex.beatsPerChord, 1, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(ex.bpmMin, 70)
        XCTAssertLessThanOrEqual(ex.bpmMax, 90)
        XCTAssertEqual(ex.segments.count, 1)
        let flat = ex.flattenedChords
        XCTAssertGreaterThanOrEqual(flat.count, 4)
        XCTAssertLessThanOrEqual(flat.count, 6)
        XCTAssertEqual(ex.romanNumerals.count, flat.count)
        let tonic = ChordSwitchGenerator.parseTonicKey(from: ex.keyZh)
        for ch in flat {
            let back = ChordTransposeLocal.transposeChordSymbol(ch, from: tonic, to: ChordSwitchGenerator.templateTonic)
            XCTAssertTrue(pool.contains(back))
        }
    }

    func testAdvancedFourToEightExtendedChordsHalfBeat() {
        var rng = SystemRandomNumberGenerator()
        let ex = ChordSwitchGenerator.buildExercise(difficulty: .高级, using: &rng)
        let pool = Set(ChordSwitchGenerator.advancedPool)
        XCTAssertEqual(ex.beatsPerChord, 0.5, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(ex.bpmMin, 90)
        XCTAssertLessThanOrEqual(ex.bpmMax, 120)
        XCTAssertEqual(ex.segments.count, 1)
        let flat = ex.flattenedChords
        XCTAssertGreaterThanOrEqual(flat.count, 4)
        XCTAssertLessThanOrEqual(flat.count, 8)
        XCTAssertEqual(ex.romanNumerals.count, flat.count)
        let tonic = ChordSwitchGenerator.parseTonicKey(from: ex.keyZh)
        for ch in flat {
            let back = ChordTransposeLocal.transposeChordSymbol(ch, from: tonic, to: ChordSwitchGenerator.templateTonic)
            XCTAssertTrue(pool.contains(back))
        }
    }

    func testWithTonicChangesKeyAndChordSymbols() {
        var rng = SystemRandomNumberGenerator()
        let exC = ChordSwitchGenerator.buildExercise(difficulty: .初级, tonic: "C", using: &rng)
        let exD = ChordSwitchGenerator.withTonic(exC, to: "D")
        XCTAssertEqual(exD.keyZh, "D 调")
        XCTAssertEqual(exD.romanNumerals, exC.romanNumerals)
        XCTAssertEqual(exD.flattenedChords.count, exC.flattenedChords.count)
        for (a, b) in zip(exC.flattenedChords, exD.flattenedChords) {
            XCTAssertEqual(ChordTransposeLocal.transposeChordSymbol(a, from: "C", to: "D"), b)
        }
    }

    func testRomanProgressionLineMatchesFlattenedCount() {
        var rng = SystemRandomNumberGenerator()
        let ex = ChordSwitchGenerator.buildExercise(difficulty: .初级, using: &rng)
        let parts = ex.romanProgressionZh.components(separatedBy: " → ")
        XCTAssertEqual(parts.count, ex.flattenedChords.count)
    }

    func testRecommendedThreeLevels() {
        var rng = SystemRandomNumberGenerator()
        let items = ChordSwitchGenerator.recommendedExercises(using: &rng)
        XCTAssertEqual(items.map(\.difficulty), [.初级, .中级, .高级])
    }
}
