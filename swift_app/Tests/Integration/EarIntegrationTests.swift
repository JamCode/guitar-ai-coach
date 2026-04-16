import XCTest
@testable import Ear

final class EarIntegrationTests: XCTestCase {
    func testLocalSightSingingSessionLifecycle() async throws {
        let repo = LocalSightSingingRepository()
        let start = try await repo.startSession(
            pitchRange: "mid",
            includeAccidental: false,
            questionCount: 3
        )
        XCTAssertNotNil(start.question)
        guard let question = start.question else {
            XCTFail("question should not be nil")
            return
        }
        try await repo.submitAnswer(
            sessionId: start.sessionId,
            questionId: question.id,
            answers: [question.targetNotes.first ?? "C4"],
            avgCentsAbs: 12,
            stableHitMs: 900,
            durationMs: 2000
        )
        _ = try await repo.nextQuestion(sessionId: start.sessionId)
        let result = try await repo.fetchResult(sessionId: start.sessionId)
        XCTAssertEqual(result.total, 3)
        XCTAssertGreaterThanOrEqual(result.correct, 1)
    }
}
