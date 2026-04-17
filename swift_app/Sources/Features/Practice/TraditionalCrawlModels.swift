import Foundation

// MARK: - 难度（传统爬格子：弦内半音四品型 + 换弦平移把位）

/// 传统「四指一格」爬格子推荐难度（供界面展示与筛选）。
public enum TraditionalCrawlDifficulty: String, Sendable, CaseIterable, Codable, Identifiable {
    case 初级
    case 中级
    case 高级

    public var id: String { rawValue }
}

public extension TraditionalCrawlDifficulty {
    /// 界面副标题 / 列表说明。
    var subtitleZh: String {
        switch self {
        case .初级:
            return "仅在六弦低把位完成 1-2-3-4 四指半音，建立手型与保留指。"
        case .中级:
            return "六弦→一弦顺向换弦，每弦四品上行，多轮把位整体上移。"
        case .高级:
            return "全弦多轮 + 每轮后增加下行 4-3-2-1，强化换弦与往返耐力。"
        }
    }
}

// MARK: - 单步（界面一行）

/// 一次落指：`stringIndexFromBass` 与 `FretboardMath.openMidiStrings` 下标一致（0=六弦）。
public struct TraditionalCrawlStep: Identifiable, Sendable, Hashable, Codable {
    public var id: Int
    public var stringIndexFromBass: Int
    public var fret: Int
    /// 左手 1-4 指（食指=1 … 小指=4）。
    public var finger: Int
    /// 绝对品位下的音名简写（如「E」），便于列表展示。
    public var pitchLabelZh: String

    public init(id: Int, stringIndexFromBass: Int, fret: Int, finger: Int, pitchLabelZh: String) {
        self.id = id
        self.stringIndexFromBass = stringIndexFromBass
        self.fret = fret
        self.finger = finger
        self.pitchLabelZh = pitchLabelZh
    }

    /// 「六弦 3品 · 2指 · A」
    public var lineSummaryZh: String {
        "\(TraditionalCrawlCopy.chineseStringName(fromBassIndex: stringIndexFromBass)) \(fret)品 · \(finger)指 · \(pitchLabelZh)"
    }
}

// MARK: - 一整条推荐练习（界面详情页 / 卡片）

public struct TraditionalCrawlExercise: Sendable, Identifiable, Hashable, Codable {
    public var id: String
    public var difficulty: TraditionalCrawlDifficulty
    public var titleZh: String
    public var summaryZh: String
    public var bpmRange: ClosedRange<Int>
    public var steps: [TraditionalCrawlStep]
    public var tipsZh: [String]

    public init(
        id: String,
        difficulty: TraditionalCrawlDifficulty,
        titleZh: String,
        summaryZh: String,
        bpmRange: ClosedRange<Int>,
        steps: [TraditionalCrawlStep],
        tipsZh: [String]
    ) {
        self.id = id
        self.difficulty = difficulty
        self.titleZh = titleZh
        self.summaryZh = summaryZh
        self.bpmRange = bpmRange
        self.steps = steps
        self.tipsZh = tipsZh
    }

    public var bpmHintZh: String {
        "建议节拍器 \(bpmRange.lowerBound)–\(bpmRange.upperBound) BPM，一拍一步。"
    }
}

// MARK: - 文案常量

public enum TraditionalCrawlCopy {
    /// 0=六弦 … 5=一弦
    public static let chineseStringNamesFromBass = ["六弦", "五弦", "四弦", "三弦", "二弦", "一弦"]

    public static func chineseStringName(fromBassIndex: Int) -> String {
        chineseStringNamesFromBass[fromBassIndex]
    }
}
