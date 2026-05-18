import Foundation

struct SheetOCRParser {
    private let chordRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9#b♯♭/])([A-G](?:#|b|♯|♭)?(?:maj7?|M7|m(?:aj7|7|9|11|13)?|7|9|11|13|6|4|2|5|sus2|sus4|add(?:9|11)|dim|aug|°|ø|Ø|\+|m)?(?:(?:/|on)(?=[A-G])(?:[A-G](?:#|b|♯|♭)?))?)"#
    )
    private let keyRegex = try! NSRegularExpression(pattern: #"1\s*=\s*([A-G](?:#|b|♯|♭)?)"#)
    func parsePageMeta(_ observations: [SheetOCRTextObservation]) -> (title: SheetOCRToken?, key: SheetOCRToken?) {
        let sorted = observations.sortedForReading()

        let title = sorted.first { observation in
            observation.rect.midY < 0.22
                && cjkRatio(observation.text) >= 0.5
                && observation.text.count <= 16
                && keyRegex.firstMatch(in: observation.text, range: observation.fullNSRange) == nil
        }.map {
            SheetOCRToken(kind: .title, text: $0.text, confidence: $0.confidence, rect: $0.rect)
        }

        return (title, nil)
    }

    func parseSystem(
        pageIndex: Int,
        systemIndex: Int,
        system: SheetOCRStaffSystem,
        observations: [SheetOCRTextObservation]
    ) -> SheetOCRSystemDraft {
        let relevant = observations
            .filter { system.bounds.expanded(dx: 0, dy: 0.01).contains(midpointOf: $0.rect) }
            .sortedForReading()
        var chords: [SheetOCRToken] = []
        var lyricOCRTokens: [SheetOCRToken] = []
        var fallbackLyricTokens: [SheetOCRToken] = []

        for observation in relevant {
            let trimmed = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if isMetadata(trimmed) {
                continue
            }
            let inChordBand = observation.isChordOCR
                || (observation.source == .fullPage && system.chordZone.expanded(dx: 0, dy: 0.005).contains(midpointOf: observation.rect))
            let inLyricBand = observation.isLyricOCR
                || (observation.source == .fullPage && system.lyricZone.expanded(dx: 0, dy: 0.01).contains(midpointOf: observation.rect))

            if inChordBand {
                chords.append(contentsOf: chordTokens(in: observation))
                continue
            }
            if inLyricBand {
                if let lyric = lyricText(from: trimmed), !isMetadata(lyric) {
                    let token = SheetOCRToken(kind: .lyric, text: lyric, confidence: observation.confidence, rect: observation.rect, originalText: trimmed)
                    if observation.isLyricOCR {
                        lyricOCRTokens.append(token)
                    } else {
                        fallbackLyricTokens.append(token)
                    }
                }
                continue
            }
        }

        let lyrics = lyricOCRTokens.isEmpty ? fallbackLyricTokens : lyricOCRTokens
        return SheetOCRSystemDraft(
            pageIndex: pageIndex,
            systemIndex: systemIndex,
            bounds: system.bounds,
            staffBounds: system.staffBounds,
            chordZone: system.chordZone,
            lyricZone: system.lyricZone,
            chords: deduplicateChords(chords.sortedByPosition()),
            lyrics: mergeLyricFragments(lyrics.sortedByPosition()),
            melody: [],
            rawObservations: relevant
        )
    }

    func fallbackSystems(
        pageIndex: Int,
        observations: [SheetOCRTextObservation]
    ) -> [SheetOCRSystemDraft] {
        let body = observations.filter { $0.rect.midY > 0.18 }
        let groups = groupLinesByY(body.sortedForReading())
        return groups.enumerated().map { idx, group in
            let minY = group.map(\.rect.minY).min() ?? 0
            let maxY = group.map(\.rect.maxY).max() ?? minY
            let bounds = SheetOCRRect(x: 0, y: max(0, minY - 0.015), width: 1, height: min(1, maxY - minY + 0.03))
            let splitY = bounds.y + bounds.height * 0.42
            let system = SheetOCRStaffSystem(
                bounds: bounds,
                staffBounds: bounds,
                chordZone: SheetOCRRect(x: bounds.x, y: bounds.y, width: bounds.width, height: max(0.01, splitY - bounds.y)),
                lyricZone: SheetOCRRect(x: bounds.x, y: splitY, width: bounds.width, height: max(0.01, bounds.maxY - splitY))
            )
            return parseSystem(pageIndex: pageIndex, systemIndex: idx, system: system, observations: group)
        }
    }

    private func chordTokens(in observation: SheetOCRTextObservation) -> [SheetOCRToken] {
        guard let candidate = bestChordCandidate(in: observation) else { return [] }
        let text = candidate.text
        let matches = chordRegex.matches(in: text, range: text.fullNSRange)
        guard !matches.isEmpty else { return [] }
        return matches.compactMap { match in
            let range = match.range(at: 1)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
            let token = String(text[swiftRange]).normalizedChordText
            guard isAllowedChordToken(token, confidence: min(observation.confidence, candidate.confidence), source: observation.source) else { return nil }
            return SheetOCRToken(
                kind: .chord,
                text: token,
                confidence: min(observation.confidence, candidate.confidence),
                rect: approximateRect(for: range, in: observation),
                originalText: token
            )
        }
    }

    private func bestChordCandidate(in observation: SheetOCRTextObservation) -> SheetOCRTextCandidate? {
        let candidates = observation.candidates.isEmpty
            ? [SheetOCRTextCandidate(text: observation.text, confidence: observation.confidence)]
            : observation.candidates
        return candidates
            .compactMap { candidate -> (candidate: SheetOCRTextCandidate, score: Float)? in
                let matches = chordRegex.matches(in: candidate.text, range: candidate.text.fullNSRange)
                guard !matches.isEmpty else { return nil }
                let chordChars = matches.reduce(0) { $0 + $1.range(at: 1).length }
                let visibleChars = candidate.text.filter { !$0.isWhitespace }.count
                let coverage = Float(chordChars) / Float(max(1, visibleChars))
                guard coverage >= 0.45 else { return nil }
                let normalized = candidate.text.normalizedChordText
                let slashBonus: Float = normalized.contains("/") ? 0.025 : 0
                let rootBonus: Float = normalized.first?.isLetter == true ? 0.02 : 0
                return (candidate, candidate.confidence + coverage * 0.10 + slashBonus + rootBonus)
            }
            .max { $0.score < $1.score }?
            .candidate
    }

    private func approximateRect(for nsRange: NSRange, in observation: SheetOCRTextObservation) -> SheetOCRRect {
        let count = max(1, (observation.text as NSString).length)
        let start = Double(nsRange.location) / Double(count)
        let width = Double(nsRange.length) / Double(count)
        return SheetOCRRect(
            x: observation.rect.x + observation.rect.width * start,
            y: observation.rect.y,
            width: max(0.008, observation.rect.width * width),
            height: observation.rect.height
        )
    }

    private func isAllowedChordToken(_ token: String, confidence: Float, source: SheetOCRObservationSource) -> Bool {
        guard !token.isEmpty else { return false }
        let singleRoots = Set(["A", "B", "C", "D", "E", "F", "G"])
        if singleRoots.contains(token) {
            let threshold: Float = source == .chordLabelZone ? 0.70 : 0.88
            return confidence >= threshold
        }
        return true
    }

    private func normalizedLyricText(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: #"[\s　]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cjkRatio(collapsed) >= 0.35 {
            return collapsed.replacingOccurrences(of: " ", with: "")
        }
        return collapsed
    }

    private func lyricText(from text: String) -> String? {
        let normalized = normalizedLyricText(text)
        let cjkCount = normalized.filter { "\u{4e00}" <= $0 && $0 <= "\u{9fff}" }.count
        guard cjkCount >= 2 else { return nil }
        let lyricScalars = normalized.unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
                || CharacterSet.whitespaces.contains(scalar)
        }
        let lyric = String(String.UnicodeScalarView(lyricScalars))
            .replacingOccurrences(of: #"[\s　]+"#, with: "", options: .regularExpression)
        guard lyric.count >= 2 else { return nil }
        return cjkRatio(lyric) >= 0.75 ? lyric : nil
    }

    private func mergeLyricFragments(_ tokens: [SheetOCRToken]) -> [SheetOCRToken] {
        var lines: [[SheetOCRToken]] = []
        for token in tokens {
            if let lastIndex = lines.indices.last,
               let previous = lines[lastIndex].last,
               abs(previous.rect.midY - token.rect.midY) <= 0.018 {
                lines[lastIndex].append(token)
            } else {
                lines.append([token])
            }
        }

        return lines.compactMap { line in
            guard let first = line.first else { return nil }
            let sorted = line.sorted { $0.rect.midX < $1.rect.midX }
            let mergedText = sorted.map(\.text).joined()
            let originalText = sorted.map(\.originalText).joined(separator: " ")
            let rect = sorted.dropFirst().reduce(first.rect) { $0.union($1.rect) }
            let confidence = sorted.map(\.confidence).reduce(0, +) / Float(sorted.count)
            return SheetOCRToken(
                kind: .lyric,
                text: mergedText,
                confidence: confidence,
                rect: rect,
                originalText: originalText
            )
        }
    }

    private func deduplicateChords(_ tokens: [SheetOCRToken]) -> [SheetOCRToken] {
        var output: [SheetOCRToken] = []
        for token in tokens {
            if let duplicateIndex = output.firstIndex(where: { existing in
                (existing.text == token.text || existing.rect.overlaps(token.rect, xTolerance: 0.018, yTolerance: 0.012))
                    && abs(existing.rect.midX - token.rect.midX) <= 0.035
                    && abs(existing.rect.midY - token.rect.midY) <= 0.035
            }) {
                if token.confidence > output[duplicateIndex].confidence {
                    output[duplicateIndex] = token
                }
            } else {
                output.append(token)
            }
        }
        return output.sortedByPosition()
    }

    private func isMetadata(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return keyRegex.firstMatch(in: t, range: t.fullNSRange) != nil
            || t.contains("演唱")
            || t.contains("制谱")
            || t == "TAB"
    }

    private func cjkRatio(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let cjk = text.filter { "\u{4e00}" <= $0 && $0 <= "\u{9fff}" }.count
        return Double(cjk) / Double(text.count)
    }

    private func groupLinesByY(_ observations: [SheetOCRTextObservation]) -> [[SheetOCRTextObservation]] {
        var groups: [[SheetOCRTextObservation]] = []
        for observation in observations {
            if let last = groups.indices.last,
               let previous = groups[last].last,
               abs(previous.rect.midY - observation.rect.midY) <= 0.055 {
                groups[last].append(observation)
            } else {
                groups.append([observation])
            }
        }
        return groups
    }
}

extension String {
    fileprivate var fullNSRange: NSRange {
        NSRange(location: 0, length: (self as NSString).length)
    }

    fileprivate var normalizedChordText: String {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "／", with: "/")
            .replacingOccurrences(of: "on", with: "/", options: .caseInsensitive)
        if normalized.count == 2, normalized.last == "5", let first = normalized.first, "ABCDEFG".contains(first) {
            return String(first)
        }
        return normalized
    }

}

extension Array where Element == SheetOCRToken {
    fileprivate func sortedByPosition() -> [SheetOCRToken] {
        sorted {
            if abs($0.rect.midY - $1.rect.midY) > 0.015 {
                return $0.rect.midY < $1.rect.midY
            }
            return $0.rect.midX < $1.rect.midX
        }
    }
}

extension SheetOCRTextObservation {
    fileprivate var fullNSRange: NSRange {
        NSRange(location: 0, length: (text as NSString).length)
    }

    fileprivate var isChordOCR: Bool {
        source == .chordLabelZone
    }

    fileprivate var isLyricOCR: Bool {
        source == .lyricZone || source == .lyricTextZone
    }
}
