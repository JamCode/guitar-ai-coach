import Foundation

// Keep aligned with Flutter `chord_progression_library.dart`.

enum ChordComplexity: String, CaseIterable, Identifiable {
    case basic
    case intermediate
    case advanced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .basic: "基础"
        case .intermediate: "进阶"
        case .advanced: "高级"
        }
    }

    var fullLabel: String {
        switch self {
        case .basic: "基础（三和弦）"
        case .intermediate: "进阶（七和弦）"
        case .advanced: "高级（九和弦+）"
        }
    }

    /// 与 Tools「和弦切换」初 / 中 / 高档级文案对齐（用于标签展示）。
    var practiceTierZh: String {
        switch self {
        case .basic: "初级"
        case .intermediate: "中级"
        case .advanced: "高级"
        }
    }
}

struct ChordProgression: Identifiable, Equatable {
    let id: String
    let name: String
    /// 连字符分隔的罗马级数，如 `I-V-vi-IV`。
    let romanNumerals: String
    /// 风格标签，用于列表分组。
    let style: String
    let description: String?
}

extension ChordProgression {
    /// 不再由用户手选复杂度：按进行风格给出默认和弦档次（与罗马级数解析表一致）。
    var impliedComplexity: ChordComplexity {
        switch style {
        case "Jazz": return .advanced
        case "Blues": return .intermediate
        default: return .basic
        }
    }
}

let kChordProgressions: [ChordProgression] = [
    // Pop
    ChordProgression(id: "pop-classic", name: "流行经典", romanNumerals: "I-V-vi-IV", style: "Pop", description: "全球最常见的流行和弦走向"),
    ChordProgression(id: "pop-50s", name: "50 年代", romanNumerals: "I-vi-IV-V", style: "Pop", description: nil),
    ChordProgression(id: "pop-minor", name: "小调流行", romanNumerals: "vi-IV-I-V", style: "Pop", description: nil),
    ChordProgression(id: "pop-canon", name: "卡农进行", romanNumerals: "I-V-vi-iii-IV-I-IV-V", style: "Pop", description: "帕赫贝尔卡农经典 8 和弦"),
    ChordProgression(id: "pop-emotional", name: "催泪进行", romanNumerals: "IV-V-iii-vi", style: "Pop", description: nil),
    ChordProgression(id: "pop-axis", name: "轴心进行", romanNumerals: "I-V-vi-iii", style: "Pop", description: nil),

    // Rock
    ChordProgression(id: "rock-classic", name: "经典三和弦", romanNumerals: "I-IV-V-I", style: "Rock", description: nil),
    ChordProgression(id: "rock-mixo", name: "混合利底亚", romanNumerals: "I-bVII-IV-I", style: "Rock", description: nil),
    ChordProgression(id: "rock-power", name: "力量进行", romanNumerals: "I-bVII-bVI-V", style: "Rock", description: "安达卢西亚终止变体"),

    // Blues
    ChordProgression(id: "blues-12bar", name: "12 小节布鲁斯", romanNumerals: "I-I-I-I-IV-IV-I-I-V-IV-I-V", style: "Blues", description: nil),
    ChordProgression(id: "blues-quick4", name: "快四布鲁斯", romanNumerals: "I-IV-I-I-IV-IV-I-I-V-IV-I-V", style: "Blues", description: "第 2 小节提前到 IV 级"),

    // Jazz
    ChordProgression(id: "jazz-251", name: "二五一", romanNumerals: "ii-V-I", style: "Jazz", description: "爵士最核心的终止进行"),
    ChordProgression(id: "jazz-turnaround", name: "回转进行", romanNumerals: "I-vi-ii-V", style: "Jazz", description: nil),
    ChordProgression(id: "jazz-rhythm", name: "节奏变化", romanNumerals: "ii-V-I-vi", style: "Jazz", description: nil),

    // Folk
    ChordProgression(id: "folk-basic", name: "民谣三和弦", romanNumerals: "I-IV-V-IV", style: "Folk", description: nil),
    ChordProgression(id: "folk-vi", name: "民谣四和弦", romanNumerals: "I-vi-IV-V", style: "Folk", description: nil),
]

let kProgressionStyles: [String] = ["Pop", "Rock", "Blues", "Jazz", "Folk"]

let kStyleLabels: [String: String] = [
    "Pop": "流行",
    "Rock": "摇滚",
    "Blues": "布鲁斯",
    "Jazz": "爵士",
    "Folk": "民谣",
]

let kMusicKeys: [String] = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

enum ChordProgressionEngine {
    private static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    private static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let sharpKeys: Set<String> = ["C", "G", "D", "A", "E", "B"]

    private static let notePcMap: [String: Int] = [
        "C": 0, "C#": 1, "Db": 1,
        "D": 2, "D#": 3, "Eb": 3,
        "E": 4, "F": 5, "F#": 6,
        "Gb": 6, "G": 7, "G#": 8,
        "Ab": 8, "A": 9, "A#": 10,
        "Bb": 10, "B": 11,
    ]

    /// 每个罗马级数在 C 调下的和弦符号（三档复杂度）。
    private static let romanToChordInC: [String: [ChordComplexity: String]] = [
        "I": [.basic: "C", .intermediate: "Cmaj7", .advanced: "Cmaj9"],
        "ii": [.basic: "Dm", .intermediate: "Dm7", .advanced: "Dm9"],
        "iii": [.basic: "Em", .intermediate: "Em7", .advanced: "Em9"],
        "IV": [.basic: "F", .intermediate: "Fmaj7", .advanced: "Fmaj9"],
        "V": [.basic: "G", .intermediate: "G7", .advanced: "G9"],
        "vi": [.basic: "Am", .intermediate: "Am7", .advanced: "Am9"],
        "vii": [.basic: "Bdim", .intermediate: "Bm7b5", .advanced: "Bm7b5"],
        // 借用和弦 —— 根音在 C 调下用降号表示
        "bVII": [.basic: "Bb", .intermediate: "Bb7", .advanced: "Bb9"],
        "bIII": [.basic: "Eb", .intermediate: "Ebmaj7", .advanced: "Ebmaj9"],
        "bVI": [.basic: "Ab", .intermediate: "Abmaj7", .advanced: "Abmaj9"],
        // 自然小调级数
        "i": [.basic: "Cm", .intermediate: "Cm7", .advanced: "Cm9"],
        "iv": [.basic: "Fm", .intermediate: "Fm7", .advanced: "Fm9"],
        "v": [.basic: "Gm", .intermediate: "Gm7", .advanced: "Gm9"],
    ]

    static func resolveChordNames(romanNumerals: String, key: String, complexity: ChordComplexity) -> [String] {
        let romans = romanNumerals
            .split(separator: "-")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return romans.map { resolveSingle($0, key: key, complexity: complexity) }
    }

    private static func resolveSingle(_ roman: String, key: String, complexity: ChordComplexity) -> String {
        guard let chordMap = romanToChordInC[roman] else { return roman }
        let chordInC = chordMap[complexity] ?? chordMap[.basic] ?? roman
        if key == "C" { return chordInC }
        let isBorrowed = roman.hasPrefix("b")
        return transposeChord(chordInC, toKey: key, forceFlats: isBorrowed)
    }

    /// 将 C 调和弦符号移至目标调。
    /// - parameter forceFlats: 为 true 时即使目标调为升号调也使用降号命名（用于 bVII / bVI / bIII 等借用和弦）。
    private static func transposeChord(_ chordInC: String, toKey: String, forceFlats: Bool) -> String {
        let delta = notePcMap[toKey] ?? 0
        guard delta != 0 else { return chordInC }

        let regex = try? NSRegularExpression(pattern: #"^([A-G])([#b]?)(.*)$"#, options: [])
        guard let regex else { return chordInC }
        let range = NSRange(chordInC.startIndex..<chordInC.endIndex, in: chordInC)
        guard let match = regex.firstMatch(in: chordInC, options: [], range: range),
              match.numberOfRanges >= 4
        else { return chordInC }

        func group(_ i: Int) -> String {
            guard let r = Range(match.range(at: i), in: chordInC) else { return "" }
            return String(chordInC[r])
        }

        let rootNote = group(1) + group(2)
        let suffix = group(3)
        let rootPc = notePcMap[rootNote] ?? 0
        let newPc = (rootPc + delta) % 12

        let useFlats = forceFlats || !sharpKeys.contains(toKey)
        let newRoot = useFlats ? flatNames[newPc] : sharpNames[newPc]
        return newRoot + suffix
    }
}

