import Foundation

// Keep aligned with Flutter `strumming_pattern.dart`.

enum StrumCellKind: String, Codable, Hashable {
    case down
    case up
    case rest
    case mute
}

enum StrumActionKind: String, Codable, Hashable {
    case down
    case up
    case rest
    case mute
}

struct StrumActionEvent: Codable, Equatable, Hashable {
    /// 最小单位：八分音符（1=半拍，2=一拍）
    let kind: StrumActionKind
    let units: Int
}

enum StrummingDifficulty: String, Codable, CaseIterable, Hashable {
    case 初级
    case 中级
    case 高级
}

enum StrummingSubdivision: String, Codable, Hashable {
    case quarter
    case eighth

    var labelZh: String {
        switch self {
        case .quarter: "四分音符"
        case .eighth: "八分音符"
        }
    }
}

struct StrummingPattern: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let tip: String
    let difficulty: StrummingDifficulty
    let timeSignature: String
    let subdivision: StrummingSubdivision
    let recommendedBPM: Int?
    /// 事件流（canonical）：按八分单位定义动作与时值，4/4 每小节应合计 8 单位。
    let events: [StrumActionEvent]
    /// 长度 8：`[1, &, 2, &, 3, &, 4, &]`。
    let cells: [StrumCellKind]
    /// 与 `cells` 对齐的逐格步骤，供 UI 按 step 高亮。
    let patternSteps: [StrumCellKind]
}

func expandStrumEventsToCells(_ events: [StrumActionEvent], totalUnits: Int = 8) -> [StrumCellKind] {
    var cells: [StrumCellKind] = []
    for event in events {
        guard event.units > 0 else { continue }
        let base: StrumCellKind = switch event.kind {
        case .down: .down
        case .up: .up
        case .rest: .rest
        case .mute: .mute
        }
        // 首个单位显示动作，后续单位用休止占位（表示时值延续）。
        cells.append(base)
        if event.units > 1 {
            cells.append(contentsOf: Array(repeating: .rest, count: event.units - 1))
        }
    }
    if cells.count < totalUnits {
        cells.append(contentsOf: Array(repeating: .rest, count: totalUnits - cells.count))
    }
    return Array(cells.prefix(totalUnits))
}

private func makePattern(
    id: String,
    name: String,
    subtitle: String,
    tip: String,
    difficulty: StrummingDifficulty,
    events: [StrumActionEvent]
) -> StrummingPattern {
    let total = events.reduce(0) { $0 + $1.units }
    precondition(total == 8, "4/4 + eighth unit requires 8 units: \(id)")
    return StrummingPattern(
        id: id,
        name: name,
        subtitle: subtitle,
        tip: tip,
        difficulty: difficulty,
        timeSignature: "4/4",
        subdivision: .eighth,
        recommendedBPM: nil,
        events: events,
        cells: expandStrumEventsToCells(events, totalUnits: 8),
        patternSteps: expandStrumEventsToCells(events, totalUnits: 8)
    )
}

private func e(_ kind: StrumActionKind, _ units: Int) -> StrumActionEvent {
    StrumActionEvent(kind: kind, units: units)
}

private let beginnerPatterns: [StrummingPattern] = [
    makePattern(
        id: "all-down-eighths",
        name: "八分全下",
        subtitle: "入门 · 稳拍",
        tip: "每一拍均匀下扫，先求稳再求力度变化。",
        difficulty: .初级,
        events: Array(repeating: e(.down, 1), count: 8)
    ),
    makePattern(
        id: "all-up-eighths",
        name: "八分全上",
        subtitle: "上扫均匀",
        tip: "全部用上扫练手腕回程，音量通常比下扫轻，注意与弦接触角度。",
        difficulty: .初级,
        events: Array(repeating: e(.up, 1), count: 8)
    ),
    makePattern(
        id: "alternate-eighths",
        name: "八分交替",
        subtitle: "上下均匀",
        tip: "下上交替，注意小臂摆动幅度一致。",
        difficulty: .初级,
        events: [e(.down, 1), e(.up, 1), e(.down, 1), e(.up, 1), e(.down, 1), e(.up, 1), e(.down, 1), e(.up, 1)]
    ),
    makePattern(
        id: "quarter-downs",
        name: "每拍一下",
        subtitle: "四分音符 · 稳",
        tip: "只在正拍下扫，& 位置休息，适合慢歌或强调重音。",
        difficulty: .初级,
        events: [e(.down, 2), e(.down, 2), e(.down, 2), e(.down, 2)]
    ),
    makePattern(
        id: "half-note-downs",
        name: "两拍一下",
        subtitle: "二分音符 · 慢曲",
        tip: "只在第 1、3 拍正点下扫，其余空拍，适合很慢的抒情或数拍。",
        difficulty: .初级,
        events: [e(.down, 2), e(.rest, 2), e(.down, 2), e(.rest, 2)]
    ),
]

private let intermediatePatterns: [StrummingPattern] = [
    makePattern(
        id: "folk-dduudu",
        name: "民谣常用",
        subtitle: "下下上 上下上",
        tip: "经典型：前两拍「下下」，后两拍「上上下上」的变体，先慢速跟拍。",
        difficulty: .中级,
        events: [e(.down, 1), e(.down, 1), e(.up, 1), e(.up, 1), e(.down, 1), e(.up, 1), e(.rest, 2)]
    ),
    makePattern(
        id: "chunk-double",
        name: "双 Chunk",
        subtitle: "下下上 下下上",
        tip: "两拍一组「下下上」连做两次，流行歌常用，注意第二组不要抢拍。",
        difficulty: .中级,
        events: [e(.down, 1), e(.down, 1), e(.up, 1), e(.up, 1), e(.down, 1), e(.down, 1), e(.up, 1), e(.up, 1)]
    ),
    makePattern(
        id: "driving-triplets-feel",
        name: "行进感",
        subtitle: "三下接一上",
        tip: "连续三个下扫后接一个上扫，有推进感；先慢速再加速。",
        difficulty: .中级,
        events: [e(.down, 1), e(.down, 1), e(.down, 1), e(.up, 1), e(.down, 1), e(.down, 1), e(.down, 1), e(.up, 1)]
    ),
    makePattern(
        id: "offbeat-downs",
        name: "反拍八分",
        subtitle: "弱拍下扫",
        tip: "正拍不扫、弱拍扫，先小声找「反拍」位置，再加重。",
        difficulty: .中级,
        events: [e(.rest, 1), e(.down, 1), e(.rest, 1), e(.down, 1), e(.rest, 1), e(.down, 1), e(.rest, 1), e(.down, 1)]
    ),
    makePattern(
        id: "ska-ups",
        name: "Ska 上扫",
        subtitle: "弱拍上扫",
        tip: "正拍休止、弱拍上扫，手腕略抬高；可与反拍下扫对照练。",
        difficulty: .中级,
        events: [e(.rest, 1), e(.up, 1), e(.rest, 1), e(.up, 1), e(.rest, 1), e(.up, 1), e(.rest, 1), e(.up, 1)]
    ),
]

private let advancedPatterns: [StrummingPattern] = [
    makePattern(
        id: "reggae-backbeat",
        name: "雷鬼反拍",
        subtitle: "2、4 拍",
        tip: "只在第 2、4 拍正点下扫，其余不扫，适合雷鬼/慢摇滚律动。",
        difficulty: .高级,
        events: [e(.rest, 2), e(.down, 2), e(.rest, 2), e(.down, 2)]
    ),
    makePattern(
        id: "percussive-du-gap",
        name: "下切上",
        subtitle: "带空隙",
        tip: "下—空—上循环，空拍可做护弦或制音，偏节奏吉他。",
        difficulty: .高级,
        events: [e(.down, 1), e(.mute, 1), e(.up, 1), e(.rest, 1), e(.down, 1), e(.mute, 1), e(.up, 1), e(.rest, 1)]
    ),
    makePattern(
        id: "shuffle-eighths",
        name: "Shuffle 感",
        subtitle: "长短短",
        tip: "近似三连音长短短：长音用下扫，短音用上扫，慢速对齐摇摆感。",
        difficulty: .高级,
        events: [e(.down, 2), e(.up, 1), e(.rest, 1), e(.down, 2), e(.up, 1), e(.rest, 1)]
    ),
]

let kStrummingPatterns: [StrummingPattern] =
    beginnerPatterns + intermediatePatterns + advancedPatterns

enum StrummingPatternGenerator {
    static func nextPattern(
        difficulty: StrummingDifficulty,
        excluding currentId: String? = nil,
        using rng: inout some RandomNumberGenerator
    ) -> StrummingPattern {
        let pool = poolForDifficulty(difficulty)
        guard !pool.isEmpty else { return kStrummingPatterns.first! }

        // 避免连续两次完全相同（当池子至少有 2 个时）。
        if let currentId, pool.count > 1 {
            let candidates = pool.filter { $0.id != currentId }
            if let p = candidates.randomElement(using: &rng) {
                return p
            }
        }
        return pool.randomElement(using: &rng) ?? pool[0]
    }

    static func defaultPattern(for difficulty: StrummingDifficulty) -> StrummingPattern {
        poolForDifficulty(difficulty).first ?? kStrummingPatterns.first!
    }

    static func poolForDifficulty(_ difficulty: StrummingDifficulty) -> [StrummingPattern] {
        switch difficulty {
        case .初级:
            return beginnerPatterns
        case .中级:
            return intermediatePatterns
        case .高级:
            return advancedPatterns
        }
    }
}

func strummingPatternNameForId(_ id: String?) -> String? {
    guard let id, !id.isEmpty else { return nil }
    return kStrummingPatterns.first(where: { $0.id == id })?.name
}

