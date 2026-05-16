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

    /// 揭示答案后展示的一行乐理说明（与 `nameZh` 一一对应）。
    public var teachZh: String {
        switch semitones {
        case 0:
            return "同音或八度内重复，两音高一致，音程为 0 个半音。"
        case 1:
            return "比低音只高 1 个半音，极窄的半音关系，不协和、张力强，常有「往上解决」的听感。"
        case 2:
            return "含 2 个半音（1 个全音），大调音阶中相邻度名的典型间距，略带展开感。"
        case 3:
            return "3 个半音，小调、布鲁斯里常见的三度色彩，比大三度更柔和、略暗。"
        case 4:
            return "4 个半音，大三和弦的骨架，明亮、稳定，是流行与进行里的常用和声感。"
        case 5:
            return "5 个半音（2 个全音 + 1 个半音），属完全协和，音响开阔、坚实，和纯五度、纯八度同属一类自然框架。"
        case 6:
            if nameZh == "减五度" {
                return "6 个半音（同「三全音」），不协和、紧张，常在属七等和弦里以「减五度」对低音呈现。"
            }
            return "6 个半音，又称三全音；极不稳定，色彩尖锐，在古典中常需「解决」到更协和的音程。"
        case 7:
            return "7 个半音，属—主、下属—主进行的重要支柱，与纯四度互为转位，和声上非常顺耳。"
        case 8:
            return "8 个半音，小调色彩偏柔、略暗，与大六度成对，常见于抒情与慢歌和声。"
        case 9:
            return "9 个半音，大调中明亮、宽的感觉，大六和弦顶音到根音的跨度就常是这类听感。"
        case 10:
            return "10 个半音，属七、小七等和弦里常见，略带忧郁或「悬而未决」的七度音色彩。"
        case 11:
            return "11 个半音，大七和弦顶音与根音的跨度，比小七更「亮」、更倾向主音的引力。"
        case 12:
            return "高一个完整八度，与低音为同名音高、频率比约 2:1，最融合、最稳定的「同音高」感。"
        default:
            return ""
        }
    }
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

// MARK: - 揭示后：本题连续半音音区（至少一个八度）

/// 生成「本题两音」附近的连续半音 MIDI 列表，用于揭示后可点试听。
public enum IntervalChromaticStrip {
    /// 升序连续半音；跨度至少 **12 半音**（含一个完整八度），且必含 `lowMidi` 与 `highMidi`。
    public static func midisCoveringOctaveIncluding(lowMidi: Int, highMidi: Int) -> [Int] {
        let lo = min(lowMidi, highMidi)
        let hi = max(lowMidi, highMidi)
        var start = lo
        var end = hi
        if end - start < 12 {
            let deficit = 12 - (end - start)
            start -= deficit / 2
            end += deficit - deficit / 2
        }
        if start < 0 {
            end += -start
            start = 0
        }
        if end > 127 {
            start -= end - 127
            end = 127
        }
        start = max(0, min(start, lo))
        end = min(127, max(end, hi))
        while end - start < 12, end < 127 {
            end += 1
        }
        while end - start < 12, start > 0 {
            start -= 1
        }
        return Array(start ... end)
    }
}
