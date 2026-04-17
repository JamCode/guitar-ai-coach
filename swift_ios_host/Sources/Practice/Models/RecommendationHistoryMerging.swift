import Foundation

enum RecommendationHistoryMerging {
    static func mergeLegacyPracticeRecords(
        stored: [RecommendationHistoryRecord],
        sessions: [PracticeSession]
    ) -> [RecommendationHistoryRecord] {
        let legacy = sessions.compactMap { session -> RecommendationHistoryRecord? in
            let module: RecommendationModuleType
            switch session.taskId {
            case "chord-switch":
                module = .chordSwitch
            case "scale-walk":
                module = .scaleTraining
            case "traditional-crawl":
                module = .traditionalCrawl
            default:
                return nil
            }
            return RecommendationHistoryRecord(
                module: module,
                completed: session.completed,
                successRate: session.completed ? 1 : 0,
                durationSeconds: session.durationSeconds,
                occurredAt: session.endedAt
            )
        }
        return stored + legacy
    }
}
