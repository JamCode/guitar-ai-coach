import XCTest
@testable import SwiftEarHost

final class TranscriptionImportServiceTests: XCTestCase {
    func testValidateSupportedExtension_acceptsConfiguredFormats() {
        XCTAssertNoThrow(try TranscriptionImportService.validate(fileName: "demo.mp3", durationMs: 30_000))
        XCTAssertNoThrow(try TranscriptionImportService.validate(fileName: "demo.mov", durationMs: 30_000))
    }

    func testValidateUnsupportedExtension_throwsFriendlyError() {
        XCTAssertThrowsError(try TranscriptionImportService.validate(fileName: "demo.ogg", durationMs: 30_000)) { error in
            XCTAssertEqual((error as? TranscriptionImportError), .unsupportedFileType)
        }
    }

    func testValidateDurationOverSixMinutes_throwsFriendlyError() {
        XCTAssertThrowsError(try TranscriptionImportService.validate(fileName: "demo.mp4", durationMs: 360_001)) { error in
            XCTAssertEqual((error as? TranscriptionImportError), .durationTooLong)
        }
    }
}
