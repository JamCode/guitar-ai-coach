import XCTest
import UIKit
@testable import SwiftEarHost

final class SheetOCRRealImageSmokeTests: XCTestCase {
    func testVisionPipelineWithLocalSampleImages_whenEnvironmentIsSet() async throws {
        let raw = ProcessInfo.processInfo.environment["SHEET_OCR_SAMPLE_IMAGES"] ?? ""
        let paths = raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !paths.isEmpty else {
            throw XCTSkip("Set SHEET_OCR_SAMPLE_IMAGES=/abs/page1.jpg,/abs/page2.jpg to run local Vision OCR smoke test.")
        }
        let images = paths.compactMap { UIImage(contentsOfFile: $0) }
        XCTAssertEqual(images.count, paths.count, "Every configured sample image path must load.")

        let draft = try await SheetOCRPipeline().recognize(images: images)
        let chordCount = draft.allSystems.reduce(0) { $0 + $1.chords.count }
        let lyricCount = draft.allSystems.reduce(0) { $0 + $1.lyrics.count }

        print("SheetOCR smoke title=\(draft.title?.text ?? "-") key=\(draft.originalKey?.text ?? "-") pages=\(draft.pages.count) systems=\(draft.allSystems.count) chords=\(chordCount) lyrics=\(lyricCount)")
        for page in draft.pages {
            print("SheetOCR page \(page.pageIndex + 1): systems=\(page.systems.count) diagnostics=\(page.diagnostics.joined(separator: "; "))")
            for system in page.systems {
                let chords = system.chords.map(\.text).joined(separator: " ")
                let melody = system.melody.map(\.text).joined(separator: " / ")
                let lyrics = system.lyrics.map(\.text).joined(separator: " / ")
                print("  system \(system.systemIndex + 1): chords=[\(chords)] melody=[\(melody)] lyrics=[\(lyrics)]")
            }
        }
        XCTAssertFalse(draft.rawObservations.isEmpty)
        XCTAssertFalse(draft.pages.isEmpty)
    }
}
