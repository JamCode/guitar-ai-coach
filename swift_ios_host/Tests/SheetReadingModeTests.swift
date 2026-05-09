import XCTest
@testable import SwiftEarHost

final class SheetReadingModeTests: XCTestCase {
    func testToggleSwitchesBetweenPagedAndContinuousModes() {
        XCTAssertEqual(SheetReadingMode.paged.toggled, .continuous)
        XCTAssertEqual(SheetReadingMode.continuous.toggled, .paged)
    }

    func testToolbarTitleKeyShowsDestinationMode() {
        XCTAssertEqual(SheetReadingMode.paged.toolbarTitleKey, "sheets_reading_mode_continuous")
        XCTAssertEqual(SheetReadingMode.continuous.toolbarTitleKey, "sheets_reading_mode_paged")
    }
}
