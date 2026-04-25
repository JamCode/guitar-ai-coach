import Foundation

/// 和弦进行（Bank B）程序化难度：与和弦听辨 `EarChordMcqDifficulty` 分离，避免语义混淆。
public enum EarProgressionMcqDifficulty: String, Sendable, CaseIterable, Codable {
    case 初级
    case 中级
    case 高级
}

public extension EarProgressionMcqDifficulty {
    static let helpText: [EarProgressionMcqDifficulty: String] = [
        .初级: "常见终止与正格进行",
        .中级: "流行主副歌常见进行",
        .高级: "较长进行，注意听低音与功能",
    ]
}

/// 程序化生成和弦进行四选一题（不读 `ear_seed` Bank B）。
/// 和声由 `EarProgressionHarmonyEngine` 按功能层 + 评分加权步进生成，再校验吉他可弹性。
public enum EarProgressionProceduralGenerator {
    private static let romanTokens = ["I", "ii", "iii", "IV", "V", "vi", "V7", "ii7", "vi7", "bVI", "bIII", "iv", "(V/ii)", "(V/vi)"]

    private static func length(for difficulty: EarProgressionMcqDifficulty) -> Int {
        switch difficulty {
        case .初级: return 3
        case .中级: return 4
        case .高级: return 5
        }
    }

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
        let n = length(for: difficulty)
        let keys = Self.keys(for: difficulty)
        let playable = firstPlayableProgression(difficulty: difficulty, keys: keys, n: n, using: &rng)
        let musicKey = playable.musicKey
        let progressionRoman = playable.progressionRoman
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
            hintZh: EarProgressionMcqDifficulty.helpText[difficulty],
            playbackFretsSixToOne: nil
        )
    }

    /// 供单测/调试复用；实现委托给 `EarProgressionPlayback`。
    public static func isProgressionPlayable(musicKey: String, progressionRoman: String) -> Bool {
        EarProgressionPlayback.isProgressionPlayable(musicKey: musicKey, progressionRoman: progressionRoman)
    }

    private static func firstPlayableProgression(
        difficulty: EarProgressionMcqDifficulty,
        keys: [String],
        n: Int,
        using rng: inout some RandomNumberGenerator
    ) -> (musicKey: String, progressionRoman: String) {
        for _ in 0 ..< 48 {
            let line = EarProgressionHarmonyEngine.generateProgressionRoman(
                difficulty: difficulty,
                length: n,
                using: &rng
            )
            for _ in 0 ..< min(24, keys.count * 4) {
                let musicKey = keys.randomElement(using: &rng)!
                if isProgressionPlayable(musicKey: musicKey, progressionRoman: line) {
                    return (musicKey, line)
                }
            }
        }
        let line = EarProgressionHarmonyEngine.generateProgressionRoman(
            difficulty: difficulty,
            length: n,
            using: &rng
        )
        for musicKey in keys where isProgressionPlayable(musicKey: musicKey, progressionRoman: line) {
            return (musicKey, line)
        }
        let safe = n <= 4 ? "I-IV-V-I" : "I-vi-IV-V-I"
        for musicKey in keys where isProgressionPlayable(musicKey: musicKey, progressionRoman: safe) {
            return (musicKey, safe)
        }
        preconditionFailure("could not find playable progression for n=\(n); keys=\(keys)")
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
        var out: [String] = []
        var guardRng = 0
        while out.count < 3 && guardRng < 400 {
            guardRng += 1
            let alt = EarProgressionHarmonyEngine.generateProgressionRoman(
                difficulty: .中级,
                length: n,
                using: &rng
            )
            if alt != correct, !out.contains(alt), EarPlaybackMidi.romanNumeralSegmentCount(alt) == n {
                out.append(alt)
            }
        }
        var mutAttempts = 0
        while out.count < 3 && mutAttempts < 500 {
            mutAttempts += 1
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
            "could not build 3 distractors for correct=\(correct) n=\(n)"
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
