import XCTest
import Core
@testable import Ear

private actor MockIntervalEarHistoryStore: IntervalEarHistoryStoring {
    private(set) var attempts: [IntervalEarAttemptRecord] = []
    func appendAttempt(_ record: IntervalEarAttemptRecord) async {
        attempts.append(record)
    }
}

/// 单测里替代真实 `IntervalTonePlayer`，避免 `playPair()` 走 `AudioEngineService.shared`
/// 在模拟器/本机扬声器播出吉他两音（开发者会误以为 App 前台「莫名」发声）。
private final class SilentIntervalTonePlayerForTests: IntervalTonePlaying {
    func playAscendingPair(lowMidi: Int, highMidi: Int) async throws {}
    func playSinglePreview(midi: Int) async throws {}
}

/// 可复现的 64-bit LCG，仅单测使用。
private struct TestLCG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class EarCoreTests: XCTestCase {
    func testIntervalGeneratorBuildsFourChoicesAndAscendingPair() {
        var rng = SystemRandomNumberGenerator()
        let q = IntervalQuestionGenerator.next(difficulty: .高级, using: &rng)
        XCTAssertEqual(q.choices.count, 4)
        XCTAssertEqual(q.difficulty, .高级)
        XCTAssertGreaterThanOrEqual(q.highMidi, q.lowMidi)
        XCTAssertEqual(q.highMidi - q.lowMidi, q.answer.semitones)
        XCTAssertTrue(q.choices.contains(where: { $0.semitones == q.answer.semitones }))
    }

    func testChromaticStripCoversOctaveAndBothNotes() {
        let strip = IntervalChromaticStrip.midisCoveringOctaveIncluding(lowMidi: 64, highMidi: 67)
        XCTAssertTrue(strip.contains(64))
        XCTAssertTrue(strip.contains(67))
        XCTAssertGreaterThanOrEqual(strip.last! - strip.first!, 12)
        XCTAssertEqual(strip, Array(strip.first! ... strip.last!))
    }

    func testChromaticStripUnisonExpandsToOctave() {
        let strip = IntervalChromaticStrip.midisCoveringOctaveIncluding(lowMidi: 60, highMidi: 60)
        XCTAssertTrue(strip.contains(60))
        XCTAssertGreaterThanOrEqual(strip.last! - strip.first!, 12)
    }

    func testChromaticStripWideIntervalKeepsEndpoints() {
        let strip = IntervalChromaticStrip.midisCoveringOctaveIncluding(lowMidi: 48, highMidi: 84)
        XCTAssertTrue(strip.contains(48))
        XCTAssertTrue(strip.contains(84))
        XCTAssertGreaterThanOrEqual(strip.last! - strip.first!, 12)
    }

    func testIntervalBeginnerPresetExcludesTritone() {
        let p = IntervalQuestionGenerator.preset(for: .初级)
        XCTAssertFalse(p.poolSemitones.contains(6))
    }

    func testIntervalIntermediatePresetExcludesTritone() {
        let p = IntervalQuestionGenerator.preset(for: .中级)
        XCTAssertFalse(p.poolSemitones.contains(6))
    }

    func testChordMcqBeginnerAnswersAreMajorOrMinorOnly() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0 ..< 24 {
            let q = EarChordMcqGenerator.makeQuestion(difficulty: .初级, using: &rng)
            XCTAssertEqual(q.questionType, "single_chord_quality")
            XCTAssertEqual(q.options.count, 4)
            let keys = Set(q.options.map(\.key))
            XCTAssertEqual(keys.count, 4)
            guard let qual = EarChordQuality(targetQualityToken: q.targetQuality ?? "") else {
                XCTFail("unknown target_quality \(q.targetQuality ?? "")")
                continue
            }
            XCTAssertTrue([.major, .minor].contains(qual), "unexpected answer \(qual)")
        }
    }

    func testChordMcqAdvancedUsesFiveQualitiesInPool() {
        let p = EarChordMcqGenerator.preset(for: .高级)
        XCTAssertEqual(p.optionQualities.count, 5)
    }

    func testChordMcqQuestionIncludesSixStringPlaybackFrets() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0 ..< 16 {
            let q = EarChordMcqGenerator.makeQuestion(difficulty: .高级, using: &rng)
            XCTAssertEqual(
                q.playbackFretsSixToOne?.count,
                6,
                "expected OfflineChordBuilder voicing for \(q.root ?? "") \(q.targetQuality ?? "")"
            )
        }
    }

    func testProgressionLetterMarkInCMajor() {
        let item = EarBankItem(
            id: "t",
            mode: "B",
            questionType: "progression_recognition",
            promptZh: "听和弦进行",
            options: [
                EarMcqOption(key: "A", label: "I-V-vi-IV"),
                EarMcqOption(key: "B", label: "ii-V-I"),
            ],
            correctOptionKey: "A",
            root: nil,
            targetQuality: nil,
            musicKey: "C",
            progressionRoman: "I-V-vi-IV",
            hintZh: nil
        )
        XCTAssertEqual(EarProgressionPlayback.progressionMarkText(for: item), "C → G → Am → F")
        XCTAssertEqual(EarPlaybackMidi.letterChordSymbols(key: "C", progressionRoman: "I-V-vi-IV"), ["C", "G", "Am", "F"])
    }

    func testIntervalAdvancedPresetIncludesTritone() {
        let p = IntervalQuestionGenerator.preset(for: .高级)
        XCTAssertTrue(p.poolSemitones.contains(6))
    }

    func testSightSingingScoreReturnsZeroWhenNoSamples() {
        let score = computeSightSingingScore(absCentsSamples: [], sampleStepMs: 120)
        XCTAssertEqual(score.score, 0, accuracy: 0.001)
        XCTAssertFalse(score.isCorrect)
    }

    func testEarSeedDecodingBankA() throws {
        let json = """
        {
          "banks": {
            "A": [{
              "id":"a1",
              "mode":"A",
              "question_type":"single_chord_quality",
              "prompt_zh":"测试",
              "options":[{"key":"maj","label":"大三和弦"},{"key":"min","label":"小三和弦"}],
              "correct_option_key":"maj",
              "root":"C",
              "target_quality":"major"
            }],
            "B": []
          }
        }
        """.data(using: .utf8)!
        let doc = try JSONDecoder().decode(EarSeedDocument.self, from: json)
        XCTAssertEqual(doc.bankA.count, 1)
        XCTAssertEqual(doc.bankA.first?.id, "a1")
    }

    @MainActor
    func testIntervalEarSubmitAppendsHistoryRecord() async throws {
        let mock = MockIntervalEarHistoryStore()
        let vm = IntervalEarSessionViewModel(
            maxQuestions: 3,
            difficulty: .初级,
            player: SilentIntervalTonePlayerForTests(),
            historyStore: mock
        )
        guard let q = vm.question else {
            XCTFail("missing question")
            return
        }
        await vm.playPair()
        let wrongIdx = q.choices.firstIndex { $0.semitones != q.answer.semitones } ?? 0
        vm.selectChoice(wrongIdx)
        try await Task.sleep(nanoseconds: 400_000_000)
        let got = await mock.attempts
        XCTAssertEqual(got.count, 1)
        XCTAssertFalse(got[0].wasCorrect)
        XCTAssertEqual(got[0].pageIndex, 0)
        XCTAssertEqual(got[0].choiceLabelsZh.count, 4)
        XCTAssertEqual(got[0].selectedIndex, wrongIdx)
    }

    func testIntervalEarFileHistoryStoreRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("interval_test.json")
        let store = IntervalEarFileHistoryStore(fileURL: url, maxRecords: 100)
        let r = IntervalEarAttemptRecord(
            difficultyRaw: "初级",
            lowMidi: 60,
            highMidi: 64,
            answerSemitones: 4,
            answerNameZh: "大三度",
            selectedIndex: 0,
            selectedSemitones: 4,
            selectedNameZh: "大三度",
            wasCorrect: true,
            choiceSemitones: [4, 5, 3, 7],
            choiceLabelsZh: ["大三度", "纯四度", "小三度", "纯五度"],
            pageIndex: 0
        )
        await store.appendAttempt(r)
        let all = await store.loadAllAttempts()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].lowMidi, 60)
        try FileManager.default.removeItem(at: dir)
    }

    func testRomanNumeralSegmentCountTrimsAndIgnoresEmpty() {
        XCTAssertEqual(EarPlaybackMidi.romanNumeralSegmentCount(" I - IV - V "), 3)
        XCTAssertEqual(EarPlaybackMidi.romanNumeralSegmentCount(""), 0)
    }

    func testProgressionProceduralOptionsSameSegmentCountAsAnswer() {
        for difficulty in EarProgressionMcqDifficulty.allCases {
            var rng = SystemRandomNumberGenerator()
            for _ in 0 ..< 80 {
                let q = EarProgressionProceduralGenerator.makeQuestion(difficulty: difficulty, using: &rng)
                guard let roman = q.progressionRoman else {
                    XCTFail("missing progression_roman")
                    continue
                }
                let n = EarPlaybackMidi.romanNumeralSegmentCount(roman)
                XCTAssertEqual(q.options.count, 4)
                let keys = Set(q.options.map(\.key))
                XCTAssertEqual(keys.count, 4)
                let labels = Set(q.options.map(\.label))
                XCTAssertEqual(labels.count, 4, "duplicate option label")
                for opt in q.options {
                    XCTAssertEqual(EarPlaybackMidi.romanNumeralSegmentCount(opt.label), n, opt.label)
                }
                let correctLabel = q.options.first { $0.key == q.correctOptionKey }?.label
                XCTAssertEqual(correctLabel, roman)
                XCTAssertNotNil(EarProgressionPlayback.playbackFretsSequence(for: q))
            }
        }
    }

    func testProgressionProceduralGoldenSeed() {
        var rng = TestLCG(seed: 42)
        let q = EarProgressionProceduralGenerator.makeQuestion(difficulty: .中级, using: &rng)
        XCTAssertEqual(q.questionType, "progression_recognition")
        XCTAssertEqual(q.mode, "B")
        XCTAssertNotNil(q.musicKey)
        XCTAssertNotNil(q.progressionRoman)
        XCTAssertEqual(EarPlaybackMidi.romanNumeralSegmentCount(q.progressionRoman!), 4)
    }

    func testProgressionWeightedGeneratorCadenceAndPenultimate() {
        for difficulty in EarProgressionMcqDifficulty.allCases {
            let n: Int = switch difficulty {
            case .初级: 3
            case .中级: 4
            case .高级: 5
            }
            var rng = SystemRandomNumberGenerator()
            for _ in 0 ..< 20 {
                let line = EarProgressionHarmonyEngine.generateProgressionRoman(
                    difficulty: difficulty,
                    length: n,
                    using: &rng
                )
                let parts = line.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }
                XCTAssertEqual(parts.count, n, line)
                XCTAssertEqual(parts.last, "I", "句尾应高概率落在 I：\(line)")
                let pen = parts[parts.count - 2]
                let penOk =
                    pen == "V" || pen == "V7" || pen.hasPrefix("(V/")
                    || (pen == "IV" && parts.last == "I")
                XCTAssertTrue(
                    penOk,
                    "倒数第二宜为属功能或 Plagal（IV→I）：\(line)"
                )
                if difficulty == .初级 {
                    for p in parts {
                        XCTAssertFalse(p.contains("7"), "初级不含七和弦 extension：\(line)")
                        XCTAssertFalse(p.hasPrefix("(V/"), "初级不含次属：\(line)")
                    }
                }
            }
        }
    }

    func testProgressionDebugModeEmitsStepLines() {
        var lines: [String] = []
        EarProgressionHarmonyEngine.debugMode = .linesOnly { lines.append($0) }
        defer { EarProgressionHarmonyEngine.debugMode = .off }
        var rng = TestLCG(seed: 7)
        _ = EarProgressionHarmonyEngine.generateProgressionRoman(difficulty: .中级, length: 4, using: &rng)
        XCTAssertFalse(lines.isEmpty)
        XCTAssertTrue(lines.contains { $0.contains("picked=") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("→ line:") })
    }

    func testPlaybackMidiV7AndSecondaryDominantSymbols() {
        XCTAssertEqual(
            EarPlaybackMidi.letterChordSymbols(key: "C", progressionRoman: "I-V7-I"),
            ["C", "G7", "C"]
        )
        XCTAssertEqual(
            EarPlaybackMidi.letterChordSymbols(key: "C", progressionRoman: "ii-(V/ii)-ii"),
            ["Dm", "A7", "Dm"]
        )
    }

    func testSightSingingIntervalQuestionsAreAscendingPairs() async throws {
        let repo = LocalSightSingingRepository()
        let start = try await repo.startSession(
            pitchRange: "mid",
            includeAccidental: false,
            questionCount: 12,
            exerciseKind: .intervalMimic
        )

        func midi12(_ name: String) -> Int {
            let upper = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let regex = try! NSRegularExpression(pattern: "^([A-G])(#?)(\\d)$")
            let range = NSRange(location: 0, length: upper.utf16.count)
            let m = regex.firstMatch(in: upper, range: range)!
            let r1 = Range(m.range(at: 1), in: upper)!
            let r2 = Range(m.range(at: 2), in: upper)!
            let r3 = Range(m.range(at: 3), in: upper)!
            let noteName = String(upper[r1]) + String(upper[r2])
            let octave = Int(upper[r3])!
            let idx = PitchMath.noteNames.firstIndex(of: noteName)!
            return (octave + 1) * 12 + idx
        }

        var q: SightSingingQuestion? = start.question
        var seen = 0
        while let current = q {
            XCTAssertEqual(current.targetNotes.count, 2)
            XCTAssertFalse(current.targetNotes[0].contains("#"))
            XCTAssertFalse(current.targetNotes[1].contains("#"))
            let low = midi12(current.targetNotes[0])
            let high = midi12(current.targetNotes[1])
            XCTAssertLessThan(low, high)

            seen += 1
            q = try await repo.nextQuestion(sessionId: start.sessionId)
        }
        XCTAssertEqual(seen, 12)
    }

    func testSightSingingMixedModeQuestionsAreSingleOrInterval() async throws {
        let repo = LocalSightSingingRepository()
        let start = try await repo.startSession(
            pitchRange: "mid",
            includeAccidental: false,
            questionCount: 0,
            exerciseKind: .mixedRandomMimic
        )
        var q: SightSingingQuestion? = start.question
        var seen = 0
        while seen < 24 {
            guard let current = q else {
                XCTFail("expected question")
                return
            }
            XCTAssertTrue(current.targetNotes.count == 1 || current.targetNotes.count == 2)
            if current.targetNotes.count == 2 {
                let low = noteNameToMidiForTest(current.targetNotes[0])
                let high = noteNameToMidiForTest(current.targetNotes[1])
                XCTAssertLessThan(low, high)
            }
            seen += 1
            q = try await repo.nextQuestion(sessionId: start.sessionId)
        }
        XCTAssertEqual(seen, 24)
    }

    func testSightSingingUpdateGenerationParametersAffectsNextQuestion() async throws {
        let repo = LocalSightSingingRepository()
        let start = try await repo.startSession(
            pitchRange: "mid",
            includeAccidental: false,
            questionCount: 0,
            exerciseKind: .intervalMimic
        )
        XCTAssertEqual(start.question?.targetNotes.count, 2)

        try await repo.updateSessionGenerationParameters(
            sessionId: start.sessionId,
            pitchRange: "mid",
            includeAccidental: false,
            questionCount: 0,
            exerciseKind: .singleNoteMimic
        )

        let next = try await repo.nextQuestion(sessionId: start.sessionId)
        XCTAssertEqual(next?.targetNotes.count, 1)
    }

    private func noteNameToMidiForTest(_ note: String) -> Int {
        let upper = note.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let regex = try! NSRegularExpression(pattern: "^([A-G])(#?)(\\d)$")
        let range = NSRange(location: 0, length: upper.utf16.count)
        let m = regex.firstMatch(in: upper, range: range)!
        let r1 = Range(m.range(at: 1), in: upper)!
        let r2 = Range(m.range(at: 2), in: upper)!
        let r3 = Range(m.range(at: 3), in: upper)!
        let noteName = String(upper[r1]) + String(upper[r2])
        let octave = Int(upper[r3])!
        let idx = PitchMath.noteNames.firstIndex(of: noteName)!
        return (octave + 1) * 12 + idx
    }
}
