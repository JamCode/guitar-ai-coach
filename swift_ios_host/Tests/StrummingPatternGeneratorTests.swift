import XCTest
@testable import SwiftEarHost

final class StrummingPatternGeneratorTests: XCTestCase {
    func testPoolsContainCommonPatternsByDifficulty() {
        let beginner = StrummingPatternGenerator.poolForDifficulty(.初级)
        let intermediate = StrummingPatternGenerator.poolForDifficulty(.中级)
        let advanced = StrummingPatternGenerator.poolForDifficulty(.高级)

        XCTAssertFalse(beginner.isEmpty)
        XCTAssertFalse(intermediate.isEmpty)
        XCTAssertFalse(advanced.isEmpty)

        XCTAssertTrue(beginner.contains(where: { $0.id == "all-down-eighths" }))
        XCTAssertTrue(intermediate.contains(where: { $0.id == "folk-dduudu" }))
        XCTAssertTrue(advanced.contains(where: { $0.id == "shuffle-eighths" }))
    }

    func testNextPatternAvoidsImmediateRepeatWhenPoolHasMultiple() {
        var rng = SystemRandomNumberGenerator()
        let pool = StrummingPatternGenerator.poolForDifficulty(.中级)
        XCTAssertGreaterThanOrEqual(pool.count, 2)

        let current = pool[0]
        let next = StrummingPatternGenerator.nextPattern(
            difficulty: .中级,
            excluding: current.id,
            using: &rng
        )
        XCTAssertNotEqual(next.id, current.id)
    }

    func testTabStaffGlyphMapping_matchesAStyleSpec() {
        XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .down), .downStroke)
        XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .up), .upStroke)
        XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .rest), .rest)

        XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .down).symbol, "↑") // 下扫
        XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .up).symbol, "↓") // 上扫
        XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .rest).symbol, "·") // 空拍
    }
}
