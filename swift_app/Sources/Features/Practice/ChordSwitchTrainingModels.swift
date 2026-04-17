import Foundation

// MARK: - 难度

public enum ChordSwitchDifficulty: String, Sendable, CaseIterable, Codable, Identifiable {
    case 初级
    case 中级
    case 高级

    public var id: String { rawValue }
}

// MARK: - 一组和弦（一次切换练习块）

/// 一个「切换组」内的和弦按弹奏顺序排列。
public struct ChordSwitchSegment: Sendable, Hashable, Codable {
    public var chords: [String]

    public init(chords: [String]) {
        self.chords = chords
    }

    public var summaryZh: String {
        chords.joined(separator: " → ")
    }
}

// MARK: - 整条题目

public struct ChordSwitchExercise: Sendable, Identifiable, Hashable, Codable {
    public var id: String
    public var difficulty: ChordSwitchDifficulty
    /// 多组串联；每组内按顺序切换。
    public var segments: [ChordSwitchSegment]
    public var bpmMin: Int
    public var bpmMax: Int
    /// 每个和弦所占拍数：初级 2；中级 1；高级 0.5（半拍）。
    public var beatsPerChord: Double
    public var promptZh: String
    public var goalsZh: [String]

    public init(
        id: String,
        difficulty: ChordSwitchDifficulty,
        segments: [ChordSwitchSegment],
        bpmMin: Int,
        bpmMax: Int,
        beatsPerChord: Double,
        promptZh: String,
        goalsZh: [String]
    ) {
        self.id = id
        self.difficulty = difficulty
        self.segments = segments
        self.bpmMin = bpmMin
        self.bpmMax = bpmMax
        self.beatsPerChord = beatsPerChord
        self.promptZh = promptZh
        self.goalsZh = goalsZh
    }

    /// 顺序展开所有和弦，便于节拍器或跟练 UI。
    public var flattenedChords: [String] {
        segments.flatMap(\.chords)
    }

    public var bpmHintZh: String {
        let beatWord: String
        if beatsPerChord == 2 { beatWord = "每和弦 2 拍" }
        else if beatsPerChord == 1 { beatWord = "每和弦 1 拍" }
        else { beatWord = "每和弦 ½ 拍（八分音符为一拍时等价于一拍两和弦）" }
        return "建议节拍器 \(bpmMin)–\(bpmMax) BPM，\(beatWord)。"
    }
}
