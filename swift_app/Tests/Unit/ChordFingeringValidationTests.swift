import XCTest
import Chords
import ChordChart

final class ChordFingeringValidationTests: XCTestCase {
    // E A D G B E, 6->1 string pitch classes
    private let standardTuningPC = [4, 9, 2, 7, 11, 4]

    func testCriticalChordSet_NoErrorAndReportWarnings() {
        let criticalSymbols = [
            "C", "D", "E", "F", "G", "A", "B",
            "Am", "Bm", "Cm", "Dm", "Em", "Fm", "Gm",
            "C7", "D7", "E7", "G7", "A7", "B7",
            "Cmaj7", "Dmaj7", "Emaj7", "Gmaj7", "Amaj7",
            "Am7", "Bm7", "Dm7", "Em7",
            "Fmaj7", "Cadd9", "G/B", "D/F#", "Asus2", "Asus4", "Dsus2", "Dsus4", "Esus4",
            "C/E", "A/C#", "E/G#", "F/A", "C/G", "D/A"
        ]

        let results = criticalSymbols.compactMap { symbol -> ValidationResult? in
            guard let payload = OfflineChordBuilder.buildPayload(displaySymbol: symbol),
                  let first = payload.voicings.first else {
                return ValidationResult(
                    chordName: symbol,
                    shape: [],
                    actualNotes: [],
                    theoreticalNotes: [],
                    level: .error,
                    issues: ["missing_voicing"],
                    suggestion: "补充该和弦的离线指法。"
                )
            }
            return validate(chordName: symbol, frets: first.explain.frets, baseFret: first.explain.baseFret)
        }

        let errors = results.filter { $0.level == .error }
        let warnings = results.filter { $0.level == .warning }
        printReport(title: "Critical chord set", errors: errors, warnings: warnings)

        XCTAssertTrue(
            errors.isEmpty,
            "critical chord set has \(errors.count) error(s):\n\(format(results: errors))"
        )
    }

    func testChordChartEntries_NoErrorWarningsListed() {
        let allEntries = ChordChartData.sections.flatMap(\.entries)
        var results: [ValidationResult] = []
        for entry in allEntries {
            results.append(validate(chordName: entry.symbol, frets: entry.frets, baseFret: 1))
        }

        let errors = results.filter { $0.level == .error }
        let warnings = results.filter { $0.level == .warning }
        printReport(title: "ChordChartData", errors: errors, warnings: warnings)

        XCTAssertTrue(
            errors.isEmpty,
            "ChordChartData has \(errors.count) error(s):\n\(format(results: errors))"
        )
    }

    // MARK: - Core validation

    private func validate(chordName: String, frets: [Int], baseFret: Int) -> ValidationResult {
        guard let parsed = parseChord(chordName) else {
            return ValidationResult(
                chordName: chordName,
                shape: frets,
                actualNotes: noteNames(pcsFromFrets(frets)),
                theoreticalNotes: [],
                level: .warning,
                issues: ["unsupported_quality"],
                suggestion: "当前规则未覆盖该和弦类型，建议人工复核。"
            )
        }

        let actual = pcsFromFrets(frets)
        let actualSet = Set(actual)
        let required = parsed.requiredPCs
        let requiredSet = Set(required)
        let optionalSet = Set(parsed.optionalPCs)
        let actualNotes = noteNames(actual)
        let expectedNotes = noteNames(required)

        var issues: [String] = []
        var level: ValidationLevel = .ok

        if actualSet.isEmpty {
            issues.append("silent_shape")
            level = .error
        }

        let missingRequired = requiredSet.subtracting(actualSet).subtracting(optionalSet)
        if !missingRequired.isEmpty {
            // 缺三音视为 ERROR，其它缺失先 WARNING
            if missingRequired.contains(parsed.thirdPC) {
                issues.append("missing_third")
                level = .error
            } else {
                issues.append("missing_tone")
                level = max(level, .warning)
            }
        }

        if let forbiddenThird = parsed.forbiddenThirdPC, actualSet.contains(forbiddenThird) {
            issues.append("third_quality_conflict")
            level = .error
        }

        if let slashBass = parsed.slashBassPC, let lowest = actual.first {
            if lowest != slashBass {
                issues.append("slash_bass_mismatch")
                level = .error
            }
        }

        if frets.filter({ $0 >= 0 }).count <= 3 {
            issues.append("thin_voicing")
            level = max(level, .warning)
        }

        let suggestion: String
        if level == .error {
            if issues.contains("slash_bass_mismatch") {
                suggestion = "补充精确 slash 指法，确保最低发声音等于 slash 低音。"
            } else if issues.contains("missing_third") || issues.contains("third_quality_conflict") {
                suggestion = "修正三音（大/小三）以匹配和弦性质。"
            } else {
                suggestion = "修正指法音组成，确保覆盖必要构成音。"
            }
        } else if level == .warning {
            suggestion = "可用但建议人工复核是否为目标场景推荐按法。"
        } else {
            suggestion = "无需修复。"
        }

        return ValidationResult(
            chordName: chordName,
            shape: frets,
            actualNotes: actualNotes,
            theoreticalNotes: expectedNotes,
            level: level,
            issues: issues,
            suggestion: suggestion
        )
    }

    private func pcsFromFrets(_ frets: [Int]) -> [Int] {
        // 6->1
        let normalized = frets.count == 6 ? frets : Array(repeating: -1, count: 6 - frets.count) + frets
        var pcs: [Int] = []
        for (idx, fret) in normalized.enumerated() where fret >= 0 {
            pcs.append((standardTuningPC[idx] + fret) % 12)
        }
        return pcs
    }

    private func parseChord(_ symbol: String) -> ParsedChord? {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
        guard !normalized.isEmpty else { return nil }

        let slashParts = normalized.split(separator: "/", maxSplits: 1).map(String.init)
        let main = slashParts[0]
        let slash = slashParts.count > 1 ? slashParts[1] : nil
        let roots = ["C#", "Db", "D#", "Eb", "F#", "Gb", "G#", "Ab", "A#", "Bb", "C", "D", "E", "F", "G", "A", "B"]
        guard let root = roots.first(where: { main.hasPrefix($0) }),
              let rootPC = pc(of: root) else { return nil }
        let quality = String(main.dropFirst(root.count))

        let intervals: [Int]
        let third: Int
        let forbiddenThird: Int?
        switch quality {
        case "":
            intervals = [0, 4, 7]
            third = 4
            forbiddenThird = 3
        case "m":
            intervals = [0, 3, 7]
            third = 3
            forbiddenThird = 4
        case "dim":
            intervals = [0, 3, 6]
            third = 3
            forbiddenThird = 4
        case "dim7":
            intervals = [0, 3, 6, 9]
            third = 3
            forbiddenThird = 4
        case "aug":
            intervals = [0, 4, 8]
            third = 4
            forbiddenThird = 3
        case "sus2":
            intervals = [0, 2, 7]
            third = 2
            forbiddenThird = 3 // both m3/M3 should be absent;先抓明显冲突
        case "sus4":
            intervals = [0, 5, 7]
            third = 5
            forbiddenThird = 4
        case "7":
            intervals = [0, 4, 7, 10]
            third = 4
            forbiddenThird = 3
        case "maj7":
            intervals = [0, 4, 7, 11]
            third = 4
            forbiddenThird = 3
        case "m7":
            intervals = [0, 3, 7, 10]
            third = 3
            forbiddenThird = 4
        case "m7b5":
            intervals = [0, 3, 6, 10]
            third = 3
            forbiddenThird = 4
        case "add9":
            intervals = [0, 4, 7, 2]
            third = 4
            forbiddenThird = 3
        case "6", "add6":
            intervals = [0, 4, 7, 9]
            third = 4
            forbiddenThird = 3
        case "m6":
            intervals = [0, 3, 7, 9]
            third = 3
            forbiddenThird = 4
        case "9":
            intervals = [0, 4, 7, 10, 2]
            third = 4
            forbiddenThird = 3
        case "m9":
            intervals = [0, 3, 7, 10, 2]
            third = 3
            forbiddenThird = 4
        case "maj9":
            intervals = [0, 4, 7, 11, 2]
            third = 4
            forbiddenThird = 3
        case "11":
            // Guitar 11 voicings commonly omit the third/fifth/ninth and keep b7 + 11.
            intervals = [0, 10, 5]
            third = 5
            forbiddenThird = nil
        case "13":
            // Compact dominant 13 grips normally require root/3/b7/13 and omit 5/9/11.
            intervals = [0, 4, 10, 9]
            third = 4
            forbiddenThird = 3
        case "7b9":
            intervals = [0, 4, 7, 10, 1]
            third = 4
            forbiddenThird = 3
        case "7#9":
            intervals = [0, 4, 7, 10, 3]
            third = 4
            forbiddenThird = nil
        case "7#11":
            intervals = [0, 4, 7, 10, 6]
            third = 4
            forbiddenThird = 3
        case "7b5":
            intervals = [0, 4, 6, 10]
            third = 4
            forbiddenThird = 3
        default:
            return nil
        }

        let required = intervals.map { (rootPC + $0) % 12 }
        let optionalFifthQualities: Set<String> = [
            "6", "add6", "7", "maj7", "m7", "9", "m9", "maj9", "7b9", "7#9", "7#11"
        ]
        let optionalPCs = optionalFifthQualities.contains(quality) ? [(rootPC + 7) % 12] : []
        let slashBassPC = slash.flatMap(pc(of:))
        return ParsedChord(
            requiredPCs: required,
            optionalPCs: optionalPCs,
            thirdPC: (rootPC + third) % 12,
            forbiddenThirdPC: forbiddenThird.map { (rootPC + $0) % 12 },
            slashBassPC: slashBassPC
        )
    }

    private func pc(of note: String) -> Int? {
        switch note {
        case "C": return 0
        case "C#", "Db": return 1
        case "D": return 2
        case "D#", "Eb": return 3
        case "E": return 4
        case "F": return 5
        case "F#", "Gb": return 6
        case "G": return 7
        case "G#", "Ab": return 8
        case "A": return 9
        case "A#", "Bb": return 10
        case "B": return 11
        default: return nil
        }
    }

    private func noteNames(_ pcs: [Int]) -> [String] {
        let names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        return pcs.map { names[$0 % 12] }
    }

    // MARK: - Reporting

    private func printReport(title: String, errors: [ValidationResult], warnings: [ValidationResult]) {
        print("=== \(title) validation report ===")
        print("ERROR: \(errors.count), WARNING: \(warnings.count)")
        if !errors.isEmpty {
            print("-- Errors --")
            print(format(results: errors))
        }
        if !warnings.isEmpty {
            print("-- Warnings --")
            print(format(results: warnings))
        }
    }

    private func format(results: [ValidationResult]) -> String {
        results.map {
            "\($0.level.rawValue) | \($0.chordName) | shape=\($0.shapeText) | actual=\($0.actualNotes.joined(separator: ",")) | expected=\($0.theoreticalNotes.joined(separator: ",")) | issues=\($0.issues.joined(separator: ",")) | suggestion=\($0.suggestion)"
        }.joined(separator: "\n")
    }
}

private struct ParsedChord {
    let requiredPCs: [Int]
    let optionalPCs: [Int]
    let thirdPC: Int
    let forbiddenThirdPC: Int?
    let slashBassPC: Int?
}

private struct ValidationResult {
    let chordName: String
    let shape: [Int]
    let actualNotes: [String]
    let theoreticalNotes: [String]
    let level: ValidationLevel
    let issues: [String]
    let suggestion: String

    var shapeText: String {
        shape.map { $0 < 0 ? "x" : String($0) }.joined(separator: " ")
    }
}

private enum ValidationLevel: String, Comparable {
    case ok = "OK"
    case warning = "WARNING"
    case error = "ERROR"

    static func < (lhs: ValidationLevel, rhs: ValidationLevel) -> Bool {
        rank(lhs) < rank(rhs)
    }

    private static func rank(_ value: ValidationLevel) -> Int {
        switch value {
        case .ok: return 0
        case .warning: return 1
        case .error: return 2
        }
    }
}
