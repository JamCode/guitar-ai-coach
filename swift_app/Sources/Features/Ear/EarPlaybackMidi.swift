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
            let root = progressionRoot(key: key, roman: roman)
            let quality: [Int] = roman.lowercased().contains("vii")
                ? [0, 3, 6]
                : (roman == roman.lowercased() ? [0, 3, 7] : [0, 4, 7])
            return quality.map { root + $0 }
        }
    }

    private static func progressionRoot(key: String, roman: String) -> Int {
        let scale: [Int] = [0, 2, 4, 5, 7, 9, 11]
        let degree: Int
        switch roman.lowercased().replacingOccurrences(of: "°", with: "") {
        case "i": degree = 0
        case "ii": degree = 1
        case "iii": degree = 2
        case "iv": degree = 3
        case "v": degree = 4
        case "vi": degree = 5
        case "vii": degree = 6
        default: degree = 0
        }
        return noteToMidi(key, octave: 4) + scale[degree]
    }

    /// 如 `I-V-vi-IV` 在 C 大调 → `["C","G","Am","F"]`（与当前三和弦听辨算法一致）。
    public static func letterChordSymbols(key: String, progressionRoman: String) -> [String] {
        progressionRoman
            .split(separator: "-")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { letterChordSymbol(key: key, roman: $0) }
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
        let rootMidi = progressionRoot(key: key, roman: roman)
        let pc = ((rootMidi % 12) + 12) % 12
        let name = sharpPitchClassNames[pc]
        if roman.lowercased().contains("vii") {
            return "\(name)dim"
        }
        let isMinorTriad = roman == roman.lowercased()
        return isMinorTriad ? "\(name)m" : name
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
