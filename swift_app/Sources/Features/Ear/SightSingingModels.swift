import Foundation

public enum SightSingingExerciseKind: String, Sendable, CaseIterable, Identifiable {
    /// 模唱单音：每题 1 个目标音高。
    case singleNoteMimic = "single_note_mimic"
    /// 模唱音程：每题 2 个目标音高（上行，低音 → 高音）。
    case intervalMimic = "interval_mimic"

    public var id: String { rawValue }

    public var titleZh: String {
        switch self {
        case .singleNoteMimic:
            return "模唱单音"
        case .intervalMimic:
            return "模唱音程"
        }
    }
}

public struct SightSingingConfig: Sendable {
    public let minNote: String
    public let maxNote: String
    public let questionCount: Int
    public let includeAccidental: Bool
    public let exerciseKind: SightSingingExerciseKind
}

public struct SightSingingQuestion: Sendable, Identifiable {
    public let id: String
    public let index: Int
    public let totalQuestions: Int
    public let targetNotes: [String]
}

public struct SightSingingResult: Sendable {
    public let answered: Int
    public let correct: Int
    public let total: Int
    public let accuracy: Double
}

public struct SightSingingSessionStart: Sendable {
    public let sessionId: String
    public let config: SightSingingConfig
    public let question: SightSingingQuestion?
}

public struct SightSingingScore: Sendable {
    public let score: Double
    public let avgCentsAbs: Double
    public let stableHitMs: Int
    public let isCorrect: Bool
}

public func computeSightSingingScore(absCentsSamples: [Double], sampleStepMs: Int) -> SightSingingScore {
    guard !absCentsSamples.isEmpty else {
        return SightSingingScore(score: 0, avgCentsAbs: 99, stableHitMs: 0, isCorrect: false)
    }
    var totalWeight = 0.0
    var totalCents = 0.0
    var currentStableMs = 0
    var bestStableMs = 0

    for cents in absCentsSamples {
        totalCents += cents
        switch cents {
        case ...15: totalWeight += 1.0
        case ...30: totalWeight += 0.7
        case ...50: totalWeight += 0.3
        default: break
        }
        if cents <= 30 {
            currentStableMs += sampleStepMs
            bestStableMs = max(bestStableMs, currentStableMs)
        } else {
            currentStableMs = 0
        }
    }
    let avgWeight = totalWeight / Double(absCentsSamples.count)
    var score = avgWeight * 10
    if bestStableMs < 500, score > 6 {
        score = 6
    }
    let avgCents = totalCents / Double(absCentsSamples.count)
    let clamped = min(10, max(0, score))
    return SightSingingScore(
        score: clamped,
        avgCentsAbs: avgCents,
        stableHitMs: bestStableMs,
        isCorrect: clamped >= 6
    )
}
