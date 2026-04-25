import Foundation

// MARK: - 功能和声（练耳和弦进行生成）

/// 大调内简化功能分类，用于转移加权（非完整斯波索宾体系）。
public enum EarHarmonicFunction: String, Sendable {
    case tonic
    case predominant
    case dominant
}

/// 调试：打印「候选 → 分数 → 选中」；默认关闭。
public enum EarProgressionGenerationDebug: Sendable {
    case off
    /// 将人类可读行写入（单测可接 `lines.append`）。
    case linesOnly((String) -> Void)
}

public enum EarProgressionHarmonyEngine {
    /// 生成时可切换；`makeQuestion` 会读取。
    public static var debugMode: EarProgressionGenerationDebug = .off

    // MARK: - 功能分类

    public static func function(ofRoman roman: String) -> EarHarmonicFunction {
        let r = roman.trimmingCharacters(in: .whitespacesAndNewlines)
        if isDominantFamily(r) { return .dominant }
        if isPredominantFamily(r) { return .predominant }
        return .tonic
    }

    private static func isDominantFamily(_ r: String) -> Bool {
        let u = r
        if u.hasPrefix("(V/") { return true }
        if u == "V" || u == "V7" { return true }
        return false
    }

    private static func isPredominantFamily(_ r: String) -> Bool {
        let u = r
        if u == "IV" || u == "ii" || u == "ii7" { return true }
        if u == "vi" || u == "vi7" { return true }
        if u == "iv" || u == "bVI" || u == "bIII" { return true }
        return false
    }

    /// 是否为「色彩/离调」和弦（高级限量使用）。
    public static func isColorChord(_ r: String) -> Bool {
        let u = r.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.hasPrefix("(V/") { return true }
        if u == "bVI" || u == "bIII" || u == "iv" { return true }
        return false
    }

    // MARK: - 候选池（按难度）

    private static func candidatePool(
        difficulty: EarProgressionMcqDifficulty,
        index: Int,
        length: Int,
        colorBudgetRemaining: Int
    ) -> [String] {
        let core = ["I", "ii", "IV", "V", "vi"]
        let tertiary = ["iii"]
        switch difficulty {
        case .初级:
            var p = core
            if index > 0 { p += tertiary }
            return p
        case .中级:
            return core + tertiary + ["V7", "ii7", "vi7"]
        case .高级:
            var p = core + tertiary + ["V7", "ii7", "vi7"]
            if colorBudgetRemaining > 0 {
                p += ["(V/ii)", "(V/vi)", "bVI", "bIII", "iv"]
            }
            return p
        }
    }

    // MARK: - 转移与句尾评分

    private static func flowBonus(from prev: String, to cand: String, difficulty: EarProgressionMcqDifficulty) -> Double {
        let pf = function(ofRoman: prev)
        let cf = function(ofRoman: cand)
        var s = 0.0
        switch (pf, cf) {
        case (.tonic, .predominant): s += 28
        case (.tonic, .dominant): s += 12
        case (.tonic, .tonic):
            if prev == "I" && (cand == "vi" || cand == "iii") { s += 22 }
            else if cand == "I" { s += 6 }
            else { s += 4 }
        case (.predominant, .dominant): s += 38
        case (.predominant, .predominant):
            if (prev == "IV" || prev == "ii" || prev == "ii7") && (cand == "ii" || cand == "ii7") { s += 8 }
            else { s += 5 }
        case (.predominant, .tonic):
            if cand == "I" { s += 18 }
            else { s += 6 }
        case (.dominant, .tonic): s += 55
        case (.dominant, .predominant):
            if cand == "ii" || cand == "ii7" { s += 10 }
            else { s += 3 }
        case (.dominant, .dominant): s -= 25
        }
        if difficulty == .初级 {
            if prev == "iii" || cand == "iii" { s -= 12 }
        }
        return s
    }

    private static func resolutionBonus(prev: String, cand: String) -> Double {
        let p = prev.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = cand.trimmingCharacters(in: .whitespacesAndNewlines)
        switch p {
        case "(V/ii)":
            return c == "ii" || c == "ii7" ? 72 : -40
        case "(V/vi)":
            return c == "vi" || c == "vi7" ? 72 : -40
        case "bVI":
            return (c == "V" || c == "V7" || c == "I") ? 38 : -15
        case "bIII":
            return (c == "ii" || c == "ii7" || c == "I" || c == "IV") ? 34 : -18
        case "iv":
            return (c == "V" || c == "V7") ? 48 : -10
        case "V7", "V":
            if c == "I" { return 40 }
            if c == "vi" || c == "vi7" { return 28 }
            return c == "IV" ? 12 : 0
        default:
            return 0
        }
    }

    private static func positionBonus(
        cand: String,
        index: Int,
        length: Int,
        difficulty: EarProgressionMcqDifficulty
    ) -> Double {
        var s = 0.0
        let last = length - 1
        let pen = length - 2
        if index == 0 {
            if cand == "I" { s += 35 }
            if cand == "vi" { s += 22 }
            if cand == "IV" { s += 8 }
        }
        if index == last {
            if cand == "I" { s += 120 }
            if cand == "vi" || cand == "vi7" { s += 28 }
            if cand == "IV" { s += 18 }
            if cand != "I", cand != "vi", cand != "vi7", cand != "IV" { s -= 55 }
        }
        if index == pen {
            if cand == "V" || cand == "V7" { s += 55 }
            if cand.hasPrefix("(V/") { s += difficulty == .高级 ? 28 : -80 }
            if cand == "IV" || cand == "ii" || cand == "ii7" { s += 12 }
        }
        if index > 0, index < last {
            if cand == "I" { s -= 8 }
        }
        return s
    }

    private static func rarityAndColorPenalty(
        cand: String,
        difficulty: EarProgressionMcqDifficulty,
        colorAlreadyUsed: Bool
    ) -> Double {
        var s = 0.0
        if cand == "iii" { s -= 18 }
        if difficulty == .中级, isColorChord(cand) { s -= 200 }
        if difficulty == .初级 {
            if cand.contains("7") || cand.hasPrefix("(V/") || cand == "bVI" || cand == "bIII" || cand == "iv" {
                s -= 200
            }
        }
        if isColorChord(cand), colorAlreadyUsed { s -= 200 }
        return s
    }

    private static func consecutiveColorPenalty(prev: String, cand: String) -> Double {
        if isColorChord(prev), isColorChord(cand) { return -90 }
        return 0
    }

    // MARK: - 加权选取

    private static func weightedPick(
        scores: [Double],
        using rng: inout some RandomNumberGenerator
    ) -> Int {
        let shifted = scores.map { max(0.05, $0 + 50) }
        let total = shifted.reduce(0, +)
        var r = Double.random(in: 0 ..< total, using: &rng)
        for (i, w) in shifted.enumerated() {
            r -= w
            if r <= 0 { return i }
        }
        return scores.count - 1
    }

    private static func logLine(_ msg: String) {
        switch debugMode {
        case .off:
            break
        case let .linesOnly(sink):
            sink(msg)
        }
    }

    /// 生成一条 `-` 分隔的罗马数字进行（大调、固定符号集）。
    public static func generateProgressionRoman(
        difficulty: EarProgressionMcqDifficulty,
        length: Int,
        using rng: inout some RandomNumberGenerator
    ) -> String {
        precondition(length >= 3 && length <= 8)
        for attempt in 0 ..< 96 {
            var seq: [String] = []
            var colorUsed = false
            var colorBudget = (difficulty == .高级) ? 1 : 0
            var dbg: [String] = []
            for i in 0 ..< length {
                let colorRemaining = colorBudget > 0 ? 1 : 0
                var pool = candidatePool(
                    difficulty: difficulty,
                    index: i,
                    length: length,
                    colorBudgetRemaining: colorRemaining
                )
                pool = Array(Set(pool)).sorted { a, b in
                    if function(ofRoman: a) != function(ofRoman: b) {
                        return function(ofRoman: a).rawValue < function(ofRoman: b).rawValue
                    }
                    return a < b
                }
                let prev = seq.last
                var scores: [Double] = []
                for cand in pool {
                    var sc = 0.0
                    sc += Double.random(in: 0 ..< 4, using: &rng)
                    if let p = prev {
                        sc += flowBonus(from: p, to: cand, difficulty: difficulty)
                        sc += resolutionBonus(prev: p, cand: cand)
                        sc += consecutiveColorPenalty(prev: p, cand: cand)
                    }
                    sc += positionBonus(cand: cand, index: i, length: length, difficulty: difficulty)
                    sc += rarityAndColorPenalty(
                        cand: cand,
                        difficulty: difficulty,
                        colorAlreadyUsed: colorUsed && isColorChord(cand)
                    )
                    if isColorChord(cand), colorBudget > 0, !colorUsed {
                        sc += 8
                    }
                    if difficulty != .初级, (cand == "ii7" || cand == "vi7"), prev == nil || prev == "I" || prev == "vi" {
                        sc += 6
                    }
                    scores.append(sc)
                }
                let pickIdx = weightedPick(scores: scores, using: &rng)
                let chosen = pool[pickIdx]
                if isColorChord(chosen) {
                    colorUsed = true
                    colorBudget = 0
                }
                if case .linesOnly = debugMode {
                    let prevStr = prev ?? "—"
                    let detail = zip(pool, scores)
                        .map { c, v in String(format: "%@=%.1f", c, v) }
                        .joined(separator: ", ")
                    let win = String(format: "%.1f", scores[pickIdx])
                    dbg.append(
                        "[\(i)] prev=\(prevStr) picked=\(chosen) score=\(win) | \(detail)"
                    )
                }
                seq.append(chosen)
            }
            let line = seq.joined(separator: "-")
            if case .linesOnly = debugMode {
                dbg.forEach { logLine($0) }
                logLine("→ line: \(line) (attempt \(attempt + 1))")
            }
            if EarProgressionPlayback.isProgressionPlayable(musicKey: "C", progressionRoman: line) {
                return line
            }
        }
        let fallback = length <= 4 ? "I-IV-V-I" : "I-vi-IV-V-I"
        logLine("→ fallback: \(fallback)")
        return fallback
    }
}
