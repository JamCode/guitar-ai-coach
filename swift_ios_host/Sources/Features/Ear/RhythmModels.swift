import Foundation

/// 节奏难度（映射到 AdaptiveEarDifficulty）
public enum RhythmDifficulty: String, Codable, Equatable {
    case beginner
    case intermediate
    case advanced
}

/// 4/4 拍一小节的节奏型，用 8 个八分位表示
public struct RhythmPattern: Codable, Equatable, Hashable {
    /// 8 个元素，每元素为 0（休止）或 1（击发）
    public let grid: [Int]

    /// Failable init: 仅当 grid 长度为 8 且每个元素为 0 或 1 时成功
    public init?(grid: [Int]) {
        guard grid.count == 8, grid.allSatisfy({ $0 == 0 || $0 == 1 }) else { return nil }
        self.grid = grid
    }

    /// 文字展示：每 2 个一组 → X / X· / ·X / .
    public var displayText: String {
        let groups = stride(from: 0, to: 8, by: 2).map { i -> String in
            let pair = (grid[i], grid[i+1])
            switch pair {
            case (1, 1): return "X"
            case (1, 0): return "X·"
            case (0, 1): return "·X"
            case (0, 0): return "."
            default: return "?"
            }
        }
        return groups.joined(separator: " ")
    }

    /// Bravura Text 字体下的标准音乐符号展示（SMuFL 标准）
    /// - 使用 U+E230 noteQuarterUp（四分音符）  U+E232 note8thUp（八分音符）
    /// - U+E0AA rest8th（八分休止）  U+E0A9 restQuarter（四分休止）
    public var musicNotationDisplay: String {
        let groups = stride(from: 0, to: 8, by: 2).map { i -> String in
            let pair = (grid[i], grid[i+1])
            switch pair {
            case (1, 1):
                // 四分音符
                return "\u{E230}"
            case (1, 0):
                // 八分 + 八分休止
                return "\u{E232}\u{2009}\u{E0AA}"
            case (0, 1):
                // 八分休止 + 八分
                return "\u{E0AA}\u{2009}\u{E232}"
            case (0, 0):
                // 四分休止
                return "\u{E0A9}"
            default:
                return "?"
            }
        }
        return groups.joined(separator: "\u{2009}\u{2009}") // thin spaces between beats
    }

    /// 播放用的击打序列（每个八分位是否发声）
    public var hits: [Bool] { grid.map { $0 == 1 } }
}
