import XCTest
@testable import Ear

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
}
