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
    /// 出题固定为 C 大调（和弦符号与级数均相对 C）。
    public var keyZh: String
    /// 与 `flattenedChords` 等长的一一对应级数（如 I、vi、IV、V7）。
    public var romanNumerals: [String]
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
        keyZh: String,
        romanNumerals: [String],
        bpmMin: Int,
        bpmMax: Int,
        beatsPerChord: Double,
        promptZh: String,
        goalsZh: [String]
    ) {
        self.id = id
        self.difficulty = difficulty
        self.segments = segments
        self.keyZh = keyZh
        self.romanNumerals = romanNumerals
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

    /// 级数连成一句，如 `I → vi → IV → V`。
    public var romanProgressionZh: String {
        romanNumerals.joined(separator: " → ")
    }

    public var bpmHintZh: String {
        let beatWord: String
        if beatsPerChord == 2 { beatWord = "每和弦 2 拍" }
        else if beatsPerChord == 1 { beatWord = "每和弦 1 拍" }
        else { beatWord = "每和弦 ½ 拍（八分音符为一拍时等价于一拍两和弦）" }
        return "建议节拍器 \(bpmMin)–\(bpmMax) BPM，\(beatWord)。"
    }
}

// MARK: - 参考调性（用于 UI 展示，非乐理判题）

public enum ChordSwitchKeyResolver {
    /// 自然大调音阶内的根音 pitch class（相对主音 0）。
    private static let majorScalePCs: Set<Int> = [0, 2, 4, 5, 7, 9, 11]

    private static let rootPitchClass: [String: Int] = [
        "C": 0, "C#": 1, "Db": 1,
        "D": 2, "D#": 3, "Eb": 3,
        "E": 4,
        "F": 5, "F#": 6, "Gb": 6,
        "G": 7, "G#": 8, "Ab": 8,
        "A": 9, "A#": 10, "Bb": 10,
        "B": 11,
    ]

    private static let tonicOrder: [String] = [
        "C", "G", "D", "A", "E", "B", "F#", "C#", "F", "Bb", "Eb", "Ab",
    ]

    private static let tonicPitchClasses: [String: Int] = [
        "C": 0, "G": 7, "D": 2, "A": 9, "E": 4, "B": 11, "F#": 6, "C#": 1,
        "F": 5, "Bb": 10, "Eb": 3, "Ab": 8,
    ]

    /// 从练习中出现的和弦符号推断「最像」的自然大调主音，用于齿轮内「参考调性」文案。
    public static func referenceMajorKeyLabel(for exercise: ChordSwitchExercise) -> String {
        referenceMajorKeyLabel(forChordSymbols: exercise.flattenedChords)
    }

    public static func referenceMajorKeyLabel(forChordSymbols symbols: [String]) -> String {
        let roots = symbols.compactMap { Self.parseRoot($0) }
        guard !roots.isEmpty else { return "参考调性未明" }

        var bestTonic = "C"
        var bestScore = -1
        for tonic in tonicOrder {
            guard let tpc = tonicPitchClasses[tonic] else { continue }
            var score = 0
            for sym in symbols {
                guard let r = Self.parseRoot(sym), let rpc = rootPitchClass[r] else { continue }
                let rel = (rpc - tpc + 12) % 12
                if majorScalePCs.contains(rel) { score += 1 }
            }
            if score > bestScore {
                bestScore = score
                bestTonic = tonic
            }
        }
        return "\(bestTonic) 调"
    }

    private static func parseRoot(_ symbol: String) -> String? {
        let s = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let rootsLongestFirst = [
            "C#", "Db", "D#", "Eb", "F#", "Gb", "G#", "Ab", "A#", "Bb",
            "C", "D", "E", "F", "G", "A", "B",
        ]
        for r in rootsLongestFirst where s.hasPrefix(r) {
            return r
        }
        return nil
    }
}
