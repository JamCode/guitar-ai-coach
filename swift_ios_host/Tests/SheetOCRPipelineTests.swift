import XCTest
import UIKit
@testable import SwiftEarHost

final class SheetOCRPipelineTests: XCTestCase {
    func testPipelineWithMockRecognizerBuildsDraftAndParsedData() async throws {
        let image = makeSyntheticTabUIImage(width: 800, height: 1000, staffTop: 260)
        let recognizer = MockSheetTextRecognizer()
        let pipeline = SheetOCRPipeline(
            preprocessor: SheetImagePreprocessor(),
            recognizer: recognizer,
            detector: SheetStaffSystemDetector(minDarkPixelRatioForLine: 0.25),
            parser: SheetOCRParser()
        )

        let draft = try await pipeline.recognize(images: [image])
        let parsed = SheetOCRDraftAdapter().makeParsedData(from: draft, sheetId: "sheet-1")

        XCTAssertEqual(draft.title?.text, "枫")
        XCTAssertEqual(draft.originalKey?.text, "1=C")
        XCTAssertEqual(draft.pages.count, 1)
        XCTAssertEqual(draft.pages[0].systems.count, 1)
        XCTAssertEqual(draft.pages[0].systems[0].chords.map(\.text), ["C", "G/B", "Am", "Em"])
        XCTAssertEqual(draft.pages[0].systems[0].lyrics.map(\.text), ["缓缓飘落的枫叶像思念"])

        XCTAssertEqual(parsed.sheetId, "sheet-1")
        XCTAssertEqual(parsed.parseStatus, .draft)
        XCTAssertEqual(parsed.originalKey, "1=C")
        XCTAssertEqual(parsed.segments, [
            SheetSegment(chords: ["C", "G/B", "Am", "Em"], melody: "", lyrics: "缓缓飘落的枫叶像思念")
        ])
    }

    private func makeSyntheticTabUIImage(width: Int, height: Int, staffTop: Int) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.black.setStroke()
            let cg = context.cgContext
            cg.setLineWidth(2)
            for line in 0..<6 {
                let y = CGFloat(staffTop + line * 14)
                cg.move(to: CGPoint(x: 80, y: y))
                cg.addLine(to: CGPoint(x: CGFloat(width - 80), y: y))
                cg.strokePath()
            }
        }
    }
}

private struct MockSheetTextRecognizer: SheetTextRecognizing {
    func recognize(
        image: CGImage,
        region: SheetOCRRect?,
        configuration: SheetTextRecognitionConfiguration
    ) async throws -> [SheetOCRTextObservation] {
        switch configuration.source {
        case .fullPage:
            return [
                SheetOCRTextObservation(text: "枫", confidence: 0.95, rect: SheetOCRRect(x: 0.48, y: 0.05, width: 0.04, height: 0.03), source: .fullPage),
                SheetOCRTextObservation(text: "1= C  4/4", confidence: 0.92, rect: SheetOCRRect(x: 0.10, y: 0.13, width: 0.16, height: 0.03), source: .fullPage)
            ]
        case .chordZone, .chordLabelZone:
            return [
                SheetOCRTextObservation(text: "C  G/B  Am  Em", confidence: 0.91, rect: SheetOCRRect(x: 0.12, y: 0.21, width: 0.56, height: 0.03), source: configuration.source)
            ]
        case .jianpuZone:
            return [
                SheetOCRTextObservation(text: "0 5 1 7 1 2 3 1", confidence: 0.82, rect: SheetOCRRect(x: 0.12, y: 0.36, width: 0.55, height: 0.03), source: .jianpuZone)
            ]
        case .lyricZone:
            return [
                SheetOCRTextObservation(text: "缓缓飘落的枫叶像思念", confidence: 0.90, rect: SheetOCRRect(x: 0.12, y: 0.40, width: 0.55, height: 0.03), source: .lyricZone)
            ]
        }
    }
}
