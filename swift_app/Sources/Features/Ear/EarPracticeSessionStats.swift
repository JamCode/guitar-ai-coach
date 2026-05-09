import Foundation

/// 与练习 Tab「前台时长」会话对齐：按时间窗聚合练耳单次判题，供训练日历等展示正确率。
public enum EarPracticeSessionStats {
    /// 返回 `nil` 表示非练耳任务或时间窗内无判题记录。
    public static func correctnessCountsInWindow(
        practiceTaskId: String,
        startedAt: Date,
        endedAt: Date
    ) async -> (answered: Int, correct: Int)? {
        switch practiceTaskId {
        case "interval-ear":
            await intervalEarCounts(startedAt: startedAt, endedAt: endedAt)
        case "ear-chord-mcq":
            await earMcqCounts(bank: "A", startedAt: startedAt, endedAt: endedAt)
        case "ear-progression-mcq":
            await earMcqCounts(bank: "B", startedAt: startedAt, endedAt: endedAt)
        default:
            nil
        }
    }

    private static func intervalEarCounts(startedAt: Date, endedAt: Date) async -> (answered: Int, correct: Int)? {
        let rows = await IntervalEarFileHistoryStore.shared.loadAllAttempts()
        let slice = rows.filter { $0.occurredAt >= startedAt && $0.occurredAt <= endedAt }
        guard !slice.isEmpty else { return nil }
        let answered = slice.count
        let correct = slice.filter(\.wasCorrect).count
        return (answered, correct)
    }

    private static func earMcqCounts(bank: String, startedAt: Date, endedAt: Date) async -> (answered: Int, correct: Int)? {
        let rows = await EarMcqFileHistoryStore.shared.loadAllAttempts()
        let slice = rows.filter { $0.bank == bank && $0.occurredAt >= startedAt && $0.occurredAt <= endedAt }
        guard !slice.isEmpty else { return nil }
        let answered = slice.count
        let correct = slice.filter(\.wasCorrect).count
        return (answered, correct)
    }
}
