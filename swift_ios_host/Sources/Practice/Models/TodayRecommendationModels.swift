import Foundation
import Ear

enum RecommendationDifficultyLevel: String, CaseIterable, Identifiable {
    case beginner = "初级"
    case intermediate = "中级"
    case advanced = "高级"

    var id: String { rawValue }
}

enum RecommendationModuleType: String, CaseIterable, Identifiable, Codable {
    case intervalEar
    case chordEar
    case sightSinging
    case chordSwitch
    case scaleTraining
    case traditionalCrawl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intervalEar: return "音程识别"
        case .chordEar: return "和弦听辨"
        case .sightSinging: return "视唱训练"
        case .chordSwitch: return "和弦切换"
        case .scaleTraining: return "音阶训练"
        case .traditionalCrawl: return "传统爬格子"
        }
    }

    var icon: String {
        switch self {
        case .intervalEar: return "ear"
        case .chordEar: return "pianokeys"
        case .sightSinging: return "mic"
        case .chordSwitch: return "guitars"
        case .scaleTraining: return "music.note.list"
        case .traditionalCrawl: return "figure.walk"
        }
    }
}

struct RecommendationHistoryRecord: Codable, Equatable, Sendable {
    let module: RecommendationModuleType
    let completed: Bool
    let successRate: Double
    let durationSeconds: Int
    let occurredAt: Date
}

struct ChordSwitchExercise {
    let chords: [String]
    let bpm: Int
}

struct ScaleTrainingExercise {
    let keyName: String
    let modeName: String
    let patternName: String
    let bpm: Int
}

struct TraditionalCrawlExercise {
    let startFret: Int
    let rounds: Int
    let bpm: Int
}

enum RecommendationPayload {
    case intervalQuestion(IntervalQuestion)
    case chordQuestion(EarBankItem)
    case sightSingingConfig(
        pitchRange: String,
        includeAccidental: Bool,
        questionCount: Int,
        exerciseKind: SightSingingExerciseKind
    )
    case chordSwitch(ChordSwitchExercise)
    case scaleTraining(ScaleTrainingExercise)
    case traditionalCrawl(TraditionalCrawlExercise)
}

struct TodayRecommendationItem: Identifiable {
    let module: RecommendationModuleType
    let difficulty: RecommendationDifficultyLevel
    let reason: String
    let summary: String
    let payload: RecommendationPayload

    var id: String { module.rawValue }
}
