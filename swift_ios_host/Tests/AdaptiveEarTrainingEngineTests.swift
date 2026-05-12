import XCTest
@testable import SwiftEarHost

final class AdaptiveEarTrainingEngineTests: XCTestCase {
    func testUpdatedRating_rewardsHardCorrectMoreThanEasyCorrect() {
        let rating = 400.0
        let easy = AdaptiveEarTrainingEngine.updatedRating(
            current: rating,
            difficultyScore: 300,
            wasCorrect: true,
            totalAnswered: 5
        )
        let hard = AdaptiveEarTrainingEngine.updatedRating(
            current: rating,
            difficultyScore: 650,
            wasCorrect: true,
            totalAnswered: 5
        )

        XCTAssertGreaterThan(hard - rating, easy - rating)
    }

    func testUpdatedRating_penalizesEasyWrongMoreThanHardWrong() {
        let rating = 500.0
        let easy = AdaptiveEarTrainingEngine.updatedRating(
            current: rating,
            difficultyScore: 300,
            wasCorrect: false,
            totalAnswered: 5
        )
        let hard = AdaptiveEarTrainingEngine.updatedRating(
            current: rating,
            difficultyScore: 700,
            wasCorrect: false,
            totalAnswered: 5
        )

        XCTAssertLessThan(easy, hard)
    }

    func testSelectNextKind_prioritizesWeakRecentModule() {
        let records = [
            mockAttempt(kind: .progression, correct: false, offset: -4),
            mockAttempt(kind: .progression, correct: false, offset: -3),
            mockAttempt(kind: .chord, correct: true, offset: -2),
            mockAttempt(kind: .interval, correct: true, offset: -1),
        ]
        let picked = AdaptiveEarTrainingEngine.selectNextKind(
            state: .initial,
            records: records,
            roll: 0.30
        )

        XCTAssertEqual(picked, .progression)
    }

    func testDifficulty_movesDownAfterTwoWrongAndUpAfterThreeCorrect() {
        var weak = AdaptiveEarAbilityState.initial
        weak.intervalRating = 620
        weak.consecutiveWrong = 2
        XCTAssertEqual(AdaptiveEarTrainingEngine.difficulty(for: .interval, state: weak), .beginner)

        var strong = AdaptiveEarAbilityState.initial
        strong.intervalRating = 620
        strong.consecutiveCorrect = 3
        XCTAssertEqual(AdaptiveEarTrainingEngine.difficulty(for: .interval, state: strong), .advanced)
    }

    func testRecentAccuracyAndLevelMapping() {
        let records = (0..<20).map { idx in
            mockAttempt(kind: .chord, correct: idx < 13, offset: idx)
        }

        XCTAssertEqual(Int((AdaptiveEarTrainingEngine.recentAccuracy(records: records)! * 100).rounded()), 65)
        var state = AdaptiveEarAbilityState.initial
        state.overallEarRating = 428
        XCTAssertEqual(state.levelTitle, "初级")
    }
}

private func mockAttempt(
    kind: AdaptiveEarQuestionKind,
    correct: Bool,
    offset: Int
) -> AdaptiveEarAttemptRecord {
    AdaptiveEarAttemptRecord(
        id: UUID().uuidString,
        questionKindRaw: kind.rawValue,
        questionId: "q-\(offset)",
        difficultyRaw: AdaptiveEarDifficulty.beginner.rawValue,
        difficultyScore: 400,
        correctAnswer: "A",
        selectedAnswer: correct ? "A" : "B",
        wasCorrect: correct,
        responseTimeMs: 1_000,
        answeredAt: Date(timeIntervalSince1970: TimeInterval(10_000 + offset)),
        ratingBeforeOverall: 400,
        ratingAfterOverall: 401,
        ratingBeforeKind: 400,
        ratingAfterKind: 401,
        skipped: false
    )
}
