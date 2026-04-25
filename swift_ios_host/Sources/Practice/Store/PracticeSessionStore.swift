import Foundation

/// 练习会话的读写抽象：本期 Swift 版本默认走本地持久化。
protocol PracticeSessionStore {
    func loadSessions() async throws -> [PracticeSession]

    func saveSession(
        task: PracticeTask,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        completed: Bool,
        difficulty: Int,
        note: String?,
        progressionId: String?,
        musicKey: String?,
        complexity: String?,
        rhythmPatternId: String?,
        scaleWarmupDrillId: String?,
        earAnsweredCount: Int?,
        earCorrectCount: Int?
    ) async throws

    func loadSummary(now: Date?) async throws -> PracticeSummary
}

