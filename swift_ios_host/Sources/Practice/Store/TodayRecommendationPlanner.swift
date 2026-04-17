import Foundation
import Ear

struct TodayRecommendationPlanner {
    private let referenceDate: Date
    private let calendar = Calendar(identifier: .gregorian)
    private var rng = SystemRandomNumberGenerator()

    init(referenceDate: Date = Date()) {
        self.referenceDate = referenceDate
    }

    mutating func buildRecommendations(historyRecords: [RecommendationHistoryRecord]) async -> [TodayRecommendationItem] {
        let modules = pickTodayModules(historyRecords: historyRecords)
        var items: [TodayRecommendationItem] = []
        for module in modules {
            let difficulty = decideDifficulty(for: module, records: historyRecords)
            let reason = reasonText(for: module, difficulty: difficulty, records: historyRecords)
            let payload = await makePayload(for: module, difficulty: difficulty)
            let summary = summaryText(for: module, difficulty: difficulty, payload: payload)
            items.append(
                TodayRecommendationItem(
                    module: module,
                    difficulty: difficulty,
                    reason: reason,
                    summary: summary,
                    payload: payload
                )
            )
        }
        return items
    }

    private func pickTodayModules(historyRecords: [RecommendationHistoryRecord]) -> [RecommendationModuleType] {
        let all = RecommendationModuleType.allCases
        let scored = all.map { module -> (RecommendationModuleType, Double) in
            (module, modulePriorityScore(module: module, records: historyRecords))
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.rawValue < rhs.0.rawValue
        }

        let top = Array(scored.prefix(3).map(\.0))
        guard top.count == 3 else { return top }

        // 同一天内稳定打散：避免永远固定顺序，同时保证可复现（同一天同一套历史 -> 同一顺序）。
        var tieBreaker = SeededGenerator(seed: daySeed(for: referenceDate))
        return top.shuffled(using: &tieBreaker)
    }

    private func daySeed(for date: Date) -> UInt64 {
        let day = calendar.startOfDay(for: date)
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        let y = UInt64(max(0, comps.year ?? 0))
        let m = UInt64(max(0, comps.month ?? 0))
        let d = UInt64(max(0, comps.day ?? 0))
        return (y &* 1_000_000) &+ (m &* 1_000) &+ d
    }

    private func modulePriorityScore(module: RecommendationModuleType, records: [RecommendationHistoryRecord]) -> Double {
        let recent = recentRecords(for: module, records: records)
        let completionRate = recent.isEmpty ? 0 : Double(recent.filter(\.completed).count) / Double(recent.count)
        let avgSuccess = recent.isEmpty ? 0 : recent.map(\.successRate).reduce(0, +) / Double(recent.count)

        let inactive = Double(inactiveDays(for: module, records: records))
        let inactivityBoost = min(40, inactive * 3)

        let completionPenalty = completionRate * 18
        let successPenalty = avgSuccess * 12

        var score = 50 + inactivityBoost - completionPenalty - successPenalty

        // 轻量偏好：让首页更容易出现「听感 + 手型」组合（可被历史数据覆盖）。
        switch module {
        case .intervalEar, .chordSwitch:
            score += 6
        default:
            break
        }

        if consecutiveIncomplete(records: recent, count: 2) {
            score += 8
        }

        return score
    }

    private func decideDifficulty(for module: RecommendationModuleType, records: [RecommendationHistoryRecord]) -> RecommendationDifficultyLevel {
        let recent = recentRecords(for: module, records: records)
        guard recent.count >= 3 else { return .beginner }

        let completionRate = Double(recent.filter(\.completed).count) / Double(recent.count)
        let avgSuccess = recent.map(\.successRate).reduce(0, +) / Double(recent.count)
        let durations = recent.map { Double(max(1, $0.durationSeconds)) }
        let avgDuration = durations.reduce(0, +) / Double(max(1, durations.count))
        let variance = durations.reduce(0.0) { partial, value in
            let delta = value - avgDuration
            return partial + delta * delta
        } / Double(max(1, durations.count))
        let normalizedStability = max(0.0, min(1.0, 1.0 - (sqrt(variance) / max(60, avgDuration))))

        let streak = moduleStreakDays(for: module, records: records)
        let accuracyScore = avgSuccess * 45.0
        let completionScore = completionRate * 25.0
        let stabilityScore = normalizedStability * 20.0
        let streakScore = min(10.0, Double(streak) * 2.0)
        var score = accuracyScore + completionScore + stabilityScore + streakScore

        if consecutiveIncomplete(records: recent, count: 2) {
            score = max(0, score - 15)
        }
        if inactiveDays(for: module, records: records) >= 3 {
            score = min(score, 70)
        }

        switch score {
        case ..<40:
            return .beginner
        case ..<70:
            return .intermediate
        default:
            return .advanced
        }
    }

    private func recentRecords(for module: RecommendationModuleType, records: [RecommendationHistoryRecord]) -> [RecommendationHistoryRecord] {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: referenceDate) ?? referenceDate
        return records
            .filter { $0.module == module && $0.occurredAt >= cutoff }
            .sorted(by: { $0.occurredAt > $1.occurredAt })
    }

    private func moduleStreakDays(for module: RecommendationModuleType, records: [RecommendationHistoryRecord]) -> Int {
        let moduleDays = Set(
            records
                .filter { $0.module == module && $0.completed }
                .map { calendar.startOfDay(for: $0.occurredAt) }
        )
        guard !moduleDays.isEmpty else { return 0 }
        var streak = 0
        var cursor = calendar.startOfDay(for: referenceDate)
        while moduleDays.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor.addingTimeInterval(-86_400)
        }
        return streak
    }

    private func inactiveDays(for module: RecommendationModuleType, records: [RecommendationHistoryRecord]) -> Int {
        let latest = records
            .filter { $0.module == module }
            .map(\.occurredAt)
            .max()
        guard let latest else { return 999 }
        let start = calendar.startOfDay(for: latest)
        let end = calendar.startOfDay(for: referenceDate)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private func consecutiveIncomplete(records: [RecommendationHistoryRecord], count: Int) -> Bool {
        guard records.count >= count else { return false }
        return records.prefix(count).allSatisfy { !$0.completed }
    }

    private mutating func makePayload(for module: RecommendationModuleType, difficulty: RecommendationDifficultyLevel) async -> RecommendationPayload {
        switch module {
        case .intervalEar:
            let mapped: IntervalEarDifficulty = switch difficulty {
            case .beginner: .初级
            case .intermediate: .中级
            case .advanced: .高级
            }
            let question = IntervalQuestionGenerator.next(difficulty: mapped, using: &rng)
            return .intervalQuestion(question)
        case .chordEar:
            let mapped: EarChordMcqDifficulty = switch difficulty {
            case .beginner: .初级
            case .intermediate: .中级
            case .advanced: .高级
            }
            let question = EarChordMcqGenerator.makeQuestion(difficulty: mapped, using: &rng)
            return .chordQuestion(question)
        case .sightSinging:
            switch difficulty {
            case .beginner:
                return .sightSingingConfig(pitchRange: "mid", includeAccidental: false, questionCount: 6)
            case .intermediate:
                return .sightSingingConfig(pitchRange: "wide", includeAccidental: false, questionCount: 8)
            case .advanced:
                return .sightSingingConfig(pitchRange: "wide", includeAccidental: true, questionCount: 10)
            }
        case .chordSwitch:
            let pools: [[String]] = [
                ["C", "G", "Am", "Em"],
                ["Dm", "G", "Cmaj7", "Am7", "F"],
                ["Bb", "Fmaj7", "Gm7", "C7", "Dm7"]
            ]
            let idx = difficulty == .beginner ? 0 : (difficulty == .intermediate ? 1 : 2)
            let pool = pools[idx]
            let chords = Array(pool.shuffled(using: &rng).prefix(4))
            let bpm = difficulty == .beginner ? 60 : (difficulty == .intermediate ? 80 : 100)
            return .chordSwitch(ChordSwitchExercise(chords: chords, bpm: bpm))
        case .scaleTraining:
            let keys = difficulty == .advanced ? ["C", "G", "D", "A", "E", "F", "Bb"] : ["C", "G", "D", "F"]
            let mode = difficulty == .beginner ? "自然大调" : (difficulty == .intermediate ? "五声音阶大调" : "自然小调")
            let pattern = difficulty == .beginner ? "Mi 指型" : (difficulty == .intermediate ? "Sol 指型" : "La 指型")
            let bpm = difficulty == .beginner ? 68 : (difficulty == .intermediate ? 84 : 104)
            return .scaleTraining(
                ScaleTrainingExercise(
                    keyName: keys.randomElement(using: &rng) ?? "C",
                    modeName: mode,
                    patternName: pattern,
                    bpm: bpm
                )
            )
        case .traditionalCrawl:
            let startFretRange: ClosedRange<Int> = switch difficulty {
            case .beginner: 1 ... 3
            case .intermediate: 2 ... 6
            case .advanced: 3 ... 8
            }
            let rounds = difficulty == .advanced ? 3 : 2
            let bpm = difficulty == .beginner ? 64 : (difficulty == .intermediate ? 78 : 96)
            return .traditionalCrawl(
                TraditionalCrawlExercise(
                    startFret: Int.random(in: startFretRange, using: &rng),
                    rounds: rounds,
                    bpm: bpm
                )
            )
        }
    }

    private func reasonText(for module: RecommendationModuleType, difficulty: RecommendationDifficultyLevel, records: [RecommendationHistoryRecord]) -> String {
        let count = recentRecords(for: module, records: records).count
        if count < 3 {
            return "最近 7 天样本不足 3 次，默认从初级开始。"
        }
        return "最近 7 天共 \(count) 次相关训练，按完成率与稳定性推荐为\(difficulty.rawValue)。"
    }

    private func summaryText(for module: RecommendationModuleType, difficulty: RecommendationDifficultyLevel, payload: RecommendationPayload) -> String {
        switch payload {
        case let .intervalQuestion(question):
            let choices = question.choices.map(\.nameZh).joined(separator: " / ")
            return "\(difficulty.rawValue) · 目标音程：\(question.answer.nameZh) · 选项：\(choices)"
        case let .chordQuestion(question):
            let opts = question.options.map(\.label).joined(separator: " / ")
            return "\(difficulty.rawValue) · \(question.promptZh) · 选项：\(opts)"
        case let .sightSingingConfig(pitchRange, includeAccidental, questionCount):
            let accidental = includeAccidental ? "含升降号" : "不含升降号"
            return "\(difficulty.rawValue) · 音域 \(pitchRange) · \(accidental) · \(questionCount) 题"
        case let .chordSwitch(exercise):
            return "\(difficulty.rawValue) · \(exercise.chords.joined(separator: " → ")) · \(exercise.bpm) BPM"
        case let .scaleTraining(exercise):
            return "\(difficulty.rawValue) · \(exercise.keyName) \(exercise.modeName) · \(exercise.patternName) · \(exercise.bpm) BPM"
        case let .traditionalCrawl(exercise):
            return "\(difficulty.rawValue) · 起始 \(exercise.startFret) 品 · \(exercise.rounds) 轮 · \(exercise.bpm) BPM"
        }
    }
}

/// 轻量可复现随机源：用于「同一天内」稳定打散推荐顺序。
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }
}
