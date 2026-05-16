import Foundation

public enum EarPlaybackMidi {
    public static func forSingleChord(_ item: EarBankItem) -> [Int] {
        let root = noteToMidi(item.root ?? "C", octave: 4)
        let quality = item.targetQuality?.lowercased() ?? "major"
        let intervals: [Int]
        switch quality {
        case "minor", "min", "m":
            intervals = [0, 3, 7]
        case "dominant7", "7", "dom7":
            intervals = [0, 4, 7, 10]
        case "major7", "maj7", "m7maj", "delta":
            intervals = [0, 4, 7, 11]
        case "minor7", "min7", "m7":
            intervals = [0, 3, 7, 10]
        default:
            intervals = [0, 4, 7]
        }
        return intervals.map { root + $0 }
    }

    public static func forProgression(_ item: EarBankItem) -> [[Int]] {
        let key = item.musicKey ?? "C"
        let romans = (item.progressionRoman ?? "I-V-vi-IV")
            .split(separator: "-")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return romans.map { roman in
            let root = progressionChordRootMidi(key: key, roman: roman)
            return progressionIntervals(roman: roman).map { root + $0 }
        }
    }

    /// 和弦根音 MIDI（4 组），支持练耳程序化扩展：`V7`、`ii7`、`(V/ii)`、`bVI` 等。
    public static func progressionChordRootMidi(key: String, roman: String) -> Int {
        let tonic = noteToMidi(key, octave: 4)
        let pc = chordRootPcFromTonic(roman: roman)
        let tonicPc = tonic % 12
        let rootPc = (tonicPc + pc + 12) % 12
        let octaveBase = tonic - tonicPc
        return octaveBase + rootPc
    }

    /// 根音相对主音的半音偏移（0…11）。
    private static func chordRootPcFromTonic(roman: String) -> Int {
        let r = roman.trimmingCharacters(in: .whitespacesAndNewlines)
        let majorSteps = [0, 2, 4, 5, 7, 9, 11]
        func deg(_ i: Int) -> Int { majorSteps[i % 7] }

        switch r {
        case "I", "i":
            return deg(0)
        case "ii", "ii7":
            return deg(1)
        case "iii":
            return deg(2)
        case "IV", "iv":
            return deg(3)
        case "V", "V7":
            return deg(4)
        case "vi", "vi7":
            return deg(5)
        case "vii", "vii°":
            return deg(6)
        case "bVI":
            return 8
        case "bIII":
            return 3
        case "(V/ii)":
            return (deg(1) + 7) % 12
        case "(V/vi)":
            return (deg(5) + 7) % 12
        default:
            return deg(0)
        }
    }

    private static func progressionIntervals(roman: String) -> [Int] {
        let r = roman.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.lowercased().contains("vii") {
            return [0, 3, 6]
        }
        switch r {
        case "ii7", "vi7":
            return [0, 3, 7, 10]
        case "V7":
            return [0, 4, 7, 10]
        case "iv":
            return [0, 3, 7]
        case "bVI", "bIII", "I", "IV", "V":
            return [0, 4, 7]
        default:
            return r == r.lowercased() ? [0, 3, 7] : [0, 4, 7]
        }
    }

    /// 如 `I-V-vi-IV` 在 C 大调 → `["C","G","Am","F"]`（与当前三和弦听辨算法一致）。
    public static func letterChordSymbols(key: String, progressionRoman: String) -> [String] {
        progressionRoman
            .split(separator: "-")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { letterChordSymbol(key: key, roman: $0) }
    }

    /// 与 `letterChordSymbols` 一致：单 token → 展示用字母和弦（供 `OfflineChordBuilder` 等）。
    public static func letterChordSymbolForProgressionToken(key: String, roman: String) -> String {
        letterChordSymbol(key: key, roman: roman)
    }

    /// `progression_roman` 按 `-` 分割后的功能标记段数（与 `letterChordSymbols` 分割规则一致）。
    public static func romanNumeralSegmentCount(_ progressionRoman: String) -> Int {
        progressionRoman
            .split(separator: "-")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private static func letterChordSymbol(key: String, roman: String) -> String {
        let rootMidi = progressionChordRootMidi(key: key, roman: roman)
        let pc = ((rootMidi % 12) + 12) % 12
        let name = sharpPitchClassNames[pc]
        let r = roman.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.lowercased().contains("vii") {
            return "\(name)dim"
        }
        switch r {
        case "V7":
            return "\(name)7"
        case "ii7", "vi7":
            return "\(name)m7"
        case "iv":
            return "\(name)m"
        case "bVI", "bIII":
            return name
        case "(V/ii)", "(V/vi)":
            return "\(name)7"
        default:
            let isMinorTriad = r == r.lowercased()
            return isMinorTriad ? "\(name)m" : name
        }
    }

    private static let sharpPitchClassNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    private static func noteToMidi(_ note: String, octave: Int) -> Int {
        let normalized = note.trimmingCharacters(in: .whitespaces)
            .uppercased()
            .replacingOccurrences(of: "DB", with: "C#")
            .replacingOccurrences(of: "EB", with: "D#")
            .replacingOccurrences(of: "GB", with: "F#")
            .replacingOccurrences(of: "AB", with: "G#")
            .replacingOccurrences(of: "BB", with: "A#")
        let idx: Int
        switch normalized {
        case "C": idx = 0
        case "C#", "DB": idx = 1
        case "D": idx = 2
        case "D#", "EB": idx = 3
        case "E": idx = 4
        case "F": idx = 5
        case "F#", "GB": idx = 6
        case "G": idx = 7
        case "G#", "AB": idx = 8
        case "A": idx = 9
        case "A#", "BB": idx = 10
        case "B": idx = 11
        default: idx = 0
        }
        return (octave + 1) * 12 + idx
    }
}
