import Foundation

// MARK: - 难度与预设（无题库，程序化出题）

/// 音程练耳难度：内部映射允许的半音集合与 MIDI 音域。
public enum IntervalEarDifficulty: String, Sendable, CaseIterable, Codable {
    case 初级
    case 中级
    case 高级
}

/// 三全音（6 半音）在中文 UI 上的规范写法。
public enum IntervalTritoneSpelling: Sendable {
    case aug4
    case dim5
}

/// 减轻「凭绝对音高猜题」：尽量让相邻题的低音 MIDI 相差至少 `minSemitoneDelta`。
public struct IntervalAntiAbsolutePitch: Sendable {
    public var previousLowerMidi: Int
    public var minSemitoneDelta: Int

    public init(previousLowerMidi: Int, minSemitoneDelta: Int) {
        self.previousLowerMidi = previousLowerMidi
        self.minSemitoneDelta = minSemitoneDelta
    }
}

/// 某难度对应的内部乐理参数（供调试与 UI 说明）。
public struct IntervalDifficultyPreset: Sendable {
    public var poolSemitones: [Int]
    public var lowerMidiMin: Int
    public var lowerMidiMax: Int
    public var upperMidiMax: Int
    public var tritoneSpelling: IntervalTritoneSpelling
}

public extension IntervalEarDifficulty {
    /// 各档设计意图（帮助文案）。
    static let helpText: [IntervalEarDifficulty: String] = [
        .初级: "协和与框架音程为主：纯一度/大二/大三/纯四/纯五/纯八；无小二与三全音；低音区较集中。",
        .中级: "加入小二及大小三、六、七度；仍不含三全音；音区略宽。",
        .高级: "含三全音在内的全部 0..12 半音简单音程；音区更宽。",
    ]
}

// MARK: - 音程种类与题目

public struct IntervalKind: Hashable, Sendable {
    public let semitones: Int
    public let nameZh: String

    /// 简单音程 0...12 的中文名（12 平均律）。
    public static func kind(semitones: Int, tritone: IntervalTritoneSpelling) -> IntervalKind {
        switch semitones {
        case 0: return .init(semitones: 0, nameZh: "纯一度")
        case 1: return .init(semitones: 1, nameZh: "小二度")
        case 2: return .init(semitones: 2, nameZh: "大二度")
        case 3: return .init(semitones: 3, nameZh: "小三度")
        case 4: return .init(semitones: 4, nameZh: "大三度")
        case 5: return .init(semitones: 5, nameZh: "纯四度")
        case 6:
            return tritone == .dim5
                ? .init(semitones: 6, nameZh: "减五度")
                : .init(semitones: 6, nameZh: "增四度")
        case 7: return .init(semitones: 7, nameZh: "纯五度")
        case 8: return .init(semitones: 8, nameZh: "小六度")
        case 9: return .init(semitones: 9, nameZh: "大六度")
        case 10: return .init(semitones: 10, nameZh: "小七度")
        case 11: return .init(semitones: 11, nameZh: "大七度")
        case 12: return .init(semitones: 12, nameZh: "纯八度")
        default:
            preconditionFailure("简单音程半音应在 0...12：\(semitones)")
        }
    }

    /// 兼容旧逻辑：1...12 半音，三全音按增四度展示。
    public static let trainingPool: [IntervalKind] = (1 ... 12).map { kind(semitones: $0, tritone: .aug4) }
}

public struct IntervalQuestion: Sendable {
    public let lowMidi: Int
    public let highMidi: Int
    public let answer: IntervalKind
    public let choices: [IntervalKind]
    public let difficulty: IntervalEarDifficulty
}

// MARK: - 出题

public enum IntervalQuestionGenerator {
    public static func preset(for difficulty: IntervalEarDifficulty) -> IntervalDifficultyPreset {
        switch difficulty {
        case .初级:
            return IntervalDifficultyPreset(
                poolSemitones: [0, 2, 4, 5, 7, 12],
                lowerMidiMin: 60,
                lowerMidiMax: 67,
                upperMidiMax: 79,
                tritoneSpelling: .aug4
            )
        case .中级:
            return IntervalDifficultyPreset(
                poolSemitones: [0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12],
                lowerMidiMin: 55,
                lowerMidiMax: 72,
                upperMidiMax: 84,
                tritoneSpelling: .aug4
            )
        case .高级:
            return IntervalDifficultyPreset(
                poolSemitones: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
                lowerMidiMin: 48,
                lowerMidiMax: 76,
                upperMidiMax: 96,
                tritoneSpelling: .aug4
            )
        }
    }

    /// 生成下一题：按乐理相关度选干扰项，再随机低音与选项顺序。
    public static func next(
        difficulty: IntervalEarDifficulty = .高级,
        antiAbsolutePitch: IntervalAntiAbsolutePitch? = nil,
        using rng: inout some RandomNumberGenerator
    ) -> IntervalQuestion {
        let p = preset(for: difficulty)
        let pool = Array(Set(p.poolSemitones)).sorted()
        precondition(pool.count >= 4, "内部预设池至少含 4 个半音")

        let correctSemitones = pool.randomElement(using: &rng)!
        let wrongPool = pool.filter { $0 != correctSemitones }
        let scored = wrongPool.map { (d: $0, s: distractorScore(correct: correctSemitones, candidate: $0)) }
            .sorted { lhs, rhs in
                if lhs.s != rhs.s { return lhs.s > rhs.s }
                return Bool.random(using: &rng)
            }

        var chosen: [Int] = []
        for row in scored where chosen.count < 3 {
            if !chosen.contains(row.d) { chosen.append(row.d) }
        }
        if chosen.count < 3 {
            for d in wrongPool.shuffled(using: &rng) where chosen.count < 3 {
                if !chosen.contains(d) { chosen.append(d) }
            }
        }
        precondition(chosen.count == 3)

        let wrongKinds = chosen.map { IntervalKind.kind(semitones: $0, tritone: p.tritoneSpelling) }
        let answerKind = IntervalKind.kind(semitones: correctSemitones, tritone: p.tritoneSpelling)
        let choices = ([answerKind] + wrongKinds).shuffled(using: &rng)

        let low = pickLowerMidi(
            semitones: correctSemitones,
            lowerMin: p.lowerMidiMin,
            lowerMax: p.lowerMidiMax,
            upperMax: p.upperMidiMax,
            anti: antiAbsolutePitch,
            using: &rng
        )

        return IntervalQuestion(
            lowMidi: low,
            highMidi: low + correctSemitones,
            answer: answerKind,
            choices: choices,
            difficulty: difficulty
        )
    }

    // MARK: 乐理干扰项打分（与 Web 版算法对齐）

    private static func distractorScore(correct: Int, candidate: Int) -> Int {
        chromaticBonus(correct, candidate)
            + inversionBonus(correct, candidate)
            + majorMinorNeighborBonus(correct, candidate)
            + perfectFourthFifthBonus(correct, candidate)
    }

    private static func chromaticBonus(_ a: Int, _ b: Int) -> Int {
        let u = abs(a - b)
        if u == 1 { return 100 }
        if u == 2 { return 78 }
        return 0
    }

    private static func inversionBonus(_ a: Int, _ b: Int) -> Int {
        if a <= 0 || a >= 12 || b <= 0 || b >= 12 { return 0 }
        return a + b == 12 ? 92 : 0
    }

    private static let majorMinorPairs: [(Int, Int)] = [(1, 2), (3, 4), (8, 9), (10, 11)]

    private static func majorMinorNeighborBonus(_ a: Int, _ b: Int) -> Int {
        for pair in majorMinorPairs where (a == pair.0 && b == pair.1) || (a == pair.1 && b == pair.0) {
            return 88
        }
        return 0
    }

    private static func perfectFourthFifthBonus(_ a: Int, _ b: Int) -> Int {
        let s: Set = [a, b]
        return s.contains(5) && s.contains(7) ? 72 : 0
    }

    private static func pickLowerMidi(
        semitones: Int,
        lowerMin: Int,
        lowerMax: Int,
        upperMax: Int,
        anti: IntervalAntiAbsolutePitch?,
        using rng: inout some RandomNumberGenerator
    ) -> Int {
        let hi = min(lowerMax, upperMax - semitones)
        precondition(hi >= lowerMin, "音域与半音跨度不兼容")

        let span = hi - lowerMin + 1
        let maxTry = anti == nil ? 1 : 48
        for _ in 0 ..< maxTry {
            let k = Int.random(in: 0 ..< span, using: &rng)
            let m = lowerMin + k
            if let anti {
                if abs(m - anti.previousLowerMidi) >= anti.minSemitoneDelta { return m }
            } else {
                return m
            }
        }
        let k = Int.random(in: 0 ..< span, using: &rng)
        return lowerMin + k
    }
}
