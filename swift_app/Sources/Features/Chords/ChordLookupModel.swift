import Foundation

public struct ChordOption: Identifiable, Hashable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public enum ChordSelectCatalog {
    public static let keys = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    public static let referenceKey = "C"

    public static let qualOptions = [
        ChordOption(id: "", label: "大三和弦"),
        ChordOption(id: "m", label: "小三和弦"),
        ChordOption(id: "7", label: "属七和弦"),
        ChordOption(id: "maj7", label: "大七和弦"),
        ChordOption(id: "m7", label: "小七和弦")
    ]

    public static let bassOptions = [
        ChordOption(id: "", label: "根音位"),
        ChordOption(id: "C", label: "/C"),
        ChordOption(id: "C#", label: "/C#"),
        ChordOption(id: "D", label: "/D"),
        ChordOption(id: "Eb", label: "/Eb"),
        ChordOption(id: "E", label: "/E"),
        ChordOption(id: "F", label: "/F"),
        ChordOption(id: "F#", label: "/F#"),
        ChordOption(id: "G", label: "/G"),
        ChordOption(id: "Ab", label: "/Ab"),
        ChordOption(id: "A", label: "/A"),
        ChordOption(id: "Bb", label: "/Bb"),
        ChordOption(id: "B", label: "/B")
    ]
}

public enum ChordSymbolBuilder {
    public static func build(root: String, qualityId: String, bassId: String) -> String {
        guard !root.isEmpty else { return "" }
        var symbol = root + qualityId
        if !bassId.isEmpty {
            symbol += "/\(bassId)"
        }
        return symbol
    }
}

public struct ChordSummary: Hashable {
    public let symbol: String
    public let notesLetters: [String]
    public let notesExplainZh: String
}

public struct ChordVoicingExplain: Hashable {
    public let frets: [Int]
    public let baseFret: Int
    public let voicingExplainZh: String
}

public struct ChordVoicingItem: Hashable, Identifiable {
    public let id: String
    public let labelZh: String
    public let explain: ChordVoicingExplain

    public init(labelZh: String, explain: ChordVoicingExplain) {
        self.id = labelZh + "_" + explain.frets.map(String.init).joined(separator: "_")
        self.labelZh = labelZh
        self.explain = explain
    }
}

public struct ChordExplainMultiPayload: Hashable {
    public let chordSummary: ChordSummary
    public let voicings: [ChordVoicingItem]
    public let disclaimer: String
}

public enum ChordTransposeLocal {
    private static let pcs: [String: Int] = [
        "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5,
        "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11
    ]
    private static let sharpKeys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    public static func transposeChordSymbol(_ symbol: String, from: String, to: String) -> String {
        guard let fromPc = pcs[from], let toPc = pcs[to] else { return symbol }
        let delta = (toPc - fromPc + 12) % 12
        guard !symbol.isEmpty else { return symbol }
        let parts = symbol.split(separator: "/", maxSplits: 1).map(String.init)
        let main = transposeSingle(parts[0], delta: delta)
        if parts.count == 1 { return main }
        let slash = transposeSingle(parts[1], delta: delta)
        return "\(main)/\(slash)"
    }

    private static func transposeSingle(_ token: String, delta: Int) -> String {
        let roots = ["C#", "Db", "D#", "Eb", "F#", "Gb", "G#", "Ab", "A#", "Bb", "C", "D", "E", "F", "G", "A", "B"]
        for root in roots where token.hasPrefix(root) {
            guard let pc = pcs[root] else { continue }
            let transposed = sharpKeys[(pc + delta) % 12]
            return transposed + token.dropFirst(root.count)
        }
        return token
    }
}

public enum OfflineChordBuilder {
    private static let spelling: [String: [String]] = [
        "": ["1", "3", "5"],
        "m": ["1", "b3", "5"],
        "7": ["1", "3", "5", "b7"],
        "maj7": ["1", "3", "5", "7"],
        "m7": ["1", "b3", "5", "b7"],
        "dim": ["1", "b3", "b5"],
        "aug": ["1", "3", "#5"],
        "sus2": ["1", "2", "5"],
        "sus4": ["1", "4", "5"],
        "m7b5": ["1", "b3", "b5", "b7"],
        "add9": ["1", "3", "5", "9"],
        "6": ["1", "3", "5", "6"],
        "m6": ["1", "b3", "5", "6"],
        "9": ["1", "3", "5", "b7", "9"],
        "m9": ["1", "b3", "5", "b7", "9"],
        "maj9": ["1", "3", "5", "7", "9"]
    ]

    private static let keyToPc: [String: Int] = [
        "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5,
        "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11
    ]
    private static let pcToName = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    private static let overrides: [String: [[Int]]] = [
        "C": [[-1, 3, 2, 0, 1, 0], [-1, 3, 5, 5, 5, 3]],
        "G": [[3, 2, 0, 0, 0, 3], [3, 2, 0, 0, 3, 3]],
        "D": [[-1, -1, 0, 2, 3, 2], [-1, -1, 0, 7, 7, 5]],
        "A": [[-1, 0, 2, 2, 2, 0], [5, 5, 7, 7, 7, 5]],
        "E": [[0, 2, 2, 1, 0, 0], [0, 7, 6, 7, 7, 0]],
        "Am": [[-1, 0, 2, 2, 1, 0], [5, 7, 7, 5, 5, 5]],
        "Em": [[0, 2, 2, 0, 0, 0], [0, 7, 7, 5, 5, 0]],
        "Dm": [[-1, -1, 0, 2, 3, 1], [-1, -1, 0, 5, 7, 5]],
        "F": [[1, 3, 3, 2, 1, 1], [-1, -1, 3, 2, 1, 1]],
        "Asus2": [[-1, 0, 2, 2, 0, 0]],
        "Asus4": [[-1, 0, 2, 2, 3, 0]],
        "Dsus2": [[-1, -1, 0, 2, 3, 0]],
        "Dsus4": [[-1, -1, 0, 2, 3, 3]],
        "Esus4": [[0, 2, 2, 2, 0, 0]],
        "Cadd9": [[-1, 3, 2, 0, 3, 0]],
        "Fmaj7": [[1, 3, 3, 2, 1, 0]]
    ]
    private static let slashOverrides: [String: [[Int]]] = [
        "D/F#": [[2, -1, 0, 2, 3, 2]],
        "G/B": [[-1, 2, 0, 0, 3, 3]],
        "C/E": [[0, 3, 2, 0, 1, 0]],
        "A/C#": [[-1, 4, 2, 2, 2, 0]],
        "E/G#": [[4, -1, 2, 1, 0, 0]],
        "F/A": [[-1, 0, 3, 2, 1, 1]],
        "C/G": [[3, 3, 2, 0, 1, 0]],
        "D/A": [[-1, 0, 0, 2, 3, 2]]
    ]

    public static func buildPayload(displaySymbol: String) -> ChordExplainMultiPayload? {
        let trimmed = displaySymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parsed = parse(trimmed)
        guard let notes = spell(root: parsed.root, quality: parsed.qualityId), notes.count >= 3 else { return nil }

        let summary = ChordSummary(
            symbol: trimmed,
            notesLetters: notes,
            notesExplainZh: explain(quality: parsed.qualityId, slash: parsed.slashBass)
        )

        let exactSlashSymbol = slashPartsJoin(main: parsed.lookupKey, slash: parsed.slashBass)
        let voicingFrets =
            (exactSlashSymbol.flatMap { slashOverrides[$0] })
            ?? overrides[parsed.lookupKey]
            ?? syntheticPair(root: parsed.root, quality: parsed.qualityId)
        guard !voicingFrets.isEmpty else { return nil }
        let hasExactSlashVoicing = exactSlashSymbol.flatMap { slashOverrides[$0] } != nil
        let voicings: [ChordVoicingItem] = voicingFrets.enumerated().map { idx, frets in
            let label = "常用把位 \(idx + 1)"
            let explainText: String
            if parsed.slashBass != nil, idx == 0, hasExactSlashVoicing {
                explainText = "Slash 转位精确低音按法。"
            } else if parsed.slashBass != nil {
                explainText = "转位参考按法；请优先关注低音音位。"
            } else {
                explainText = idx == 0 ? "离线字典收录的常见型。" : "备选按法，可择手型更顺的一种。"
            }
            return ChordVoicingItem(labelZh: label, explain: explainVoicing(frets, text: explainText))
        }

        return ChordExplainMultiPayload(
            chordSummary: summary,
            voicings: voicings,
            disclaimer: parsed.slashBass == nil
                ? "本地和弦速查：指法为常见吉他型，因人而异；不构成音以乐理推算为准。"
                : "Slash 和弦优先展示精确低音按法；若未覆盖全部转位，显示主和弦参考按法，请人工确认低音。"
        )
    }

    private static func parse(_ symbol: String) -> (root: String, qualityId: String, slashBass: String?, lookupKey: String) {
        let slashParts = symbol.split(separator: "/", maxSplits: 1).map(String.init)
        let main = slashParts[0]
        let slash = slashParts.count > 1 ? slashParts[1] : nil
        let roots = ["C#", "Db", "D#", "Eb", "F#", "Gb", "G#", "Ab", "A#", "Bb", "C", "D", "E", "F", "G", "A", "B"]
        for root in roots where main.hasPrefix(root) {
            let q = String(main.dropFirst(root.count))
            let quality = normalize(q)
            return (root, quality, slash, ChordSymbolBuilder.build(root: root, qualityId: quality, bassId: ""))
        }
        return ("C", "", slash, "C")
    }

    private static func normalize(_ q: String) -> String {
        return [
            "", "m", "7", "maj7", "m7", "dim", "aug", "sus2", "sus4",
            "m7b5", "add9", "6", "m6", "9", "m9", "maj9"
        ].contains(q) ? q : ""
    }

    private static func spell(root: String, quality: String) -> [String]? {
        guard let rootPc = keyToPc[root], let intervals = spelling[quality] else { return nil }
        return intervals.compactMap { interval in
            let semitone: Int
            switch interval {
            case "1": semitone = 0
            case "b3": semitone = 3
            case "3": semitone = 4
            case "5": semitone = 7
            case "b5": semitone = 6
            case "#5": semitone = 8
            case "2", "9": semitone = 2
            case "4": semitone = 5
            case "6": semitone = 9
            case "b7": semitone = 10
            case "7": semitone = 11
            default: return nil
            }
            return pcToName[(rootPc + semitone) % 12]
        }
    }

    private static func explain(quality: String, slash: String?) -> String {
        var base: String
        switch quality {
        case "m": base = "小三和弦（根-小三度-纯五度）"
        case "7": base = "属七和弦（根-大三度-纯五度-小七度）"
        case "maj7": base = "大七和弦（根-大三度-纯五度-大七度）"
        case "m7": base = "小七和弦（根-小三度-纯五度-小七度）"
        default: base = "大三和弦（根-大三度-纯五度）"
        }
        if let slash, !slash.isEmpty { base += "；Slash 低音为 \(slash)。" }
        return base
    }

    private static func explainVoicing(_ frets: [Int], text: String) -> ChordVoicingExplain {
        let positive = frets.filter { $0 > 0 }
        let baseFret = positive.min() ?? 1
        return ChordVoicingExplain(frets: frets, baseFret: baseFret, voicingExplainZh: text)
    }

    private static func syntheticPair(root: String, quality: String) -> [[Int]] {
        guard let rootPc = keyToPc[root] else { return [[0, 2, 2, 1, 0, 0], [0, 7, 6, 7, 7, 0]] }
        let f = (rootPc - 4 + 12) % 12
        if quality == "m" || quality == "m7" {
            return [[f, f + 2, f + 2, f, f, f], [f + 3, f + 5, f + 5, f + 3, f + 3, f + 3]]
        }
        return [[f, f + 2, f + 2, f + 1, f, f], [f + 3, f + 5, f + 5, f + 4, f + 3, f + 3]]
    }

    private static func slashPartsJoin(main: String, slash: String?) -> String? {
        guard let slash, !slash.isEmpty else { return nil }
        return "\(main)/\(slash)"
    }
}

