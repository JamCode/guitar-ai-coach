import Foundation
import Core

public enum FretboardMath {
    public static let openMidiStrings = [40, 45, 50, 55, 59, 64]
    public static let stringNames = ["E", "A", "D", "G", "B", "E"]

    public static func midiAtFret(stringIndex: Int, fret: Int, capo: Int) -> Int {
        openMidiStrings[stringIndex] + fret + capo
    }

    public static func labelForCell(stringIndex: Int, fret: Int, capo: Int, naturalOnly: Bool) -> String? {
        let midi = midiAtFret(stringIndex: stringIndex, fret: fret, capo: capo)
        let note = PitchMath.midiToNoteName(midi)
        if naturalOnly && note.contains("#") {
            return nil
        }
        return note
    }
}

