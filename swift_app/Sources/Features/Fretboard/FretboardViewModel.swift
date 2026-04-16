import Foundation

@MainActor
public final class FretboardViewModel: ObservableObject {
    @Published public var capo = 0
    @Published public var naturalOnly = false
    @Published public var mirror = false

    private let tonePlayer: FretboardTonePlayer

    public init(tonePlayer: FretboardTonePlayer = FretboardTonePlayer()) {
        self.tonePlayer = tonePlayer
    }

    public func labelForCell(stringIndex: Int, fret: Int) -> String? {
        FretboardMath.labelForCell(
            stringIndex: stringIndex,
            fret: fret,
            capo: capo,
            naturalOnly: naturalOnly
        )
    }

    public func playCell(stringIndex: Int, fret: Int) {
        let midi = FretboardMath.midiAtFret(stringIndex: stringIndex, fret: fret, capo: capo)
        tonePlayer.playMidi(midi)
    }
}

