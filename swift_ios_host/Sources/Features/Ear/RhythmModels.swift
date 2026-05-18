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

    /// 简谱风格展示：每 2 个一组
    ///  X = 四分音符（一拍）   X̲ = 八分音符   0 = 四分休止   0̲ = 八分休止
    public var displayText: String {
        let underline = "\u{0332}"  // 组合下划线，如 X̲
        let groups = stride(from: 0, to: 8, by: 2).map { i -> String in
            let pair = (grid[i], grid[i+1])
            switch pair {
            case (1, 1): return "X"
            case (1, 0): return "X" + underline
            case (0, 1): return "0" + underline + "X" + underline
            case (0, 0): return "0"
            default: return "?"
            }
        }
        return groups.joined(separator: " ")
    }

    /// 播放用的击打序列（每个八分位是否发声）
    public var hits: [Bool] { grid.map { $0 == 1 } }
}
