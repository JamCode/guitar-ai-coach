import XCTest
@testable import SwiftEarHost

final class TodayRecommendationPlannerTests: XCTestCase {
    func testBuildRecommendations_returnsThreeUniqueModules() async {
        var planner = TodayRecommendationPlanner(referenceDate: fixedNow)
        let items = await planner.buildRecommendations(historyRecords: [])
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Set(items.map(\.module)).count, 3)
    }

    func testBuildRecommendations_defaultsToBeginnerWhenSamplesInsufficient() async {
        let history = [
            mockRecord(module: .chordSwitch, occurredAt: fixedNow.addingTimeInterval(-3600), completed: true, successRate: 1, duration: 300),
            mockRecord(module: .chordSwitch, occurredAt: fixedNow.addingTimeInterval(-7200), completed: true, successRate: 1, duration: 260),
        ]
        var planner = TodayRecommendationPlanner(referenceDate: fixedNow)
        let items = await planner.buildRecommendations(historyRecords: history)
        let chordSwitch = items.first(where: { $0.module == .chordSwitch })
        XCTAssertEqual(chordSwitch?.difficulty, .beginner)
    }

    func testBuildRecommendations_promotesDifficultyWithStableCompletions() async {
        let history = (0..<7).map { idx in
            mockRecord(
                module: .chordSwitch,
                occurredAt: fixedNow.addingTimeInterval(TimeInterval(-idx * 3600)),
                completed: true,
                successRate: 1,
                duration: 300
            )
        }
        var planner = TodayRecommendationPlanner(referenceDate: fixedNow)
        let items = await planner.buildRecommendations(historyRecords: history)
        let chordSwitch = items.first(where: { $0.module == .chordSwitch })
        XCTAssertNotEqual(chordSwitch?.difficulty, .beginner)
    }
}

private let fixedNow = ISO8601DateFormatter().date(from: "2026-04-17T12:00:00Z")!

private func mockRecord(
    module: RecommendationModuleType,
    occurredAt: Date,
    completed: Bool,
    successRate: Double,
    duration: Int
) -> RecommendationHistoryRecord {
    RecommendationHistoryRecord(
        module: module,
        completed: completed,
        successRate: successRate,
        durationSeconds: duration,
        occurredAt: occurredAt
    )
}
