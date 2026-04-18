import XCTest
@testable import Ear

final class EarIntegrationTests: XCTestCase {
    func testLocalSightSingingSessionLifecycle() async throws {
        let repo = LocalSightSingingRepository()
        let start = try await repo.startSession(
            pitchRange: "mid",
            includeAccidental: false,
            questionCount: 3,
            exerciseKind: .singleNoteMimic
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
        guard let q2 = try await repo.nextQuestion(sessionId: start.sessionId) else {
            XCTFail("expected second question")
            return
        }
        try await repo.submitAnswer(
            sessionId: start.sessionId,
            questionId: q2.id,
            answers: [q2.targetNotes.first ?? "C4"],
            avgCentsAbs: 12,
            stableHitMs: 900,
            durationMs: 2000
        )
        guard let q3 = try await repo.nextQuestion(sessionId: start.sessionId) else {
            XCTFail("expected third question")
            return
        }
        try await repo.submitAnswer(
            sessionId: start.sessionId,
            questionId: q3.id,
            answers: [q3.targetNotes.first ?? "C4"],
            avgCentsAbs: 12,
            stableHitMs: 900,
            durationMs: 2000
        )
        let done = try await repo.nextQuestion(sessionId: start.sessionId)
        XCTAssertNil(done)

        let result = try await repo.fetchResult(sessionId: start.sessionId)
        XCTAssertEqual(result.total, 3)
        XCTAssertGreaterThanOrEqual(result.correct, 1)
    }

    func testLocalSightSingingIntervalSessionLifecycle() async throws {
        let repo = LocalSightSingingRepository()
        let start = try await repo.startSession(
            pitchRange: "mid",
            includeAccidental: false,
            questionCount: 2,
            exerciseKind: .intervalMimic
        )
        XCTAssertNotNil(start.question)
        guard let question = start.question else {
            XCTFail("question should not be nil")
            return
        }
        XCTAssertEqual(question.targetNotes.count, 2)
        try await repo.submitAnswer(
            sessionId: start.sessionId,
            questionId: question.id,
            answers: question.targetNotes,
            avgCentsAbs: 12,
            stableHitMs: 900,
            durationMs: 4000
        )
        guard let q2 = try await repo.nextQuestion(sessionId: start.sessionId) else {
            XCTFail("expected second question")
            return
        }
        try await repo.submitAnswer(
            sessionId: start.sessionId,
            questionId: q2.id,
            answers: q2.targetNotes,
            avgCentsAbs: 12,
            stableHitMs: 900,
            durationMs: 4000
        )
        let done = try await repo.nextQuestion(sessionId: start.sessionId)
        XCTAssertNil(done)

        let result = try await repo.fetchResult(sessionId: start.sessionId)
        XCTAssertEqual(result.total, 2)
    }
}
