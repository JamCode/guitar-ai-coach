import Foundation

// MARK: - 难度

public enum ScaleTrainingDifficulty: String, Sendable, CaseIterable, Codable, Identifiable {
    case 初级
    case 中级
    case 高级

    public var id: String { rawValue }
}

// MARK: - 音阶类型（可枚举、无模糊）

public enum ScaleTrainingScaleKind: String, Sendable, Hashable, Codable, CaseIterable {
    case 自然大调
    case 自然小调
    case 五声音阶大调
    case 五声音阶小调

    /// 相对主音的半音程（含八度终点）。
    public func intervalsOneOctaveInclusive() -> [Int] {
        switch self {
        case .自然大调:
            return [0, 2, 4, 5, 7, 9, 11, 12]
        case .自然小调:
            return [0, 2, 3, 5, 7, 8, 10, 12]
        case .五声音阶大调:
            return [0, 2, 4, 7, 9, 12]
        case .五声音阶小调:
            return [0, 3, 5, 7, 10, 12]
        }
    }

    public var degreeCount: Int {
        switch self {
        case .自然大调, .自然小调: return 8
        case .五声音阶大调, .五声音阶小调: return 6
        }
    }
}

// MARK: - 指型（Mi / Sol / La：根音所在弦，可码）

/// 基础指型：根音落在 **六 / 五 / 四弦**（`stringIndexFromBass` 0/1/2），与常见 CAGED 教学中 Mi/Sol/La 命名对齐。
public enum ScaleTrainingFingerPattern: String, Sendable, Hashable, Codable, CaseIterable {
    case Mi
    case Sol
    case La

    public var anchorStringIndexFromBass: Int {
        switch self {
        case .Mi: return 0
        case .Sol: return 1
        case .La: return 2
        }
    }

    public var titleZh: String {
        switch self {
        case .Mi: return "Mi 指型"
        case .Sol: return "Sol 指型"
        case .La: return "La 指型"
        }
    }
}

// MARK: - 弹奏方向（题目层）

public enum ScaleTrainingPlayDirection: String, Sendable, Codable, Hashable {
    /// 从主音到高八度主音（含终点）。
    case 上行
    /// 从高八度主音回到主音。
    case 下行
    /// 上行至终点的音后，再下行回到起点（终点音只出现一次）。
    case 上下行
}

// MARK: - 音符时值（展示与节拍器文案）

public enum ScaleTrainingRhythmGrid: String, Sendable, Codable, Hashable {
    case 八分音符
    case 十六分音符

    public var userLabelZh: String { rawValue }
}

// MARK: - 单步

public struct ScaleTrainingStep: Identifiable, Sendable, Hashable, Codable {
    public var id: Int
    public var stringIndexFromBass: Int
    public var fret: Int
    public var midi: Int
    public var pitchLabelZh: String
    /// 在当前音阶类型下相对主音的级数标签，如「1」「♭3」（五声小调用数字即可：1…5）。
    public var degreeLabelZh: String

    public init(
        id: Int,
        stringIndexFromBass: Int,
        fret: Int,
        midi: Int,
        pitchLabelZh: String,
        degreeLabelZh: String
    ) {
        self.id = id
        self.stringIndexFromBass = stringIndexFromBass
        self.fret = fret
        self.midi = midi
        self.pitchLabelZh = pitchLabelZh
        self.degreeLabelZh = degreeLabelZh
    }

    public var lineSummaryZh: String {
        "\(TraditionalCrawlCopy.chineseStringName(fromBassIndex: stringIndexFromBass)) \(fret)品 · \(pitchLabelZh)（\(degreeLabelZh)）"
    }
}

// MARK: - 整条练习（界面 / JSON）

public struct ScaleTrainingExercise: Sendable, Identifiable, Hashable, Codable {
    public var id: String
    public var difficulty: ScaleTrainingDifficulty
    public var keyName: String
    public var scaleKind: ScaleTrainingScaleKind
    public var pattern: ScaleTrainingFingerPattern
    public var direction: ScaleTrainingPlayDirection
    public var rhythm: ScaleTrainingRhythmGrid
    public var bpmMin: Int
    public var bpmMax: Int
    public var allowsSequenceShift: Bool
    public var allowsDegreeLeap: Bool
    public var usesAllStrings: Bool
    /// 若为 `true`，表示整段 MIDI 序列在展示前已做时间反向（与 `direction` 独立，便于统计）。
    public var retrogradeApplied: Bool
    public var promptZh: String
    public var goalsZh: [String]
    public var steps: [ScaleTrainingStep]

    public var bpmRange: ClosedRange<Int> { bpmMin ... bpmMax }

    public init(
        id: String,
        difficulty: ScaleTrainingDifficulty,
        keyName: String,
        scaleKind: ScaleTrainingScaleKind,
        pattern: ScaleTrainingFingerPattern,
        direction: ScaleTrainingPlayDirection,
        rhythm: ScaleTrainingRhythmGrid,
        bpmMin: Int,
        bpmMax: Int,
        allowsSequenceShift: Bool,
        allowsDegreeLeap: Bool,
        usesAllStrings: Bool,
        retrogradeApplied: Bool,
        promptZh: String,
        goalsZh: [String],
        steps: [ScaleTrainingStep]
    ) {
        self.id = id
        self.difficulty = difficulty
        self.keyName = keyName
        self.scaleKind = scaleKind
        self.pattern = pattern
        self.direction = direction
        self.rhythm = rhythm
        self.bpmMin = bpmMin
        self.bpmMax = bpmMax
        self.allowsSequenceShift = allowsSequenceShift
        self.allowsDegreeLeap = allowsDegreeLeap
        self.usesAllStrings = usesAllStrings
        self.retrogradeApplied = retrogradeApplied
        self.promptZh = promptZh
        self.goalsZh = goalsZh
        self.steps = steps
    }

    public var bpmHintZh: String {
        "建议节拍器 \(bpmMin)–\(bpmMax) BPM，一\(rhythm == .八分音符 ? "拍两音" : "拍四音")（\(rhythm.userLabelZh)）。"
    }
}
