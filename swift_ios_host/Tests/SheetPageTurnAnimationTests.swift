import SwiftUI
import XCTest
@testable import SwiftEarHost

final class SheetPageTurnAnimationTests: XCTestCase {
    func testTransitionEdgesFollowSwipeDirection() {
        XCTAssertEqual(SheetPageTurnDirection.forward.insertionEdge, .trailing)
        XCTAssertEqual(SheetPageTurnDirection.forward.removalEdge, .leading)
        XCTAssertEqual(SheetPageTurnDirection.backward.insertionEdge, .leading)
        XCTAssertEqual(SheetPageTurnDirection.backward.removalEdge, .trailing)
    }
}
