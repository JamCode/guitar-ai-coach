import XCTest
@testable import Ear

private actor MockIntervalEarHistoryStore: IntervalEarHistoryStoring {
    private(set) var attempts: [IntervalEarAttemptRecord] = []
    func appendAttempt(_ record: IntervalEarAttemptRecord) async {
        attempts.append(record)
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

    func testIntervalEarSubmitAppendsHistoryRecord() async throws {
        let mock = MockIntervalEarHistoryStore()
        let wrongIdx: Int = await MainActor.run {
            let vm = IntervalEarSessionViewModel(maxQuestions: 3, difficulty: .初级, historyStore: mock)
            guard let q = vm.question else {
                XCTFail("missing question")
                return 0
            }
            let idx = q.choices.firstIndex { $0.semitones != q.answer.semitones } ?? 0
            vm.selectChoice(idx)
            return idx
        }
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
}
