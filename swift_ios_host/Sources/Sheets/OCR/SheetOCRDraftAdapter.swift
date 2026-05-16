import Foundation

struct SheetOCRDraftAdapter {
    func makeParsedData(
        from draft: SheetOCRDraft,
        sheetId: String,
        status: SheetParseStatus = .draft
    ) -> SheetParsedData {
        let segments = draft.allSystems.compactMap { system -> SheetSegment? in
            let chords = system.chords.map(\.text).filter { !$0.isEmpty }
            let lyrics = system.lyrics.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chords.isEmpty || !lyrics.isEmpty else { return nil }
            return SheetSegment(chords: chords, melody: "", lyrics: lyrics)
        }
        return SheetParsedData(
            sheetId: sheetId,
            parseStatus: status,
            originalKey: draft.originalKey?.text ?? "C",
            segments: segments,
            updatedAtMs: Int(Date().timeIntervalSince1970 * 1000)
        )
    }
}
