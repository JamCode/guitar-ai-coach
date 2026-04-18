import Foundation
import Chords

struct ResolvedChordFingering: Equatable {
    let symbol: String
    let frets: [Int]
}

enum ChordFingeringResolver {
    static func resolve(_ chord: String) -> ResolvedChordFingering? {
        guard let payload = OfflineChordBuilder.buildPayload(displaySymbol: chord),
              let voicing = payload.voicings.first else {
            return nil
        }
        return ResolvedChordFingering(symbol: chord, frets: voicing.explain.frets)
    }
}
