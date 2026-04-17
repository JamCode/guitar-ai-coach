import XCTest
@testable import Practice

final class ScaleTrainingTests: XCTestCase {
    func testBeginnerIsCMajorMiEighthBpmRange() {
        var rng = SystemRandomNumberGenerator()
        let ex = ScaleTrainingGenerator.buildExercise(difficulty: .初级, using: &rng)
        XCTAssertEqual(ex.keyName, "C")
        XCTAssertEqual(ex.scaleKind, .自然大调)
        XCTAssertEqual(ex.pattern, .Mi)
        XCTAssertEqual(ex.rhythm, .八分音符)
        XCTAssertGreaterThanOrEqual(ex.bpmMin, 60)
        XCTAssertLessThanOrEqual(ex.bpmMax, 70)
        XCTAssertFalse(ex.allowsSequenceShift)
        XCTAssertFalse(ex.allowsDegreeLeap)
        XCTAssertFalse(ex.retrogradeApplied)
        XCTAssertFalse(ex.steps.isEmpty)
    }

    func testIntermediateKeyPoolAndRhythm() {
        var rng = SystemRandomNumberGenerator()
        let allowedKeys = Set(["C", "G", "D", "F"])
        for _ in 0 ..< 16 {
            let ex = ScaleTrainingGenerator.buildExercise(difficulty: .中级, using: &rng)
            XCTAssertTrue(allowedKeys.contains(ex.keyName))
            XCTAssertEqual(ex.rhythm, .八分音符)
            XCTAssertGreaterThanOrEqual(ex.bpmMin, 70)
            XCTAssertLessThanOrEqual(ex.bpmMax, 85)
            XCTAssertTrue(ex.allowsSequenceShift)
            XCTAssertFalse(ex.steps.isEmpty)
        }
    }

    func testAdvancedUsesSixteenthAndTwoOctaveSpine() {
        var rng = SystemRandomNumberGenerator()
        let ex = ScaleTrainingGenerator.buildExercise(difficulty: .高级, using: &rng)
        XCTAssertEqual(ex.rhythm, .十六分音符)
        XCTAssertGreaterThanOrEqual(ex.bpmMin, 85)
        XCTAssertLessThanOrEqual(ex.bpmMax, 110)
        XCTAssertTrue(ex.steps.count >= 20)
    }

    func testRecommendedHasThreeLevels() {
        var rng = SystemRandomNumberGenerator()
        let items = ScaleTrainingGenerator.recommendedExercises(using: &rng)
        XCTAssertEqual(items.map(\.difficulty), [.初级, .中级, .高级])
    }
}
