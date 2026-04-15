import Foundation

public struct LiveChordCandidate: Hashable, Sendable {
    public let label: String
    public let score: Double

    public init(label: String, score: Double) {
        self.label = label
        self.score = score
    }
}

public struct LiveChordFrame: Hashable, Sendable {
    public let best: String
    public let topK: [LiveChordCandidate]
    public let confidence: Double
    public let status: String
    public let timestampMs: Int

    public init(
        best: String,
        topK: [LiveChordCandidate],
        confidence: Double,
        status: String,
        timestampMs: Int
    ) {
        self.best = best
        self.topK = topK
        self.confidence = confidence
        self.status = status
        self.timestampMs = timestampMs
    }
}

public enum LiveChordMode: String, Sendable {
    case fast
    case stable
}

