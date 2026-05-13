import Foundation
import Ear

enum AdaptiveEarQuestionKind: String, CaseIterable, Codable, Equatable {
    case interval
    case chord
    case progression
    case singleNote

    var title: String {
        switch self {
        case .interval: return "音程识别"
        case .chord: return "和弦听辨"
        case .progression: return "和弦进行听辨"
        case .singleNote: return "单音测试"
        }
    }

    var shortTitle: String {
        switch self {
        case .interval: return "音程"
        case .chord: return "和弦"
        case .progression: return "进行"
        case .singleNote: return "单音"
        }
    }
}

enum AdaptiveEarDifficulty: String, Codable, Equatable {
    case beginner
    case intermediate
    case advanced

    var title: String {
        switch self {
        case .beginner: return "初级"
        case .intermediate: return "中级"
        case .advanced: return "高级"
        }
    }

    var intervalDifficulty: IntervalEarDifficulty {
        switch self {
        case .beginner: return .初级
        case .intermediate: return .中级
        case .advanced: return .高级
        }
    }

    var chordDifficulty: EarChordMcqDifficulty {
        switch self {
        case .beginner: return .初级
        case .intermediate: return .中级
        case .advanced: return .高级
        }
    }

    var progressionDifficulty: EarProgressionMcqDifficulty {
        switch self {
        case .beginner: return .初级
        case .intermediate: return .中级
        case .advanced: return .高级
        }
    }
}

struct SingleNoteQuestion: Codable, Equatable {
    /// 目标音 MIDI 编号
    let midi: Int
    /// 显示用的音名，如 "C"（初级/中级）或 "C4"（高级）
    let noteLabel: String
    /// 四个选项
    let choices: [SingleNoteChoice]

    struct SingleNoteChoice: Codable, Equatable, Identifiable {
        let id: String
        let label: String
    }
}

enum AdaptiveEarQuestion: Identifiable {
    case interval(IntervalQuestion, difficulty: AdaptiveEarDifficulty, difficultyScore: Int)
    case chord(EarBankItem, difficulty: AdaptiveEarDifficulty, difficultyScore: Int)
    case progression(EarBankItem, difficulty: AdaptiveEarDifficulty, difficultyScore: Int)
    case singleNote(SingleNoteQuestion, difficulty: AdaptiveEarDifficulty, difficultyScore: Int)

    var id: String {
        stableQuestionId
    }

    var stableQuestionId: String {
        switch self {
        case let .interval(q, _, _):
            return "interval-\(q.lowMidi)-\(q.highMidi)-\(q.answer.semitones)"
        case let .chord(q, _, _), let .progression(q, _, _):
            return q.id
        case let .singleNote(q, _, _):
            return "singlenote-\(q.midi)"
        }
    }

    var kind: AdaptiveEarQuestionKind {
        switch self {
        case .interval: return .interval
        case .chord: return .chord
        case .progression: return .progression
        case .singleNote: return .singleNote
        }
    }

    var difficulty: AdaptiveEarDifficulty {
        switch self {
        case let .interval(_, d, _), let .chord(_, d, _), let .progression(_, d, _), let .singleNote(_, d, _):
            return d
        }
    }

    var difficultyScore: Int {
        switch self {
        case let .interval(_, _, s), let .chord(_, _, s), let .progression(_, _, s), let .singleNote(_, _, s):
            return s
        }
    }

    var prompt: String {
        switch self {
        case .interval:
            return "听一遍，选出两个音之间的音程"
        case let .chord(q, _, _), let .progression(q, _, _):
            return q.promptZh
        case .singleNote:
            return "听标准音 A4（440Hz），判断接下来听到的是哪个音"
        }
    }

    var choices: [AdaptiveEarChoice] {
        switch self {
        case let .interval(q, _, _):
            return q.choices.map { AdaptiveEarChoice(id: "\($0.semitones)", label: $0.nameZh) }
        case let .chord(q, _, _), let .progression(q, _, _):
            return q.options.map { AdaptiveEarChoice(id: $0.key, label: $0.label) }
        case let .singleNote(q, _, _):
            return q.choices.map { AdaptiveEarChoice(id: $0.id, label: $0.label) }
        }
    }

    var correctChoiceId: String {
        switch self {
        case let .interval(q, _, _):
            return "\(q.answer.semitones)"
        case let .chord(q, _, _), let .progression(q, _, _):
            return q.correctOptionKey
        case let .singleNote(q, _, _):
            return q.choices.first(where: { $0.label == q.noteLabel })?.id ?? ""
        }
    }

    var correctAnswerText: String {
        switch self {
        case let .interval(q, _, _):
            return q.answer.nameZh
        case let .chord(q, _, _), let .progression(q, _, _):
            return q.options.first(where: { $0.key == q.correctOptionKey })?.label ?? ""
        case let .singleNote(q, _, _):
            return q.noteLabel
        }
    }

    var explanation: String {
        switch self {
        case let .interval(q, _, _):
            return q.answer.teachZh
        case let .chord(q, _, _):
            return Self.chordExplanation(q)
        case let .progression(q, _, _):
            let marks = EarProgressionPlayback.progressionMarkText(for: q)
            if marks.isEmpty {
                return q.hintZh ?? "注意听低音走向和每个和弦的功能变化。"
            }
            return "实际和弦：\(marks)。\(q.hintZh ?? "注意听低音走向和每个和弦的功能变化。")"
        case let .singleNote(q, _, _):
            let name = Self.scientificPitchLabel(midi: q.midi)
            return "本题音是 \(name)（MIDI \(q.midi)）"
        }
    }

    private static func chordExplanation(_ item: EarBankItem) -> String {
        guard let token = item.targetQuality, let quality = EarChordQuality(targetQualityToken: token) else {
            return item.hintZh ?? "先抓住和弦整体明暗，再判断七和弦色彩。"
        }
        switch quality {
        case .major:
            return "大三和弦更明亮、稳定，三音到根音是大三度。"
        case .minor:
            return "小三和弦更柔和、偏暗，三音到根音是小三度。"
        case .dominant7:
            return "属七和弦比三和弦多一个小七度，听感更有解决倾向。"
        case .major7:
            return "大七和弦明亮但带悬浮感，顶音离根音只差半音。"
        case .minor7:
            return "小七和弦保留小三和弦的暗色，同时多了更松弛的七度。"
        }
    }

    private static func scientificPitchLabel(midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let pc = midi % 12
        let octave = (midi / 12) - 1
        return "\(names[pc])\(octave)"
    }
}

struct AdaptiveEarChoice: Identifiable, Equatable {
    let id: String
    let label: String
}

struct AdaptiveEarAbilityState: Codable, Equatable {
    var overallEarRating: Double
    var intervalRating: Double
    var chordRating: Double
    var progressionRating: Double
    var singleNoteRating: Double
    var totalAnswered: Int
    var consecutiveCorrect: Int
    var consecutiveWrong: Int
    var lastQuestionKindRaw: String?

    static let initial = AdaptiveEarAbilityState(
        overallEarRating: 400,
        intervalRating: 400,
        chordRating: 400,
        progressionRating: 400,
        singleNoteRating: 400,
        totalAnswered: 0,
        consecutiveCorrect: 0,
        consecutiveWrong: 0,
        lastQuestionKindRaw: nil
    )

    var roundedOverallRating: Int { Int(overallEarRating.rounded()) }

    /// 将评分换算为等级（400→Lv1，每 50 分升一级，最高 Lv10）
    static func level(for rating: Double) -> Int {
        let l = (Int(rating.rounded()) - 400) / 50 + 1
        return max(1, min(10, l))
    }

    var level: Int { Self.level(for: overallEarRating) }
    var levelTitle: String { "Lv\(level)" }

    func rating(for kind: AdaptiveEarQuestionKind) -> Double {
        switch kind {
        case .interval: return intervalRating
        case .chord: return chordRating
        case .progression: return progressionRating
        case .singleNote: return singleNoteRating
        }
    }

    mutating func setRating(_ value: Double, for kind: AdaptiveEarQuestionKind) {
        switch kind {
        case .interval: intervalRating = value
        case .chord: chordRating = value
        case .progression: progressionRating = value
        case .singleNote: singleNoteRating = value
        }
    }
}

struct AdaptiveEarAttemptRecord: Codable, Equatable, Identifiable {
    let id: String
    let questionKindRaw: String
    let questionId: String
    let difficultyRaw: String
    let difficultyScore: Int
    let correctAnswer: String
    let selectedAnswer: String?
    let wasCorrect: Bool
    let responseTimeMs: Int
    let answeredAt: Date
    let ratingBeforeOverall: Double
    let ratingAfterOverall: Double
    let ratingBeforeKind: Double
    let ratingAfterKind: Double
    let skipped: Bool

    var questionKind: AdaptiveEarQuestionKind {
        AdaptiveEarQuestionKind(rawValue: questionKindRaw) ?? .interval
    }
}

enum AdaptiveEarTrainingEngine {
    static func expectedCorrectProbability(rating: Double, difficultyScore: Int) -> Double {
        1.0 / (1.0 + pow(10.0, (Double(difficultyScore) - rating) / 400.0))
    }

    static func updatedRating(current: Double, difficultyScore: Int, wasCorrect: Bool, totalAnswered: Int) -> Double {
        let k = totalAnswered < 30 ? 40.0 : 20.0
        let expected = expectedCorrectProbability(rating: current, difficultyScore: difficultyScore)
        let actual = wasCorrect ? 1.0 : 0.0
        return max(100, min(900, current + k * (actual - expected)))
    }

    static func stateAfterAnswer(
        state: AdaptiveEarAbilityState,
        kind: AdaptiveEarQuestionKind,
        difficultyScore: Int,
        wasCorrect: Bool
    ) -> AdaptiveEarAbilityState {
        var next = state
        let beforeKind = state.rating(for: kind)
        let afterKind = updatedRating(
            current: beforeKind,
            difficultyScore: difficultyScore,
            wasCorrect: wasCorrect,
            totalAnswered: state.totalAnswered
        )
        let afterOverall = updatedRating(
            current: state.overallEarRating,
            difficultyScore: difficultyScore,
            wasCorrect: wasCorrect,
            totalAnswered: state.totalAnswered
        )
        next.setRating(afterKind, for: kind)
        next.overallEarRating = afterOverall
        next.totalAnswered += 1
        next.consecutiveCorrect = wasCorrect ? state.consecutiveCorrect + 1 : 0
        next.consecutiveWrong = wasCorrect ? 0 : state.consecutiveWrong + 1
        next.lastQuestionKindRaw = kind.rawValue
        return next
    }

    static func recentAccuracy(records: [AdaptiveEarAttemptRecord], limit: Int = 20) -> Double? {
        let recent = records.suffix(limit)
        guard !recent.isEmpty else { return nil }
        let correct = recent.filter(\.wasCorrect).count
        return Double(correct) / Double(recent.count)
    }

    static func recentAccuracy(
        for kind: AdaptiveEarQuestionKind,
        records: [AdaptiveEarAttemptRecord],
        limit: Int = 12
    ) -> Double? {
        let recent = records.filter { $0.questionKind == kind }.suffix(limit)
        guard !recent.isEmpty else { return nil }
        let correct = recent.filter(\.wasCorrect).count
        return Double(correct) / Double(recent.count)
    }

    static func weakestKind(state: AdaptiveEarAbilityState, records: [AdaptiveEarAttemptRecord]) -> AdaptiveEarQuestionKind {
        AdaptiveEarQuestionKind.allCases.min { lhs, rhs in
            weaknessScore(kind: lhs, state: state, records: records) < weaknessScore(kind: rhs, state: state, records: records)
        } ?? .interval
    }

    static func selectNextKind(
        state: AdaptiveEarAbilityState,
        records: [AdaptiveEarAttemptRecord],
        roll: Double
    ) -> AdaptiveEarQuestionKind {
        let weakest = weakestKind(state: state, records: records)
        if roll < 0.60 {
            return weakest
        }
        if roll < 0.85 {
            return mainlineKind(state: state)
        }
        return reviewKind(state: state, excluding: weakest)
    }

    static func difficulty(for kind: AdaptiveEarQuestionKind, state: AdaptiveEarAbilityState) -> AdaptiveEarDifficulty {
        var level = baseDifficulty(forRating: state.rating(for: kind))
        if state.consecutiveWrong >= 2 {
            level = lower(level)
        } else if state.consecutiveCorrect >= 3 {
            level = higher(level)
        }
        return level
    }

    static func difficultyScore(kind: AdaptiveEarQuestionKind, difficulty: AdaptiveEarDifficulty) -> Int {
        switch (kind, difficulty) {
        case (.interval, .beginner): return 330
        case (.interval, .intermediate): return 500
        case (.interval, .advanced): return 660
        case (.chord, .beginner): return 360
        case (.chord, .intermediate): return 520
        case (.chord, .advanced): return 680
        case (.progression, .beginner): return 380
        case (.progression, .intermediate): return 540
        case (.progression, .advanced): return 700
        case (.singleNote, .beginner): return 300
        case (.singleNote, .intermediate): return 470
        case (.singleNote, .advanced): return 630
        }
    }

    static func recommendationLine(state: AdaptiveEarAbilityState, records: [AdaptiveEarAttemptRecord]) -> String {
        guard !records.isEmpty else {
            return "先用几道题校准听力值，系统会自动调整下一题难度。"
        }
        let weak = weakestKind(state: state, records: records)
        let accuracyText: String
        if let acc = recentAccuracy(for: weak, records: records) {
            accuracyText = "近题正确率 \(Int((acc * 100).rounded()))%"
        } else {
            accuracyText = "样本较少"
        }
        return "最近\(weak.shortTitle)偏弱（\(accuracyText)），下一题会优先补这块。"
    }

    private static func weaknessScore(
        kind: AdaptiveEarQuestionKind,
        state: AdaptiveEarAbilityState,
        records: [AdaptiveEarAttemptRecord]
    ) -> Double {
        let accuracy = recentAccuracy(for: kind, records: records) ?? 0.55
        return accuracy * 1000 + state.rating(for: kind)
    }

    private static func mainlineKind(state: AdaptiveEarAbilityState) -> AdaptiveEarQuestionKind {
        AdaptiveEarQuestionKind.allCases.min { lhs, rhs in
            abs(state.rating(for: lhs) - state.overallEarRating) < abs(state.rating(for: rhs) - state.overallEarRating)
        } ?? .chord
    }

    private static func reviewKind(
        state: AdaptiveEarAbilityState,
        excluding weakest: AdaptiveEarQuestionKind
    ) -> AdaptiveEarQuestionKind {
        AdaptiveEarQuestionKind.allCases
            .filter { $0 != weakest }
            .max { lhs, rhs in state.rating(for: lhs) < state.rating(for: rhs) }
            ?? .interval
    }

    private static func baseDifficulty(forRating rating: Double) -> AdaptiveEarDifficulty {
        switch rating {
        case ..<500: return .beginner
        case ..<650: return .intermediate
        default: return .advanced
        }
    }

    private static func lower(_ level: AdaptiveEarDifficulty) -> AdaptiveEarDifficulty {
        switch level {
        case .beginner: return .beginner
        case .intermediate: return .beginner
        case .advanced: return .intermediate
        }
    }

    private static func higher(_ level: AdaptiveEarDifficulty) -> AdaptiveEarDifficulty {
        switch level {
        case .beginner: return .intermediate
        case .intermediate: return .advanced
        case .advanced: return .advanced
        }
    }
}
