import Foundation

@MainActor
public final class FretboardViewModel: ObservableObject {
    public struct ActiveCell: Equatable {
        public let stringIndex: Int
        public let fret: Int
    }

    @Published public var capo = 0
    @Published public var naturalOnly = false
    @Published public var mirror = false
    @Published public private(set) var activeCell: ActiveCell?

    private let tonePlayer: FretboardTonePlayer
    private var clearActiveCellTask: Task<Void, Never>?

    public init(tonePlayer: FretboardTonePlayer = FretboardTonePlayer()) {
        self.tonePlayer = tonePlayer
    }

    public func labelForCell(stringIndex: Int, fret: Int) -> String {
        FretboardMath.labelForCell(stringIndex: stringIndex, fret: fret, capo: capo)
    }

    public func isAccidentalCell(stringIndex: Int, fret: Int) -> Bool {
        labelForCell(stringIndex: stringIndex, fret: fret).contains("#")
    }

    public func prepareAudio() {
        tonePlayer.prepare()
    }

    public func playCell(stringIndex: Int, fret: Int) {
        activeCell = ActiveCell(stringIndex: stringIndex, fret: fret)
        clearActiveCellTask?.cancel()
        clearActiveCellTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled else { return }
            self?.activeCell = nil
        }
        let midi = FretboardMath.midiAtFret(stringIndex: stringIndex, fret: fret, capo: capo)
        tonePlayer.playMidi(midi)
    }
}

