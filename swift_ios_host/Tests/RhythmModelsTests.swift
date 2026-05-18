import XCTest
@testable import SwiftEarHost

final class RhythmModelsTests: XCTestCase {
    func testDisplayText_allQuarterNotes() {
        let p = RhythmPattern(grid: [1,0,1,0,1,0,1,0])!
        XCTAssertEqual(p.displayText, "X X X X")
    }

    func testDisplayText_allEighthNotes() {
        let p = RhythmPattern(grid: [1,1,1,1,1,1,1,1])!
        // 每个 [1,1] = X（四分），所以是 4 个 X
        XCTAssertEqual(p.displayText, "X X X X")
    }

    func testDisplayText_dottedQuarter() {
        let p = RhythmPattern(grid: [1,0,0,0,1,0,1,0])!
        // [1,0]=X̲0̲, [0,0]=0, [1,0]=X̲0̲, [1,0]=X̲0̲
        let ul = "\u{0332}"
        XCTAssertEqual(p.displayText, "X\(ul)0\(ul) 0 X\(ul)0\(ul) X\(ul)0\(ul)")
    }

    func testDisplayText_restOnFirstBeat() {
        let p = RhythmPattern(grid: [0,0,1,1,1,0,1,0])!
        // [0,0]=0, [1,1]=X, [1,0]=X̲0̲, [1,0]=X̲0̲
        let ul = "\u{0332}"
        XCTAssertEqual(p.displayText, "0 X X\(ul)0\(ul) X\(ul)0\(ul)")
    }

    func testGridValidation_exactly8() {
        XCTAssertNil(RhythmPattern(grid: [1,0,1,0,1,0,1]))
        XCTAssertNil(RhythmPattern(grid: [1,0,1,0,1,0,1,0,1]))
        XCTAssertNil(RhythmPattern(grid: [1,0,1,0,1,0,1,2]))
        XCTAssertNotNil(RhythmPattern(grid: [1,0,1,0,1,0,1,0]))
    }
}
