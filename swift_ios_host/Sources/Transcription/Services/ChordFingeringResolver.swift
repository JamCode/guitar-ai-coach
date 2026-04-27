import Foundation
import Chords

struct ResolvedChordFingering: Equatable {
    let symbol: String
    let frets: [Int]
    let bassHint: String?
}

enum ChordFingeringResolver {
    static func normalizeChordName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
    }

    static func isInvalidChordName(_ raw: String) -> Bool {
        let normalized = normalizeChordName(raw).lowercased()
        return normalized.isEmpty
            || normalized == "-"
            || normalized == "—"
            || normalized == "n"
            || normalized == "nc"
            || normalized == "no chord"
            || normalized == "unknown"
    }

    static func resolve(_ chord: String) -> ResolvedChordFingering? {
        let normalized = normalizeChordName(chord)
        guard !isInvalidChordName(normalized) else { return nil }
        if let resolved = ChordFingeringProvider.resolve(symbol: normalized) {
            return ResolvedChordFingering(
                symbol: resolved.resolvedSymbol,
                frets: resolved.frets,
                bassHint: resolved.bassHint
            )
        }

        #if DEBUG
        print("[ChordFingeringResolver] unresolved chord=\(chord), normalized=\(normalized)")
        #endif
        return nil
    }
}
