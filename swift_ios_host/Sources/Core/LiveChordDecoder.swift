import Foundation

public final class LiveChordDecoder {
    public struct Candidate {
        public let label: String
        public let score: Double
    }

    private let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private let templates: [(suffix: String, intervals: [Int])] = [
        ("", [0, 4, 7]),
        ("m", [0, 3, 7]),
        ("7", [0, 4, 7, 10]),
        ("m7", [0, 3, 7, 10]),
        ("maj7", [0, 4, 7, 11])
    ]

    public init() {}

    public func decode(chroma: [Double], topK: Int = 3) -> [Candidate] {
        guard chroma.count == 12 else { return [] }
        var out: [Candidate] = []
        for root in 0..<12 {
            for tpl in templates {
                let included = tpl.intervals.map { chroma[(root + $0) % 12] }
                let includedMean = included.reduce(0, +) / Double(included.count)
                var mask = Array(repeating: false, count: 12)
                for interval in tpl.intervals { mask[(root + interval) % 12] = true }
                let excluded = chroma.enumerated().filter { !mask[$0.offset] }.map(\.element)
                let excludedMean = excluded.isEmpty ? 0 : excluded.reduce(0, +) / Double(excluded.count)
                let score = includedMean - 0.35 * excludedMean
                out.append(Candidate(label: names[root] + tpl.suffix, score: max(0, score)))
            }
        }
        out.sort { $0.score > $1.score }
        return Array(out.prefix(max(1, topK)))
    }

    public func confidence(from top: [Candidate]) -> Double {
        guard let first = top.first else { return 0 }
        guard top.count >= 2 else { return min(1, first.score) }
        let second = top[1]
        let margin = max(0, first.score - second.score)
        return min(1.0, first.score * 1.4 + margin * 2.2)
    }
}

