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
}
