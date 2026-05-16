import Foundation

public struct ChordFingeringResolution: Equatable {
    public let requestedSymbol: String
    public let resolvedSymbol: String
    public let frets: [Int]
    public let isFallback: Bool
    public let bassHint: String?

    public init(
        requestedSymbol: String,
        resolvedSymbol: String,
        frets: [Int],
        isFallback: Bool,
        bassHint: String?
    ) {
        self.requestedSymbol = requestedSymbol
        self.resolvedSymbol = resolvedSymbol
        self.frets = frets
        self.isFallback = isFallback
        self.bassHint = bassHint
    }
}

public enum ChordFingeringProvider {
    public static func resolve(symbol: String) -> ChordFingeringResolution? {
        let normalized = normalize(symbol)
        guard !normalized.isEmpty else { return nil }

        // 1) 优先精确命中（含 slash 精确按法）
        if let payload = OfflineChordBuilder.buildPayload(displaySymbol: normalized),
           let voicing = payload.voicings.first {
            return ChordFingeringResolution(
                requestedSymbol: normalized,
                resolvedSymbol: normalized,
                frets: voicing.explain.frets,
                isFallback: false,
                bassHint: nil
            )
        }

        // 2) slash 回退主和弦
        if let slashIndex = normalized.firstIndex(of: "/") {
            let root = String(normalized[..<slashIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let bass = String(normalized[normalized.index(after: slashIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !root.isEmpty,
               let payload = OfflineChordBuilder.buildPayload(displaySymbol: root),
               let voicing = payload.voicings.first {
                return ChordFingeringResolution(
                    requestedSymbol: normalized,
                    resolvedSymbol: root,
                    frets: voicing.explain.frets,
                    isFallback: true,
                    bassHint: bass.isEmpty ? nil : bass
                )
            }
        }

        return nil
    }

    public static func resolveFrets(symbol: String) -> [Int]? {
        resolve(symbol: symbol)?.frets
    }

    private static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
    }
}
