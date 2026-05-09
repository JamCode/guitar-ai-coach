import XCTest
@testable import SwiftEarHost

final class ScaleWarmupGeneratorTests: XCTestCase {
    func testPools_nonEmptyPerDifficulty() {
        for d in ScaleWarmupDifficulty.allCases {
            XCTAssertFalse(ScaleWarmupGenerator.drills(for: d).isEmpty, "\(d)")
        }
    }

    func testNext_avoidsImmediateRepeatWhenPoolHasMultiple() {
        var rng = SystemRandomNumberGenerator()
        let difficulty = ScaleWarmupDifficulty.初级
        let first = ScaleWarmupGenerator.nextDrill(difficulty: difficulty, excluding: nil, using: &rng)
        let second = ScaleWarmupGenerator.nextDrill(difficulty: difficulty, excluding: first.id, using: &rng)
        let pool = ScaleWarmupGenerator.drills(for: difficulty)
        if pool.count > 1 {
            XCTAssertNotEqual(first.id, second.id)
        }
    }

    func testAllDrills_spanAtLeastFourFrets() {
        for difficulty in ScaleWarmupDifficulty.allCases {
            for d in ScaleWarmupGenerator.drills(for: difficulty) {
                let span = d.fretEnd - d.fretStart + 1
                XCTAssertGreaterThanOrEqual(span, 4, "drill=\(d.id) span=\(span)")
            }
        }
    }

    func testDrill_crawl_b_6_4_68_hasSequenceAndGridSteps() {
        let d = ScaleWarmupGenerator.drills(for: .初级).first { $0.id == "crawl_b_6_4_68" }!
        XCTAssertEqual(d.stringsIncluded, [4, 5, 6])
        XCTAssertEqual(d.fretStart, 1)
        XCTAssertEqual(d.fretEnd, 4)
        XCTAssertEqual(d.orderedSteps.count, 12) // 3 弦 × 4 品
        XCTAssertEqual(d.orderedSteps.first?.stringNumber, 6)
        XCTAssertEqual(d.orderedSteps.first?.fret, 1)
        XCTAssertEqual(d.orderedSteps.first?.order, 1)
        XCTAssertEqual(d.orderedSteps.last?.stringNumber, 4)
        XCTAssertEqual(d.orderedSteps.last?.fret, 4)
        XCTAssertEqual(d.orderedSteps.last?.order, 12)
        XCTAssertFalse(d.sequenceBullets.isEmpty)
    }
}
