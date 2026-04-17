import XCTest
@testable import Practice

final class TraditionalCrawlTests: XCTestCase {
    func testBeginnerOnlyUsesSixthString() {
        var rng = SystemRandomNumberGenerator()
        let ex = TraditionalCrawlGenerator.buildExercise(difficulty: .初级, capo: 0, using: &rng)
        XCTAssertTrue(ex.steps.allSatisfy { $0.stringIndexFromBass == 0 })
        XCTAssertEqual(ex.steps.count, 12)
    }

    func testIntermediateStepCountAndAscendingOnEachString() {
        var rng = SystemRandomNumberGenerator()
        let ex = TraditionalCrawlGenerator.buildExercise(difficulty: .中级, capo: 0, using: &rng)
        XCTAssertEqual(ex.steps.count, 48)
        for chunk in stride(from: 0, to: ex.steps.count, by: 4) {
            let slice = Array(ex.steps[chunk ..< min(chunk + 4, ex.steps.count)])
            XCTAssertEqual(slice.count, 4)
            let s0 = slice[0].stringIndexFromBass
            XCTAssertTrue(slice.allSatisfy { $0.stringIndexFromBass == s0 })
            let frets = slice.map(\.fret)
            XCTAssertEqual(frets, [frets[0], frets[0] + 1, frets[0] + 2, frets[0] + 3])
            let fingers = slice.map(\.finger)
            XCTAssertEqual(fingers, [1, 2, 3, 4])
        }
    }

    func testAdvancedIncludesDescendingChunks() {
        var rng = SystemRandomNumberGenerator()
        let ex = TraditionalCrawlGenerator.buildExercise(difficulty: .高级, capo: 0, using: &rng)
        XCTAssertEqual(ex.steps.count, 96)
        let firstStringChunk = Array(ex.steps.prefix(4))
        XCTAssertEqual(firstStringChunk.map(\.finger), [1, 2, 3, 4])
        let secondStringChunk = Array(ex.steps.dropFirst(4).prefix(4))
        XCTAssertEqual(secondStringChunk.map(\.finger), [1, 2, 3, 4])
        let firstDescChunk = Array(ex.steps.dropFirst(24).prefix(4))
        XCTAssertEqual(firstDescChunk.map(\.finger), [4, 3, 2, 1])
        XCTAssertEqual(firstDescChunk.map(\.fret), [firstDescChunk[0].fret, firstDescChunk[0].fret - 1, firstDescChunk[0].fret - 2, firstDescChunk[0].fret - 3])
    }

    func testRecommendedReturnsThreeDifficulties() {
        var rng = SystemRandomNumberGenerator()
        let items = TraditionalCrawlGenerator.recommendedExercises(using: &rng)
        XCTAssertEqual(items.map(\.difficulty), [.初级, .中级, .高级])
    }
}
