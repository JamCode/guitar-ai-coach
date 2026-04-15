import Foundation

public enum PitchMath {
    public static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    public static func frequencyToMidi(_ hz: Double) -> Int {
        guard hz > 0 else { return 0 }
        return Int(round(69.0 + 12.0 * log2(hz / 440.0)))
    }

    public static func midiToNoteName(_ midi: Int) -> String {
        let index = ((midi % 12) + 12) % 12
        return noteNames[index]
    }

    public static func centsBetween(actualHz: Double, targetHz: Double) -> Double {
        guard actualHz > 0, targetHz > 0 else { return 0 }
        return 1200.0 * log2(actualHz / targetHz)
    }
}

