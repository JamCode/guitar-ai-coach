import XCTest
import Practice
@testable import SwiftEarHost

final class PracticeLocalStoreTests: XCTestCase {
    func testDecodeSessions_invalidJson_returnsEmpty() {
        let sessions = decodeSessions("{not json")
        XCTAssertEqual(sessions, [])
    }

    func testDecodeSessions_skipsBrokenItems_keepsValidOnes() {
        let good: [String: Any] = [
            "id": "1",
            "taskId": "scale-walk",
            "taskName": "爬格子热身",
            "startedAt": "2026-01-01T00:00:00Z",
            "endedAt": "2026-01-01T00:01:00Z",
            "durationSeconds": 60,
            "completed": true,
            "difficulty": 3
        ]
        let bad: [String: Any] = [
            "id": "2",
            "taskId": "scale-walk"
            // missing required fields
        ]
        let rawData = try! JSONSerialization.data(withJSONObject: [bad, good], options: [])
        let raw = String(data: rawData, encoding: .utf8)!

        let sessions = decodeSessions(raw)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, "1")
    }

    func testDecodeSessions_acceptsScaleWarmupDrillId() {
        let raw: [String: Any] = [
            "id": "1",
            "taskId": "scale-walk",
            "taskName": "爬格子热身",
            "startedAt": "2026-01-01T00:00:00Z",
            "endedAt": "2026-01-01T00:01:00Z",
            "durationSeconds": 60,
            "completed": true,
            "difficulty": 3,
            "scaleWarmupDrillId": "crawl_b_6_4_68",
        ]
        let data = try! JSONSerialization.data(withJSONObject: [raw], options: [])
        let sessions = decodeSessions(String(data: data, encoding: .utf8)!)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.scaleWarmupDrillId, "crawl_b_6_4_68")
    }

    func testComputeSummary_todayCounts_completedOnly() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = ISO8601DateFormatter().date(from: "2026-01-02T12:00:00Z")!
        let todayEnd = now
        let yesterdayEnd = calendar.date(byAdding: .day, value: -1, to: now)!

        let sessions: [PracticeSession] = [
            PracticeSession(
                id: "a",
                taskId: "scale-walk",
                taskName: "爬格子热身",
                startedAt: todayEnd.addingTimeInterval(-120),
                endedAt: todayEnd,
                durationSeconds: 120,
                completed: true,
                difficulty: 3,
                note: nil,
                progressionId: nil,
                musicKey: nil,
                complexity: nil,
                rhythmPatternId: nil,
                scaleWarmupDrillId: nil
            ),
            PracticeSession(
                id: "b",
                taskId: "scale-walk",
                taskName: "爬格子热身",
                startedAt: todayEnd.addingTimeInterval(-60),
                endedAt: todayEnd,
                durationSeconds: 60,
                completed: false,
                difficulty: 3,
                note: nil,
                progressionId: nil,
                musicKey: nil,
                complexity: nil,
                rhythmPatternId: nil,
                scaleWarmupDrillId: nil
            ),
            PracticeSession(
                id: "c",
                taskId: "scale-walk",
                taskName: "爬格子热身",
                startedAt: yesterdayEnd.addingTimeInterval(-60),
                endedAt: yesterdayEnd,
                durationSeconds: 60,
                completed: true,
                difficulty: 3,
                note: nil,
                progressionId: nil,
                musicKey: nil,
                complexity: nil,
                rhythmPatternId: nil,
                scaleWarmupDrillId: nil
            ),
        ]

        XCTAssertEqual(computeTodayMinutes(sessions, now: now), 2) // 120s -> 2min
        XCTAssertEqual(computeTodaySessions(sessions, now: now), 1)
    }

    func testComputeStreakDays_countsConsecutiveDays() {
        let calendar = Calendar(identifier: .gregorian)
        let now = ISO8601DateFormatter().date(from: "2026-01-03T12:00:00Z")!
        let day0 = now
        let day1 = calendar.date(byAdding: .day, value: -1, to: now)!
        let day2 = calendar.date(byAdding: .day, value: -2, to: now)!
        let day4 = calendar.date(byAdding: .day, value: -4, to: now)!

        let sessions: [PracticeSession] = [
            PracticeSession(id: "0", taskId: "x", taskName: "x", startedAt: day0, endedAt: day0, durationSeconds: 60, completed: true, difficulty: 3, note: nil, progressionId: nil, musicKey: nil, complexity: nil, rhythmPatternId: nil, scaleWarmupDrillId: nil),
            PracticeSession(id: "1", taskId: "x", taskName: "x", startedAt: day1, endedAt: day1, durationSeconds: 60, completed: true, difficulty: 3, note: nil, progressionId: nil, musicKey: nil, complexity: nil, rhythmPatternId: nil, scaleWarmupDrillId: nil),
            PracticeSession(id: "2", taskId: "x", taskName: "x", startedAt: day2, endedAt: day2, durationSeconds: 60, completed: true, difficulty: 3, note: nil, progressionId: nil, musicKey: nil, complexity: nil, rhythmPatternId: nil, scaleWarmupDrillId: nil),
            PracticeSession(id: "4", taskId: "x", taskName: "x", startedAt: day4, endedAt: day4, durationSeconds: 60, completed: true, difficulty: 3, note: nil, progressionId: nil, musicKey: nil, complexity: nil, rhythmPatternId: nil, scaleWarmupDrillId: nil),
        ]

        XCTAssertEqual(computeStreakDays(sessions, now: now), 3)
    }

    func testRollingSevenDayStats_includesSixCalendarDaysBackFromStartOfToday() {
        let cal = Calendar(identifier: .gregorian)
        let now = ISO8601DateFormatter().date(from: "2026-01-08T12:00:00Z")!
        let inside = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))!.addingTimeInterval(3600)
        let outside = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))!.addingTimeInterval(3600)

        let sessions: [PracticeSession] = [
            PracticeSession(
                id: "in", taskId: "x", taskName: "x",
                startedAt: inside.addingTimeInterval(-10), endedAt: inside,
                durationSeconds: 120, completed: true, difficulty: 3,
                note: nil, progressionId: nil, musicKey: nil, complexity: nil,
                rhythmPatternId: nil, scaleWarmupDrillId: nil
            ),
            PracticeSession(
                id: "out", taskId: "x", taskName: "x",
                startedAt: outside.addingTimeInterval(-10), endedAt: outside,
                durationSeconds: 999, completed: true, difficulty: 3,
                note: nil, progressionId: nil, musicKey: nil, complexity: nil,
                rhythmPatternId: nil, scaleWarmupDrillId: nil
            ),
            PracticeSession(
                id: "incomplete", taskId: "x", taskName: "x",
                startedAt: now.addingTimeInterval(-20), endedAt: now,
                durationSeconds: 60, completed: false, difficulty: 3,
                note: nil, progressionId: nil, musicKey: nil, complexity: nil,
                rhythmPatternId: nil, scaleWarmupDrillId: nil
            ),
        ]

        let stats = computeRollingSevenDayPracticeStats(sessions, now: now)
        XCTAssertEqual(stats.sessionCount, 1)
        XCTAssertEqual(stats.totalDurationSeconds, 120)
    }

    func testSaveSession_belowMinForegroundSeconds_doesNotPersist() async throws {
        let suite = "practice_store_min_gate_\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("suite defaults")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        let store = PracticeLocalStore(defaults: defaults)
        let task = PracticeTask(id: "t", name: "T", targetMinutes: 1, description: "")
        try await store.saveSession(
            task: task,
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: PracticeRecordingPolicy.minForegroundSecondsToPersist - 1,
            completed: true,
            difficulty: 3,
            note: nil,
            progressionId: nil,
            musicKey: nil,
            complexity: nil,
            rhythmPatternId: nil,
            scaleWarmupDrillId: nil
        )
        let sessions = try await store.loadSessions()
        XCTAssertEqual(sessions.count, 0)
        defaults.removePersistentDomain(forName: suite)
    }

    func testSaveSession_atMinForegroundSeconds_persists() async throws {
        let suite = "practice_store_min_ok_\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("suite defaults")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        let store = PracticeLocalStore(defaults: defaults)
        let task = PracticeTask(id: "t2", name: "T2", targetMinutes: 1, description: "")
        try await store.saveSession(
            task: task,
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: PracticeRecordingPolicy.minForegroundSecondsToPersist,
            completed: true,
            difficulty: 3,
            note: nil,
            progressionId: nil,
            musicKey: nil,
            complexity: nil,
            rhythmPatternId: nil,
            scaleWarmupDrillId: nil
        )
        let sessions = try await store.loadSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.durationSeconds, PracticeRecordingPolicy.minForegroundSecondsToPersist)
        defaults.removePersistentDomain(forName: suite)
    }

    func testLatestCompletedPracticeEndedAt_picksMaxEndedAtAmongCompleted() {
        let t1 = ISO8601DateFormatter().date(from: "2026-01-01T10:00:00Z")!
        let t2 = ISO8601DateFormatter().date(from: "2026-01-02T10:00:00Z")!
        let sessions: [PracticeSession] = [
            PracticeSession(
                id: "a", taskId: "x", taskName: "x",
                startedAt: t1.addingTimeInterval(-1), endedAt: t1,
                durationSeconds: 1, completed: true, difficulty: 3,
                note: nil, progressionId: nil, musicKey: nil, complexity: nil,
                rhythmPatternId: nil, scaleWarmupDrillId: nil
            ),
            PracticeSession(
                id: "b", taskId: "x", taskName: "x",
                startedAt: t2.addingTimeInterval(-1), endedAt: t2,
                durationSeconds: 1, completed: false, difficulty: 3,
                note: nil, progressionId: nil, musicKey: nil, complexity: nil,
                rhythmPatternId: nil, scaleWarmupDrillId: nil
            ),
            PracticeSession(
                id: "c", taskId: "x", taskName: "x",
                startedAt: t2.addingTimeInterval(-1), endedAt: t2,
                durationSeconds: 1, completed: true, difficulty: 3,
                note: nil, progressionId: nil, musicKey: nil, complexity: nil,
                rhythmPatternId: nil, scaleWarmupDrillId: nil
            ),
        ]
        XCTAssertEqual(latestCompletedPracticeEndedAt(sessions), t2)
    }
}

