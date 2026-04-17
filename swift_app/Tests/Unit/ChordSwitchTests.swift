import XCTest
@testable import Practice

final class ChordSwitchTests: XCTestCase {
    func testBeginnerUsesOnlyOpenPoolPairsOfTwo() {
        var rng = SystemRandomNumberGenerator()
        let ex = ChordSwitchGenerator.buildExercise(difficulty: .初级, using: &rng)
        let pool = Set(ChordSwitchGenerator.beginnerPool)
        XCTAssertEqual(ex.beatsPerChord, 2, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(ex.bpmMin, 50)
        XCTAssertLessThanOrEqual(ex.bpmMax, 70)
        XCTAssertFalse(ex.segments.isEmpty)
        for seg in ex.segments {
            XCTAssertEqual(seg.chords.count, 2)
            XCTAssertTrue(seg.chords.allSatisfy { pool.contains($0) })
        }
    }

    func testIntermediateGroupSizeAndBeats() {
        var rng = SystemRandomNumberGenerator()
        let ex = ChordSwitchGenerator.buildExercise(difficulty: .中级, using: &rng)
        let pool = Set(ChordSwitchGenerator.intermediatePool)
        XCTAssertEqual(ex.beatsPerChord, 1, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(ex.bpmMin, 70)
        XCTAssertLessThanOrEqual(ex.bpmMax, 90)
        for seg in ex.segments {
            XCTAssertTrue((3 ... 4).contains(seg.chords.count))
            XCTAssertTrue(seg.chords.allSatisfy { pool.contains($0) })
        }
    }

    func testAdvancedFourChordsHalfBeat() {
        var rng = SystemRandomNumberGenerator()
        let ex = ChordSwitchGenerator.buildExercise(difficulty: .高级, using: &rng)
        let pool = Set(ChordSwitchGenerator.advancedPool)
        XCTAssertEqual(ex.beatsPerChord, 0.5, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(ex.bpmMin, 90)
        XCTAssertLessThanOrEqual(ex.bpmMax, 120)
        for seg in ex.segments {
            XCTAssertEqual(seg.chords.count, 4)
            XCTAssertTrue(seg.chords.allSatisfy { pool.contains($0) })
        }
    }

    func testRecommendedThreeLevels() {
        var rng = SystemRandomNumberGenerator()
        let items = ChordSwitchGenerator.recommendedExercises(using: &rng)
        XCTAssertEqual(items.map(\.difficulty), [.初级, .中级, .高级])
    }
}
