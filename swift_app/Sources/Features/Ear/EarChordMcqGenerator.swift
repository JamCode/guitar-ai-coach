import Foundation

// MARK: - 难度（和弦听辨 bank A：程序化、无固定题库）

/// 和弦性质听辨难度：内部映射「可选和弦性质集合」「根音范围」与「正确答案池」。
public enum EarChordMcqDifficulty: String, Sendable, CaseIterable, Codable {
    case 初级
    case 中级
    case 高级
}

public extension EarChordMcqDifficulty {
    static let helpText: [EarChordMcqDifficulty: String] = [
        .初级: "答案仅在大三 / 小三中抽选；四选项为大三、小三、属七、大七；根音以自然音级为主。",
        .中级: "答案在大三、小三、属七中抽选；选项池同上；根音略增（含 F、Bb）。",
        .高级: "五种常见性质（大/小/属七/大七/小七）均可成为正确答案；根音覆盖全部半音。",
    ]
}

// MARK: - 和弦性质（与 `EarPlaybackMidi.forSingleChord` 的 target_quality 对齐）

public enum EarChordQuality: String, Sendable, Hashable, CaseIterable {
    case major
    case minor
    case dominant7
    case major7
    case minor7

    public var labelZh: String {
        switch self {
        case .major: return "大三"
        case .minor: return "小三"
        case .dominant7: return "属七"
        case .major7: return "大七"
        case .minor7: return "小七"
        }
    }

    /// 写入 `EarBankItem.targetQuality`，供播放与合成使用。
    public var targetQualityToken: String {
        switch self {
        case .major: return "major"
        case .minor: return "minor"
        case .dominant7: return "dominant7"
        case .major7: return "major7"
        case .minor7: return "minor7"
        }
    }

    public init?(targetQualityToken: String) {
        let t = targetQualityToken.lowercased()
        switch t {
        case "major", "maj": self = .major
        case "minor", "min", "m": self = .minor
        case "dominant7", "7", "dom7": self = .dominant7
        case "major7", "maj7", "m7maj", "delta": self = .major7
        case "minor7", "min7", "m7": self = .minor7
        default: return nil
        }
    }
}

// MARK: - 预设

public struct EarChordMcqPreset: Sendable {
    /// 本题四选项所展示的和弦性质集合（高级为 5 取 4 题面时由生成器从中抽答案与干扰）
    public let optionQualities: [EarChordQuality]
    /// 正确答案可抽中的性质
    public let answerQualities: [EarChordQuality]
    public let roots: [String]
}

// MARK: - 出题

public enum EarChordMcqGenerator {
    public static func preset(for difficulty: EarChordMcqDifficulty) -> EarChordMcqPreset {
        let four: [EarChordQuality] = [.major, .minor, .dominant7, .major7]
        switch difficulty {
        case .初级:
            return EarChordMcqPreset(
                optionQualities: four,
                answerQualities: [.major, .minor],
                roots: ["C", "G", "D", "A", "E"]
            )
        case .中级:
            return EarChordMcqPreset(
                optionQualities: four,
                answerQualities: [.major, .minor, .dominant7],
                roots: ["C", "G", "D", "A", "E", "F", "Bb"]
            )
        case .高级:
            return EarChordMcqPreset(
                optionQualities: [.major, .minor, .dominant7, .major7, .minor7],
                answerQualities: [.major, .minor, .dominant7, .major7, .minor7],
                roots: ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
            )
        }
    }

    /// 组卷：每题独立随机；尽量避免与上一题完全相同的「根音 + 性质」。
    public static func buildSession(
        count: Int,
        difficulty: EarChordMcqDifficulty,
        using rng: inout some RandomNumberGenerator
    ) -> [EarBankItem] {
        let n = max(1, count)
        var out: [EarBankItem] = []
        var last: (root: String, quality: EarChordQuality)?
        out.reserveCapacity(n)
        for _ in 0 ..< n {
            let q = makeQuestion(difficulty: difficulty, avoid: last, using: &rng)
            if let r = q.root, let tok = q.targetQuality, let qual = EarChordQuality(targetQualityToken: tok) {
                last = (r, qual)
            }
            out.append(q)
        }
        return out
    }

    public static func makeQuestion(
        difficulty: EarChordMcqDifficulty,
        avoid: (root: String, quality: EarChordQuality)? = nil,
        using rng: inout some RandomNumberGenerator
    ) -> EarBankItem {
        let p = preset(for: difficulty)
        let answer = p.answerQualities.randomElement(using: &rng)!
        let wrongPool = p.optionQualities.filter { $0 != answer }
        let scored = wrongPool.map { (q: $0, s: distractorScore(correct: answer, wrong: $0)) }
            .sorted { lhs, rhs in
                if lhs.s != rhs.s { return lhs.s > rhs.s }
                return Bool.random(using: &rng)
            }
        var chosen: [EarChordQuality] = []
        for row in scored where chosen.count < 3 {
            if !chosen.contains(row.q) { chosen.append(row.q) }
        }
        if chosen.count < 3 {
            for q in wrongPool.shuffled(using: &rng) where chosen.count < 3 {
                if !chosen.contains(q) { chosen.append(q) }
            }
        }
        precondition(chosen.count == 3, "干扰项不足")
        let four = ([answer] + chosen).shuffled(using: &rng)
        let keys = ["A", "B", "C", "D"]
        let options = zip(keys, four).map { EarMcqOption(key: $0, label: $1.labelZh) }
        guard let correctKey = zip(keys, four).first(where: { $0.1 == answer })?.0 else {
            preconditionFailure("正确答案未落入四选项")
        }

        let root = pickRoot(from: p.roots, avoid: avoid, answer: answer, using: &rng)
        let id = "EA-P-\(UUID().uuidString.prefix(8))"
        let promptZh = "听音后判断和弦性质：\(root) ?"

        return EarBankItem(
            id: id,
            mode: "A",
            questionType: "single_chord_quality",
            promptZh: promptZh,
            options: options,
            correctOptionKey: correctKey,
            root: root,
            targetQuality: answer.targetQualityToken,
            hintZh: nil
        )
    }

    // MARK: 乐理干扰项

    private static func distractorScore(correct: EarChordQuality, wrong: EarChordQuality) -> Int {
        if correct == wrong { return -10_000 }
        var s = 0
        switch (correct, wrong) {
        case (.major, .minor), (.minor, .major):
            s += 100
        case (.major, .major7), (.major7, .major):
            s += 92
        case (.minor, .minor7), (.minor7, .minor):
            s += 92
        case (.dominant7, .major7), (.major7, .dominant7):
            s += 88
        case (.dominant7, .minor7), (.minor7, .dominant7):
            s += 86
        case (.dominant7, .major), (.major, .dominant7):
            s += 84
        case (.dominant7, .minor), (.minor, .dominant7):
            s += 82
        case (.major7, .minor7), (.minor7, .major7):
            s += 78
        default:
            break
        }
        return s
    }

    private static func pickRoot(
        from roots: [String],
        avoid: (root: String, quality: EarChordQuality)?,
        answer: EarChordQuality,
        using rng: inout some RandomNumberGenerator
    ) -> String {
        let pool = roots.shuffled(using: &rng)
        if let avoid {
            if let r = pool.first(where: { !($0 == avoid.root && answer == avoid.quality) }) {
                return r
            }
        }
        return roots.randomElement(using: &rng)!
    }
}
