import Foundation

public final class LiveChordEngine {
    private var sampleRate = 16_000
    private var windowSec = 2.0
    private var hopSec = 0.5
    private var confidenceThreshold = 0.6
    private var mode: LiveChordMode = .stable
    private var chunkSamplesSinceLastEval = 0
    private var ringBuffer = LiveChordAudioRingBuffer(maxSamples: 64_000)
    private let extractor = LiveChordNNLSChromaExtractor()
    private let decoder = LiveChordDecoder()
    private var stableCandidate = "Unknown"
    private var stableHits = 0

    public init() {}

    public func configure(
        sampleRate: Int,
        windowSec: Double,
        hopSec: Double,
        mode: LiveChordMode,
        confidenceThreshold: Double
    ) {
        self.sampleRate = sampleRate
        self.windowSec = windowSec
        self.hopSec = hopSec
        self.mode = mode
        self.confidenceThreshold = confidenceThreshold
        let maxSamples = Int(Double(sampleRate) * max(windowSec * 2.0, 4.0))
        ringBuffer = LiveChordAudioRingBuffer(maxSamples: maxSamples)
        reset()
    }

    public func reset() {
        ringBuffer.clear()
        chunkSamplesSinceLastEval = 0
        stableCandidate = "Unknown"
        stableHits = 0
    }

    public func process(floatChunk: [Float]) -> LiveChordFrame {
        ringBuffer.appendFloatSamples(floatChunk)
        chunkSamplesSinceLastEval += floatChunk.count

        let hopSamples = max(1, Int(Double(sampleRate) * hopSec))
        guard chunkSamplesSinceLastEval >= hopSamples else {
            return makeFrame(best: "Unknown", confidence: 0, topK: [], status: "🎵 Listening…")
        }
        chunkSamplesSinceLastEval = 0

        let windowSamples = max(1024, Int(Double(sampleRate) * windowSec))
        guard let window = ringBuffer.latestWindow(sampleCount: windowSamples) else {
            return makeFrame(best: "Unknown", confidence: 0, topK: [], status: "🎵 Listening…")
        }

        let rms = sqrt(window.reduce(0) { $0 + Double($1 * $1) } / Double(window.count))
        if rms < 0.006 {
            return makeFrame(best: "Unknown", confidence: 0, topK: [], status: "No clear chord detected")
        }

        let chroma = extractor.extractChroma(from: window, sampleRate: sampleRate)
        let top = decoder.decode(chroma: chroma, topK: 3)
        let confidence = decoder.confidence(from: top)
        let accepted = confidence >= confidenceThreshold ? (top.first?.label ?? "Unknown") : "Unknown"

        let best: String
        if mode == .fast {
            best = accepted
        } else {
            if accepted == stableCandidate {
                stableHits += 1
            } else {
                stableCandidate = accepted
                stableHits = 1
            }
            best = stableHits >= 2 ? stableCandidate : "Unknown"
        }

        let status = confidence >= confidenceThreshold ? "🎵 Listening…" : "No clear chord detected"
        let topK = top.map { LiveChordCandidate(label: $0.label, score: $0.score) }
        return makeFrame(best: best, confidence: confidence, topK: topK, status: status)
    }

    private func makeFrame(best: String, confidence: Double, topK: [LiveChordCandidate], status: String) -> LiveChordFrame {
        LiveChordFrame(
            best: best,
            topK: topK,
            confidence: confidence,
            status: status,
            timestampMs: Int(Date().timeIntervalSince1970 * 1000)
        )
    }
}

