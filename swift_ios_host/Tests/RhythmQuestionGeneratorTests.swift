import XCTest
@testable import SwiftEarHost

final class RhythmQuestionGeneratorTests: XCTestCase {
    func testBeginnerPoolNotEmpty() {
        XCTAssertFalse(RhythmQuestionGenerator.pool(for: .beginner).isEmpty)
    }

    func testIntermediatePoolNotEmpty() {
        XCTAssertFalse(RhythmQuestionGenerator.pool(for: .intermediate).isEmpty)
    }

    func testAdvancedPoolNotEmpty() {
        XCTAssertFalse(RhythmQuestionGenerator.pool(for: .advanced).isEmpty)
    }

    func testMakeQuestionReturnsFourChoices() {
        var rng = SystemRandomNumberGenerator()
        let result = RhythmQuestionGenerator.makeQuestion(difficulty: .beginner, using: &rng)
        XCTAssertTrue(result.choices.contains(result.correct))
        XCTAssertEqual(result.choices.count, 4)
    }

    func testChoicesAreDistinct() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            let result = RhythmQuestionGenerator.makeQuestion(difficulty: .beginner, using: &rng)
            let unique = Set(result.choices)
            XCTAssertEqual(unique.count, 4, "Choices must all be distinct")
        }
    }

    func testNoAutoRepeat() {
        var rng = SystemRandomNumberGenerator()
        let first = RhythmQuestionGenerator.makeQuestion(difficulty: .beginner, using: &rng)
        var foundDifferent = false
        for _ in 0..<10 {
            let next = RhythmQuestionGenerator.makeQuestion(difficulty: .beginner, using: &rng)
            if next.correct != first.correct {
                foundDifferent = true
                break
            }
        }
        XCTAssertTrue(foundDifferent, "Should produce different patterns across calls")
    }
}
