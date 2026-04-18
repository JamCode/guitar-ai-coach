import Foundation
import Chords

/// 和弦进行（Bank B）程序化难度：与和弦听辨 `EarChordMcqDifficulty` 分离，避免语义混淆。
public enum EarProgressionMcqDifficulty: String, Sendable, CaseIterable, Codable {
    case 初级
    case 中级
    case 高级
}

/// 规则生成和弦进行四选一题（不读 `ear_seed` Bank B）。
public enum EarProgressionProceduralGenerator {
    private static let romanTokens = ["I", "ii", "iii", "IV", "V", "vi"]

    private static let templatesByN: [Int: [String]] = [
        3: ["ii-V-I", "I-IV-V", "vi-IV-I", "I-V-vi", "IV-V-I"],
        4: ["I-V-vi-IV", "vi-IV-I-V", "I-vi-IV-V", "I-IV-V-I", "ii-V-I-IV"],
        5: ["I-vi-IV-V-I", "ii-V-I-vi-IV", "I-IV-vi-V-I", "vi-IV-I-V-vi", "I-V-vi-IV-I"],
    ]

    public static func keys(for difficulty: EarProgressionMcqDifficulty) -> [String] {
        switch difficulty {
        case .初级:
            return ["C", "G", "D", "F"]
        case .中级:
            return ["C", "G", "D", "F", "A", "E", "Bb"]
        case .高级:
            return ["C", "G", "D", "F", "A", "E", "Bb", "B", "Db", "Eb", "Ab"]
        }
    }

    public static func makeQuestion(
        difficulty: EarProgressionMcqDifficulty,
        using rng: inout some RandomNumberGenerator
    ) -> EarBankItem {
        let n: Int
        switch difficulty {
        case .初级: n = 3
        case .中级: n = 4
        case .高级: n = 5
        }
        let keys = Self.keys(for: difficulty)
        let templates = Self.templatesByN[n] ?? ["I-IV-V"]
        var musicKey = keys.randomElement(using: &rng)!
        var progressionRoman = templates[0]
        for _ in 0 ..< 64 {
            musicKey = keys.randomElement(using: &rng)!
            progressionRoman = templates.randomElement(using: &rng)!
            let probe = stubItem(musicKey: musicKey, progressionRoman: progressionRoman)
            if EarProgressionPlayback.playbackFretsSequence(for: probe) != nil {
                break
            }
        }
        let wrong = makeWrongLabels(correct: progressionRoman, n: n, using: &rng)
        let (options, correctKey) = shuffleOptions(correctLabel: progressionRoman, wrong: wrong, using: &rng)
        return EarBankItem(
            id: UUID().uuidString,
            mode: "B",
            questionType: "progression_recognition",
            promptZh: "听和弦进行，选择最符合的一项",
            options: options,
            correctOptionKey: correctKey,
            root: nil,
            targetQuality: nil,
            musicKey: musicKey,
            progressionRoman: progressionRoman,
            hintZh: hintZh(for: difficulty),
            playbackFretsSixToOne: nil
        )
    }

    private static func stubItem(musicKey: String, progressionRoman: String) -> EarBankItem {
        EarBankItem(
            id: "stub",
            mode: "B",
            questionType: "progression_recognition",
            promptZh: "",
            options: [EarMcqOption(key: "A", label: progressionRoman)],
            correctOptionKey: "A",
            root: nil,
            targetQuality: nil,
            musicKey: musicKey,
            progressionRoman: progressionRoman,
            hintZh: nil,
            playbackFretsSixToOne: nil
        )
    }

    private static func hintZh(for difficulty: EarProgressionMcqDifficulty) -> String {
        switch difficulty {
        case .初级:
            return "常见终止与正格进行"
        case .中级:
            return "流行主副歌常见进行"
        case .高级:
            return "较长进行，注意听低音与功能"
        }
    }

    private static func shuffleOptions(
        correctLabel: String,
        wrong: [String],
        using rng: inout some RandomNumberGenerator
    ) -> (options: [EarMcqOption], correctKey: String) {
        precondition(wrong.count == 3)
        var labels = wrong + [correctLabel]
        labels.shuffle(using: &rng)
        let keys = ["A", "B", "C", "D"]
        let options = zip(keys, labels).map { EarMcqOption(key: $0.0, label: $0.1) }
        let correctKey = options.first { $0.label == correctLabel }!.key
        return (options, correctKey)
    }

    private static func makeWrongLabels(
        correct: String,
        n: Int,
        using rng: inout some RandomNumberGenerator
    ) -> [String] {
        var pool = (templatesByN[n] ?? []).filter { $0 != correct }
        pool.shuffle(using: &rng)
        var out: [String] = []
        for p in pool where out.count < 3 {
            if !out.contains(p) { out.append(p) }
        }
        var attempts = 0
        while out.count < 3 && attempts < 300 {
            attempts += 1
            if let m = randomMutant(from: correct, using: &rng),
               m != correct,
               !out.contains(m),
               EarPlaybackMidi.romanNumeralSegmentCount(m) == n
            {
                out.append(m)
            }
        }
        precondition(
            out.count == 3,
            "could not build 3 distractors for correct=\(correct) n=\(n); extend templates or mutator"
        )
        return out
    }

    private static func randomMutant(from correct: String, using rng: inout some RandomNumberGenerator) -> String? {
        var parts = correct.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        let idx = Int.random(in: 0 ..< parts.count, using: &rng)
        let old = parts[idx]
        guard let replacement = romanTokens.filter({ $0 != old }).randomElement(using: &rng) else { return nil }
        parts[idx] = replacement
        return parts.joined(separator: "-")
    }
}
