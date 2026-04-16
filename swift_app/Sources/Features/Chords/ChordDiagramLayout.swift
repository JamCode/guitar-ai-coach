import Foundation

/// 六线指法图布局：根据6→1 弦的品格数组计算是否画琴枕、可见品格区间等。
enum ChordDiagramLayout {
    struct Config: Equatable {
        /// 是否绘制琴枕（开放弦 / 低把位常见型）。
        let showsNut: Bool
        /// 非琴枕视图时左侧标注的第一品绝对品格。
        let positionLabel: Int?
        let startFret: Int
        let endFret: Int
    }

    static func normalizedFrets(_ frets: [Int]) -> [Int] {
        var f = Array(frets.prefix(6))
        if f.count < 6 {
            f.append(contentsOf: Array(repeating: -1, count: 6 - f.count))
        }
        return f
    }

    static func config(for frets: [Int]) -> Config {
        let f = normalizedFrets(frets)
        let positives = f.filter { $0 > 0 }
        let minP = positives.min() ?? 1
        let maxP = positives.max() ?? minP
        let showsNut = minP <= 1 || f.contains(0)
        let startFret: Int
        let endFret: Int
        if showsNut {
            startFret = 1
            endFret = max(maxP, 4)
        } else {
            startFret = minP
            endFret = max(maxP, minP + 3)
        }
        let positionLabel: Int? = showsNut ? nil : startFret
        return Config(showsNut: showsNut, positionLabel: positionLabel, startFret: startFret, endFret: endFret)
    }
}
