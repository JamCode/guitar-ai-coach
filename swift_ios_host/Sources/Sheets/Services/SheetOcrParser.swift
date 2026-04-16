import Foundation

struct OcrLineCandidate: Equatable {
    let text: String
    let centerY: Double
}

enum SheetOcrParser {
    private static let chordToken = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "^[A-G](?:#|b)?(?:m|maj|min|sus|dim|aug|add)?\\d*(?:/[A-G](?:#|b)?)?$",
        options: []
    )
    private static let melodyChars = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "^[0-7\\-\\.\\|\\(\\)\\s]+$",
        options: []
    )
    private static let containsCjk = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "[\\u4e00-\\u9fff]",
        options: []
    )

    static func parseCandidates(_ lines: [OcrLineCandidate]) -> [SheetSegment] {
        if lines.isEmpty { return [] }
        let sorted = lines.sorted { $0.centerY < $1.centerY }
        var chordLines: [String] = []
        var melodyLines: [String] = []
        var lyricLines: [String] = []

        for line in sorted {
            let text = normalize(line.text)
            if text.isEmpty { continue }
            if isChordLine(text) {
                chordLines.append(text)
                continue
            }
            if isMelodyLine(text) {
                melodyLines.append(text)
                continue
            }
            if matchExists(containsCjk, in: text) {
                lyricLines.append(text)
            }
        }

        let size = max(chordLines.count, max(melodyLines.count, lyricLines.count))
        if size == 0 { return [] }

        var out: [SheetSegment] = []
        for i in 0..<size {
            let line = i < chordLines.count ? chordLines[i] : ""
            out.append(
                SheetSegment(
                    chords: line.isEmpty ? [] : splitChordLine(line),
                    melody: i < melodyLines.count ? melodyLines[i] : "",
                    lyrics: i < lyricLines.count ? lyricLines[i] : ""
                )
            )
        }
        return out
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "｜", with: "|")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isChordLine(_ text: String) -> Bool {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        if tokens.isEmpty { return false }
        var chordCount = 0
        for token in tokens where matchExists(chordToken, in: token) {
            chordCount += 1
        }
        return chordCount >= 2 && chordCount * 2 >= tokens.count
    }

    private static func isMelodyLine(_ text: String) -> Bool {
        guard matchExists(melodyChars, in: text) else { return false }
        let digitCount = text.filter(\.isNumber).count
        return digitCount >= 4
    }

    private static func splitChordLine(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { matchExists(chordToken, in: $0) }
    }

    private static func matchExists(_ regex: NSRegularExpression, in text: String) -> Bool {
        regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }
}
