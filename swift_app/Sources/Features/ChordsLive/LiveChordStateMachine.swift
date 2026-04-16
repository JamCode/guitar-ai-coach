import Foundation
import Core

public struct LiveChordUiState: Equatable {
    public let isListening: Bool
    public let mode: LiveChordMode
    public let status: String
    public let stableChord: String
    public let topK: [LiveChordCandidate]
    public let confidence: Double
    public let timeline: [String]
    public let error: String?

    public static func initial() -> LiveChordUiState {
        LiveChordUiState(
            isListening: false,
            mode: .stable,
            status: "未开始监听",
            stableChord: "Unknown",
            topK: [],
            confidence: 0,
            timeline: [],
            error: nil
        )
    }

    public func copyWith(
        isListening: Bool? = nil,
        mode: LiveChordMode? = nil,
        status: String? = nil,
        stableChord: String? = nil,
        topK: [LiveChordCandidate]? = nil,
        confidence: Double? = nil,
        timeline: [String]? = nil,
        error: String?? = nil
    ) -> LiveChordUiState {
        LiveChordUiState(
            isListening: isListening ?? self.isListening,
            mode: mode ?? self.mode,
            status: status ?? self.status,
            stableChord: stableChord ?? self.stableChord,
            topK: topK ?? self.topK,
            confidence: confidence ?? self.confidence,
            timeline: timeline ?? self.timeline,
            error: error ?? self.error
        )
    }
}

public final class LiveChordStateMachine {
    private let minConfidence: Double
    private let maxTimelineLength: Int
    private let fastModeStableHits: Int
    private let stableModeStableHits: Int
    private var stableCandidate = "Unknown"
    private var stableHits = 0

    public init(
        minConfidence: Double = 0.6,
        maxTimelineLength: Int = 8,
        fastModeStableHits: Int = 1,
        stableModeStableHits: Int = 2
    ) {
        self.minConfidence = minConfidence
        self.maxTimelineLength = maxTimelineLength
        self.fastModeStableHits = fastModeStableHits
        self.stableModeStableHits = stableModeStableHits
    }

    public func applyFrame(current: LiveChordUiState, frame: LiveChordFrame) -> LiveChordUiState {
        let best = frame.best.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = best.isEmpty ? "Unknown" : best
        let accepted = frame.confidence >= minConfidence ? candidate : "Unknown"
        let requiredHits = current.mode == .fast ? fastModeStableHits : stableModeStableHits

        if accepted == stableCandidate {
            stableHits += 1
        } else {
            stableCandidate = accepted
            stableHits = 1
        }

        var nextStable = current.stableChord
        var nextTimeline = current.timeline
        if stableHits >= requiredHits && accepted != current.stableChord {
            nextStable = accepted
            if accepted != "Unknown" {
                nextTimeline = appendTimeline(current.timeline, chord: accepted)
            }
        }

        return current.copyWith(
            status: frame.status,
            stableChord: nextStable,
            topK: frame.topK,
            confidence: frame.confidence,
            timeline: nextTimeline,
            error: .some(nil)
        )
    }

    public func reset() {
        stableCandidate = "Unknown"
        stableHits = 0
    }

    private func appendTimeline(_ timeline: [String], chord: String) -> [String] {
        var out = timeline
        if out.last == chord { return out }
        out.append(chord)
        if out.count > maxTimelineLength {
            out.removeFirst(out.count - maxTimelineLength)
        }
        return out
    }
}

