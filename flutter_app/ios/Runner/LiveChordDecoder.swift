import Foundation

/// 和弦解码器：将 12 维 chroma 转为 top‑k 和弦候选。
final class LiveChordDecoder {
  struct Candidate {
    let label: String
    let score: Double
  }

  private let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

  /// 支持的和弦模板（root + interval set）。
  private let templates: [(suffix: String, intervals: [Int])] = [
    ("", [0, 4, 7]),       // maj
    ("m", [0, 3, 7]),      // min
    ("7", [0, 4, 7, 10]),  // dominant 7
    ("m7", [0, 3, 7, 10]), // minor 7
    ("maj7", [0, 4, 7, 11]),
  ]

  func decode(chroma: [Double], topK: Int = 3) -> [Candidate] {
    guard chroma.count == 12 else { return [] }
    var out: [Candidate] = []
    for root in 0..<12 {
      for tpl in templates {
        let included = tpl.intervals.map { chroma[(root + $0) % 12] }
        let includedMean = included.reduce(0, +) / Double(included.count)

        var mask = Array(repeating: false, count: 12)
        for interval in tpl.intervals {
          mask[(root + interval) % 12] = true
        }
        let excluded = chroma.enumerated().filter { !mask[$0.offset] }.map(\.element)
        let excludedMean = excluded.isEmpty ? 0 : excluded.reduce(0, +) / Double(excluded.count)

        let score = includedMean - 0.35 * excludedMean
        let label = names[root] + tpl.suffix
        out.append(Candidate(label: label, score: max(0, score)))
      }
    }
    out.sort { $0.score > $1.score }
    return Array(out.prefix(max(1, topK)))
  }

  func confidence(from top: [Candidate]) -> Double {
    guard let first = top.first else { return 0 }
    guard top.count >= 2 else { return min(1, first.score) }
    let second = top[1]
    let margin = max(0, first.score - second.score)
    let scaled = min(1.0, first.score * 1.4 + margin * 2.2)
    return scaled
  }
}
