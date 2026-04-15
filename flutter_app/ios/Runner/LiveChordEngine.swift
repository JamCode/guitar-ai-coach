import Foundation
import Flutter

/// 实时识别引擎：缓冲音频 -> 提取 chroma -> 解码和弦。
final class LiveChordEngine {
  private var sampleRate: Int = 16_000
  private var windowSec: Double = 2.0
  private var hopSec: Double = 0.5
  private var confidenceThreshold: Double = 0.6
  private var mode: String = "stable"

  private var chunkSamplesSinceLastEval: Int = 0

  private var ringBuffer = LiveChordAudioRingBuffer(maxSamples: 64_000)
  private let extractor = LiveChordNNLSChromaExtractor()
  private let decoder = LiveChordDecoder()

  private var stableCandidate: String = "Unknown"
  private var stableHits: Int = 0

  func configure(args: [String: Any]) {
    sampleRate = (args["sampleRate"] as? NSNumber)?.intValue ?? 16_000
    windowSec = (args["windowSec"] as? NSNumber)?.doubleValue ?? 2.0
    hopSec = (args["hopSec"] as? NSNumber)?.doubleValue ?? 0.5
    confidenceThreshold = (args["confidenceThreshold"] as? NSNumber)?.doubleValue ?? 0.6
    mode = (args["mode"] as? String) ?? "stable"

    let maxSamples = Int(Double(sampleRate) * max(windowSec * 2.0, 4.0))
    ringBuffer = LiveChordAudioRingBuffer(maxSamples: maxSamples)
    reset()
  }

  func reset() {
    ringBuffer.clear()
    chunkSamplesSinceLastEval = 0
    stableCandidate = "Unknown"
    stableHits = 0
  }

  func process(arguments: Any?) -> [String: Any] {
    guard
      let args = arguments as? [String: Any],
      let typed = args["pcm16le"] as? FlutterStandardTypedData
    else {
      return result(best: "Unknown", confidence: 0, topK: [], status: "No clear chord detected")
    }

    ringBuffer.appendPCM16LE(typed.data)
    chunkSamplesSinceLastEval += typed.data.count / 2

    let hopSamples = max(1, Int(Double(sampleRate) * hopSec))
    guard chunkSamplesSinceLastEval >= hopSamples else {
      return result(best: "Unknown", confidence: 0, topK: [], status: "🎵 Listening…")
    }
    chunkSamplesSinceLastEval = 0

    let windowSamples = max(1024, Int(Double(sampleRate) * windowSec))
    guard let window = ringBuffer.latestWindow(sampleCount: windowSamples) else {
      return result(best: "Unknown", confidence: 0, topK: [], status: "🎵 Listening…")
    }

    let rms = sqrt(window.reduce(0) { $0 + Double($1 * $1) } / Double(window.count))
    if rms < 0.006 {
      return result(best: "Unknown", confidence: 0, topK: [], status: "No clear chord detected")
    }

    let chroma = extractor.extractChroma(from: window, sampleRate: sampleRate)
    let top = decoder.decode(chroma: chroma, topK: 3)
    let confidence = decoder.confidence(from: top)

    let accepted = confidence >= confidenceThreshold ? (top.first?.label ?? "Unknown") : "Unknown"
    let best: String
    if mode == "fast" {
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

    let topKPayload = top.map { ["label": $0.label, "score": $0.score] }
    let status = confidence >= confidenceThreshold ? "🎵 Listening…" : "No clear chord detected"
    return result(best: best, confidence: confidence, topK: topKPayload, status: status)
  }

  private func result(
    best: String,
    confidence: Double,
    topK: [[String: Any]],
    status: String
  ) -> [String: Any] {
    return [
      "best": best,
      "confidence": confidence,
      "status": status,
      "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
      "topK": topK,
    ]
  }
}
