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

        if let payload = OfflineChordBuilder.buildPayload(displaySymbol: normalized),
           let voicing = payload.voicings.first {
            return ResolvedChordFingering(symbol: normalized, frets: voicing.explain.frets, bassHint: nil)
        }

        // Slash chord fallback: D/F# -> D
        if let slashIndex = normalized.firstIndex(of: "/") {
            let root = String(normalized[..<slashIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let bass = String(normalized[normalized.index(after: slashIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !root.isEmpty,
               let payload = OfflineChordBuilder.buildPayload(displaySymbol: root),
               let voicing = payload.voicings.first {
                return ResolvedChordFingering(symbol: root, frets: voicing.explain.frets, bassHint: bass.isEmpty ? nil : bass)
            }
        }

        #if DEBUG
        print("[ChordFingeringResolver] unresolved chord=\(chord), normalized=\(normalized)")
        #endif
        return nil
    }
}
