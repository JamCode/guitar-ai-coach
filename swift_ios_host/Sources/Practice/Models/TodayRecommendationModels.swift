import Core
import Ear
import Foundation
import Practice

enum RecommendationDifficultyLevel: String, CaseIterable, Identifiable {
    case beginner = "初级"
    case intermediate = "中级"
    case advanced = "高级"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .beginner: return AppL10n.t("rec_diff_beginner")
        case .intermediate: return AppL10n.t("rec_diff_intermediate")
        case .advanced: return AppL10n.t("rec_diff_advanced")
        }
    }
}

enum RecommendationModuleType: String, CaseIterable, Identifiable, Codable {
    case intervalEar
    case chordEar
    case sightSinging
    case chordSwitch
    case scaleTraining
    case traditionalCrawl

    var id: String { rawValue }

    /// 展示用；`Codable` 仍用英文 `rawValue`（如 `intervalEar`）。
    var localizedTitle: String {
        switch self {
        case .intervalEar: return AppL10n.t("task_interval_ear_name")
        case .chordEar: return AppL10n.t("task_ear_chord_mcq_name")
        case .sightSinging: return AppL10n.t("task_sight_singing_name")
        case .chordSwitch: return AppL10n.t("task_chord_switch_name")
        case .scaleTraining: return AppL10n.t("rec_mod_scale_training")
        case .traditionalCrawl: return AppL10n.t("rec_mod_traditional_crawl")
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
