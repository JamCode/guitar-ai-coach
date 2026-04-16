import Foundation

public enum PitchMath {
    public static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    /// 科学音高记谱用小写字母 + `#` 变音 + 八度（MIDI 60 → `c4`）。
    private static let pitchClassLabelsLower = ["c", "c#", "d", "d#", "e", "f", "f#", "g", "g#", "a", "a#", "b"]

    public static func frequencyToMidi(_ hz: Double) -> Int {
        guard hz > 0 else { return 0 }
        return Int(round(69.0 + 12.0 * log2(hz / 440.0)))
    }

    public static func midiToNoteName(_ midi: Int) -> String {
        let index = ((midi % 12) + 12) % 12
        return noteNames[index]
    }

    /// 带八度的音高标签，例如 MIDI 40 → `e2`，MIDI 69 → `a4`。
    public static func midiToPitchLabel(_ midi: Int) -> String {
        let pc = ((midi % 12) + 12) % 12
        let name = pitchClassLabelsLower[pc]
        let octave = midi / 12 - 1
        return "\(name)\(octave)"
    }

    public static func centsBetween(actualHz: Double, targetHz: Double) -> Double {
        guard actualHz > 0, targetHz > 0 else { return 0 }
        return 1200.0 * log2(actualHz / targetHz)
    }
}

