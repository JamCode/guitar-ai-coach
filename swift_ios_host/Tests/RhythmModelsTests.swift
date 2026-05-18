import XCTest
@testable import SwiftEarHost

final class RhythmModelsTests: XCTestCase {
    func testDisplayText_allQuarterNotes() {
        let p = RhythmPattern(grid: [1,0,1,0,1,0,1,0])!
        XCTAssertEqual(p.displayText, "X X X X")
    }

    func testDisplayText_allEighthNotes() {
        let p = RhythmPattern(grid: [1,1,1,1,1,1,1,1])!
        XCTAssertEqual(p.displayText, "XX XX XX XX")
    }

    func testDisplayText_dottedQuarter() {
        let p = RhythmPattern(grid: [1,0,0,0,1,0,1,0])!
        XCTAssertEqual(p.displayText, "X· . X X")
    }

    func testDisplayText_restOnFirstBeat() {
        let p = RhythmPattern(grid: [0,0,1,1,1,0,1,0])!
        XCTAssertEqual(p.displayText, ". XX X· X")
    }

    func testGridValidation_exactly8() {
        XCTAssertNil(RhythmPattern(grid: [1,0,1,0,1,0,1]))
        XCTAssertNil(RhythmPattern(grid: [1,0,1,0,1,0,1,0,1]))
        XCTAssertNil(RhythmPattern(grid: [1,0,1,0,1,0,1,2]))
        XCTAssertNotNil(RhythmPattern(grid: [1,0,1,0,1,0,1,0]))
    }
}
