import Foundation
import Core

public enum FretboardMath {
    public static let openMidiStrings = [40, 45, 50, 55, 59, 64]
    public static let stringNames = ["E", "A", "D", "G", "B", "E"]

    /// 左侧品格为从琴枕起的绝对品；0 品为夹上 capo 后的空弦音，≥1 品为 `open + fret`。
    public static func midiAtFret(stringIndex: Int, fret: Int, capo: Int) -> Int {
        let open = openMidiStrings[stringIndex]
        if fret == 0 {
            return open + capo
        }
        return open + fret
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

