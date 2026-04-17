import Foundation

// MARK: - 难度与说明（程序化出题，无固定题库；对齐音程 / 和弦听辨模块风格）

/// 吉他「爬格子」指型序列的出题难度：控制把位范围、是否含下行指序等。
public enum SpiderCrawlDifficulty: String, Sendable, CaseIterable, Codable {
    case 初级
    case 中级
    case 高级
}

public extension SpiderCrawlDifficulty {
    static let helpText: [SpiderCrawlDifficulty: String] = [
        .初级: "经典上行：从六弦到一弦，每弦依次按连续四品；把位较低，仅问「下一格」落点。",
        .中级: "仍以上行为主，把位范围更宽；干扰项更贴近常见错按。",
        .高级: "随机混合上行 / 下行指序（每弦四品倒序），考查换弦与换把位后的下一落点。",
    ]
}

// MARK: - 指板落点

/// 单音落点：`stringIndexFromBass` 0 表示六弦（最粗），5 表示一弦（最细），与 `FretboardMath.openMidiStrings` 下标一致。
public struct SpiderCell: Hashable, Sendable, Codable {
    public var stringIndexFromBass: Int
    public var fret: Int

    public init(stringIndexFromBass: Int, fret: Int) {
        self.stringIndexFromBass = stringIndexFromBass
        self.fret = fret
    }

    /// 中文展示，如「五弦 7品」。
    public var zhLabel: String {
        precondition((0 ... 5).contains(stringIndexFromBass), "弦索引应在 0...5")
        let s = SpiderCrawlQuestionGenerator.chineseStringNames[stringIndexFromBass]
        return "\(s) \(fret)品"
    }
}

// MARK: - 指序模式

/// 单轮「四指一格」在六根弦上的遍历方式。
public enum SpiderCrawlPattern: String, Sendable, Hashable, Codable, CaseIterable {
    /// 每弦从低到高品：\(b, b+1, b+2, b+3\)，弦序六弦→一弦；每轮结束后把位整体上移一品。
    case ascendingPerString
    /// 每弦从高到低品：\(b+3, b+2, b+1, b\)，弦序六弦→一弦；每轮结束后把位整体上移一品。
    case descendingPerString

    public var titleZh: String {
        switch self {
        case .ascendingPerString: return "上行（每弦低→高品）"
        case .descendingPerString: return "下行（每弦高→低品）"
        }
    }
}

// MARK: - 题目

public struct SpiderCrawlQuestion: Sendable {
    public let difficulty: SpiderCrawlDifficulty
    public let pattern: SpiderCrawlPattern
    public let previousCell: SpiderCell
    public let answer: SpiderCell
    /// 四选一，含且仅含一个与 `answer` 相等的元素。
    public let choices: [SpiderCell]
    public let promptZh: String
}

// MARK: - 出题

public enum SpiderCrawlQuestionGenerator {
    /// 与 `FretboardMath` 一致：0 = 六弦（low E）。
    static let chineseStringNames = ["六弦", "五弦", "四弦", "三弦", "二弦", "一弦"]

    public struct SessionPreset: Sendable {
        public var minBlockStartFret: Int
        public var maxBlockStartFret: Int
        public var maxFret: Int
        public var allowedPatterns: [SpiderCrawlPattern]
    }

    public static func preset(for difficulty: SpiderCrawlDifficulty) -> SessionPreset {
        switch difficulty {
        case .初级:
            return SessionPreset(minBlockStartFret: 1, maxBlockStartFret: 5, maxFret: 12, allowedPatterns: [.ascendingPerString])
        case .中级:
            return SessionPreset(minBlockStartFret: 1, maxBlockStartFret: 8, maxFret: 12, allowedPatterns: [.ascendingPerString])
        case .高级:
            return SessionPreset(minBlockStartFret: 1, maxBlockStartFret: 8, maxFret: 12, allowedPatterns: SpiderCrawlPattern.allCases)
        }
    }

    /// 组卷：每题独立随机；尽量避免与上一题完全相同的「模式 + 前一格 + 答案格」。
    public static func buildSession(
        count: Int,
        difficulty: SpiderCrawlDifficulty,
        using rng: inout some RandomNumberGenerator
    ) -> [SpiderCrawlQuestion] {
        let n = max(1, count)
        var out: [SpiderCrawlQuestion] = []
        out.reserveCapacity(n)
        var last: (SpiderCrawlPattern, SpiderCell, SpiderCell)?
        for _ in 0 ..< n {
            let q = next(difficulty: difficulty, avoid: last, using: &rng)
            last = (q.pattern, q.previousCell, q.answer)
            out.append(q)
        }
        return out
    }

    public static func next(
        difficulty: SpiderCrawlDifficulty = .初级,
        avoid: (pattern: SpiderCrawlPattern, previous: SpiderCell, answer: SpiderCell)? = nil,
        using rng: inout some RandomNumberGenerator
    ) -> SpiderCrawlQuestion {
        let p = preset(for: difficulty)
        let pattern = p.allowedPatterns.randomElement(using: &rng)!
        let rounds = 6
        let maxTry = 96
        for _ in 0 ..< maxTry {
            let blockStart = Int.random(in: p.minBlockStartFret ... p.maxBlockStartFret, using: &rng)
            let path = makePath(pattern: pattern, blockStart: blockStart, rounds: rounds, maxFret: p.maxFret)
            guard path.count >= 2 else { continue }
            let idx = Int.random(in: 1 ..< path.count, using: &rng)
            let prev = path[idx - 1]
            let ans = path[idx]
            if let avoid, avoid.pattern == pattern, avoid.previous == prev, avoid.answer == ans { continue }
            let wrongPool = candidateDistractors(answer: ans, previous: prev, maxFret: p.maxFret)
            let scored = wrongPool.map { (c: $0, s: distractorScore(answer: ans, candidate: $0)) }
                .sorted { lhs, rhs in
                    if lhs.s != rhs.s { return lhs.s > rhs.s }
                    return Bool.random(using: &rng)
                }
            var chosen: [SpiderCell] = []
            for row in scored where chosen.count < 3 {
                if !chosen.contains(row.c) { chosen.append(row.c) }
            }
            if chosen.count < 3 {
                for c in wrongPool.shuffled(using: &rng) where chosen.count < 3 {
                    if !chosen.contains(c) { chosen.append(c) }
                }
            }
            if chosen.count < 3 { continue }
            let choices = ([ans] + chosen).shuffled(using: &rng)
            let promptZh = prompt(pattern: pattern, previous: prev)
            return SpiderCrawlQuestion(
                difficulty: difficulty,
                pattern: pattern,
                previousCell: prev,
                answer: ans,
                choices: choices,
                promptZh: promptZh
            )
        }
        preconditionFailure("爬格子题目生成失败：请放宽 avoid 条件或扩大把位预设")
    }

    // MARK: 路径

    /// 生成「爬格子」离散落点序列（含换把）：每完成六根弦的一轮四指，把位起点 +1。
    public static func makePath(
        pattern: SpiderCrawlPattern,
        blockStart: Int,
        rounds: Int,
        maxFret: Int
    ) -> [SpiderCell] {
        precondition(rounds >= 1)
        var out: [SpiderCell] = []
        out.reserveCapacity(rounds * 6 * 4)
        var b = blockStart
        for _ in 0 ..< rounds {
            switch pattern {
            case .ascendingPerString:
                for s in 0 ..< 6 {
                    for k in 0 ..< 4 {
                        let f = b + k
                        guard f <= maxFret else { return out }
                        out.append(SpiderCell(stringIndexFromBass: s, fret: f))
                    }
                }
            case .descendingPerString:
                for s in 0 ..< 6 {
                    for k in stride(from: 3, through: 0, by: -1) {
                        let f = b + k
                        guard f <= maxFret else { return out }
                        out.append(SpiderCell(stringIndexFromBass: s, fret: f))
                    }
                }
            }
            b += 1
        }
        return out
    }

    // MARK: 文案

    private static func prompt(pattern: SpiderCrawlPattern, previous: SpiderCell) -> String {
        "爬格子（\(pattern.titleZh)）：刚弹到 \(previous.zhLabel)，下一音应在？"
    }

    // MARK: 干扰项

    private static func candidateDistractors(answer: SpiderCell, previous: SpiderCell, maxFret: Int) -> [SpiderCell] {
        var pool: Set<SpiderCell> = []
        let s = answer.stringIndexFromBass
        let f = answer.fret
        func insert(_ c: SpiderCell) {
            if c != answer, c.fret >= 1, c.fret <= maxFret, (0 ... 5).contains(c.stringIndexFromBass) {
                pool.insert(c)
            }
        }
        insert(previous)
        insert(SpiderCell(stringIndexFromBass: s, fret: f - 1))
        insert(SpiderCell(stringIndexFromBass: s, fret: f + 1))
        insert(SpiderCell(stringIndexFromBass: s, fret: f - 2))
        insert(SpiderCell(stringIndexFromBass: s, fret: f + 2))
        insert(SpiderCell(stringIndexFromBass: max(0, s - 1), fret: f))
        insert(SpiderCell(stringIndexFromBass: min(5, s + 1), fret: f))
        insert(SpiderCell(stringIndexFromBass: max(0, s - 1), fret: f - 1))
        insert(SpiderCell(stringIndexFromBass: min(5, s + 1), fret: f + 1))
        insert(SpiderCell(stringIndexFromBass: s, fret: max(1, f - 3)))
        insert(SpiderCell(stringIndexFromBass: s, fret: min(maxFret, f + 3)))
        return Array(pool)
    }

    private static func distractorScore(answer: SpiderCell, candidate: SpiderCell) -> Int {
        if candidate == answer { return -10_000 }
        var score = 0
        let ds = abs(candidate.stringIndexFromBass - answer.stringIndexFromBass)
        let df = abs(candidate.fret - answer.fret)
        if ds == 0, df == 1 { score += 100 }
        if ds == 1, df == 0 { score += 96 }
        if ds == 1, df == 1 { score += 92 }
        if ds == 0, df == 2 { score += 86 }
        if ds == 2, df == 0 { score += 78 }
        if ds == 0, df == 3 { score += 72 }
        if df == 0, ds >= 1 { score += 60 }
        return score
    }
}
