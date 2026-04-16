import XCTest
@testable import Ear

final class EarCoreTests: XCTestCase {
    func testIntervalGeneratorBuildsFourChoicesAndAscendingPair() {
        var rng = SystemRandomNumberGenerator()
        let q = IntervalQuestionGenerator.next(using: &rng)
        XCTAssertEqual(q.choices.count, 4)
        XCTAssertGreaterThan(q.highMidi, q.lowMidi)
        XCTAssertTrue(q.choices.contains(where: { $0.semitones == q.answer.semitones }))
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
