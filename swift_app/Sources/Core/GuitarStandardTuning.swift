import Foundation

/// 标准调弦（6 弦 E2–E4）下，和弦速查等「6→1 弦」品格数组与 MIDI 的对应关系。
///
/// `frets` 顺序与 `ChordChartEntry.frets` 一致：下标 0 为 6 弦（最粗），5 为 1 弦（最细）。
/// `-1` 表示该弦不发声（闷音/不按），跳过。
public enum GuitarStandardTuning {
    /// 空弦 MIDI：6→1 弦 E A D G B E。
    public static let openStringMidis: [Int] = [40, 45, 50, 55, 59, 64]

    /// 从 6→1 品格数组得到发声弦的 MIDI 列表（自低音弦向高音弦，去重保序）。
    public static func midisFromChordFretsSixToOne(_ frets: [Int]) -> [Int] {
        guard frets.count == 6 else { return [] }
        var seen = Set<Int>()
        var ordered: [Int] = []
        for i in 0..<6 {
            let f = frets[i]
            if f < 0 { continue }
            let midi = openStringMidis[i] + f
            if midi < 0 || midi > 127 { continue }
            if seen.insert(midi).inserted {
                ordered.append(midi)
            }
        }
        return ordered
    }
}
