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
        XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .mute), .mute)

        XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .down).symbol, "↑") // 下扫
        XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .up).symbol, "↓") // 上扫
        XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .rest).symbol, "·") // 空拍
        XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .mute).symbol, "×") // 拍弦
    }

    func testAllBuiltInPatterns_totalUnitsEqualsEightIn44() {
        for p in kStrummingPatterns {
            XCTAssertEqual(p.events.reduce(0) { $0 + $1.units }, 8, "pattern=\(p.id)")
        }
    }

    func testExpandEvents_downOneBeat_thenDownUpOneBeat() {
        let events: [StrumActionEvent] = [
            .init(kind: .down, units: 2), // 1 beat
            .init(kind: .down, units: 1), // half beat
            .init(kind: .up, units: 1), // half beat
            .init(kind: .rest, units: 4), // remaining 2 beats
        ]
        let cells = expandStrumEventsToCells(events, totalUnits: 8)
        XCTAssertEqual(cells.count, 8)
        XCTAssertEqual(cells, [.down, .rest, .down, .up, .rest, .rest, .rest, .rest])
    }
}
