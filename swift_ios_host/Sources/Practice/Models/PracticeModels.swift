import Foundation

// Keep model fields aligned with Flutter `practice_models.dart`.

struct PracticeTask: Identifiable, Equatable {
    let id: String
    let name: String
    let targetMinutes: Int
    let description: String
}

/// Swift 侧统一维护一期内置任务，避免散落常量（对齐 Flutter `kDefaultPracticeTasks`）。
let kDefaultPracticeTasks: [PracticeTask] = [
    PracticeTask(
        id: "chord-switch",
        name: "和弦切换",
        targetMinutes: 5,
        description: "多种进行 · 12 调 · 3 档复杂度"
    ),
    PracticeTask(
        id: "rhythm-strum",
        name: "节奏扫弦",
        targetMinutes: 10,
        description: "目标：稳定 4/4 节拍，下上扫衔接均匀。"
    ),
    PracticeTask(
        id: "scale-walk",
        name: "音阶爬格子",
        targetMinutes: 5,
        description: "目标：保持力度均匀，减少杂音。"
    ),
]

struct PracticeSummary: Equatable {
    let todayMinutes: Int
    let todaySessions: Int
    let streakDays: Int
}

struct PracticeSession: Identifiable, Codable, Equatable {
    let id: String
    let taskId: String
    let taskName: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let completed: Bool
    let difficulty: Int
    let note: String?

    /// 和弦进行练习专属字段（可空，兼容旧数据）。
    let progressionId: String?
    let musicKey: String?
    let complexity: String?

    /// 节奏扫弦练习所选内置节奏型 id（可空，兼容旧数据）。
    let rhythmPatternId: String?
}

// MARK: - Summary computation (aligned with Flutter)

func computeTodayMinutes(_ sessions: [PracticeSession], now: Date) -> Int {
    var seconds = 0
    for s in sessions where s.completed && isSameDay(s.endedAt, now) {
        seconds += max(0, s.durationSeconds)
    }
    return seconds / 60
}

func computeTodaySessions(_ sessions: [PracticeSession], now: Date) -> Int {
    sessions.reduce(0) { acc, s in
        acc + ((s.completed && isSameDay(s.endedAt, now)) ? 1 : 0)
    }
}

/// 连续打卡天数：自然日内有至少一次 completed 即记 1 天。
func computeStreakDays(_ sessions: [PracticeSession], now: Date) -> Int {
    let calendar = Calendar(identifier: .gregorian)
    let completedDays = Set(
        sessions
            .filter { $0.completed }
            .map { calendar.startOfDay(for: $0.endedAt) }
    )
    guard !completedDays.isEmpty else { return 0 }

    var cursor = calendar.startOfDay(for: now)
    var streak = 0
    while completedDays.contains(cursor) {
        streak += 1
        cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor.addingTimeInterval(-86400)
    }
    return streak
}

private func isSameDay(_ a: Date, _ b: Date) -> Bool {
    let calendar = Calendar(identifier: .gregorian)
    return calendar.isDate(a, inSameDayAs: b)
}

