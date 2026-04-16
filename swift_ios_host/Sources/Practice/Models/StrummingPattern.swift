import Foundation

// Keep aligned with Flutter `strumming_pattern.dart`.

enum StrumCellKind: String, Codable, Hashable {
    case down
    case up
    case rest
}

struct StrummingPattern: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let tip: String
    /// 长度 8：`[1, &, 2, &, 3, &, 4, &]`。
    let cells: [StrumCellKind]
}

let kStrummingPatterns: [StrummingPattern] = [
    StrummingPattern(
        id: "all-down-eighths",
        name: "八分全下",
        subtitle: "入门 · 稳拍",
        tip: "每一拍均匀下扫，先求稳再求力度变化。",
        cells: Array(repeating: .down, count: 8)
    ),
    StrummingPattern(
        id: "all-up-eighths",
        name: "八分全上",
        subtitle: "上扫均匀",
        tip: "全部用上扫练手腕回程，音量通常比下扫轻，注意与弦接触角度。",
        cells: Array(repeating: .up, count: 8)
    ),
    StrummingPattern(
        id: "alternate-eighths",
        name: "八分交替",
        subtitle: "上下均匀",
        tip: "下上交替，注意小臂摆动幅度一致。",
        cells: [.down, .up, .down, .up, .down, .up, .down, .up]
    ),
    StrummingPattern(
        id: "folk-dduudu",
        name: "民谣常用",
        subtitle: "下下上 上下上",
        tip: "经典型：前两拍「下下」，后两拍「上上下上」的变体，先慢速跟拍。",
        cells: [.down, .down, .up, .up, .down, .up, .rest, .rest]
    ),
    StrummingPattern(
        id: "chunk-double",
        name: "双 Chunk",
        subtitle: "下下上 下下上",
        tip: "两拍一组「下下上」连做两次，流行歌常用，注意第二组不要抢拍。",
        cells: [.down, .down, .up, .up, .down, .down, .up, .up]
    ),
    StrummingPattern(
        id: "driving-triplets-feel",
        name: "行进感",
        subtitle: "三下接一上",
        tip: "连续三个下扫后接一个上扫，有推进感；先慢速再加速。",
        cells: [.down, .down, .down, .up, .down, .down, .down, .up]
    ),
    StrummingPattern(
        id: "quarter-downs",
        name: "每拍一下",
        subtitle: "四分音符 · 稳",
        tip: "只在正拍下扫，& 位置休息，适合慢歌或强调重音。",
        cells: [.down, .rest, .down, .rest, .down, .rest, .down, .rest]
    ),
    StrummingPattern(
        id: "half-note-downs",
        name: "两拍一下",
        subtitle: "二分音符 · 慢曲",
        tip: "只在第 1、3 拍正点下扫，其余空拍，适合很慢的抒情或数拍。",
        cells: [.down, .rest, .rest, .rest, .down, .rest, .rest, .rest]
    ),
    StrummingPattern(
        id: "offbeat-downs",
        name: "反拍八分",
        subtitle: "弱拍下扫",
        tip: "正拍不扫、弱拍扫，先小声找「反拍」位置，再加重。",
        cells: [.rest, .down, .rest, .down, .rest, .down, .rest, .down]
    ),
    StrummingPattern(
        id: "ska-ups",
        name: "Ska 上扫",
        subtitle: "弱拍上扫",
        tip: "正拍休止、弱拍上扫，手腕略抬高；可与反拍下扫对照练。",
        cells: [.rest, .up, .rest, .up, .rest, .up, .rest, .up]
    ),
    StrummingPattern(
        id: "reggae-backbeat",
        name: "雷鬼反拍",
        subtitle: "2、4 拍",
        tip: "只在第 2、4 拍正点下扫，其余不扫，适合雷鬼/慢摇滚律动。",
        cells: [.rest, .rest, .down, .rest, .rest, .rest, .down, .rest]
    ),
    StrummingPattern(
        id: "percussive-du-gap",
        name: "下切上",
        subtitle: "带空隙",
        tip: "下—空—上循环，空拍可做护弦或制音，偏节奏吉他。",
        cells: [.down, .rest, .up, .rest, .down, .rest, .up, .rest]
    ),
    StrummingPattern(
        id: "shuffle-eighths",
        name: "Shuffle 感",
        subtitle: "长短短",
        tip: "近似三连音长短短：长音用下扫，短音用上扫，慢速对齐摇摆感。",
        cells: [.down, .up, .rest, .down, .up, .rest, .down, .up]
    ),
]

func strummingPatternNameForId(_ id: String?) -> String? {
    guard let id, !id.isEmpty else { return nil }
    return kStrummingPatterns.first(where: { $0.id == id })?.name
}

