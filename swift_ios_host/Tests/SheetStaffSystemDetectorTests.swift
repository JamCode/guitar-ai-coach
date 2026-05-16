import XCTest
import UIKit
@testable import SwiftEarHost

final class SheetStaffSystemDetectorTests: XCTestCase {
    func testDetectSystems_findsSyntheticSixLineStaffs() throws {
        let image = try makeSyntheticTabPage(width: 800, height: 1000, staffTops: [220, 520])
        let detector = SheetStaffSystemDetector(minDarkPixelRatioForLine: 0.25)

        let systems = detector.detectSystems(in: image)

        XCTAssertEqual(systems.count, 2)
        XCTAssertEqual(systems[0].staffBounds.y, 0.22, accuracy: 0.03)
        XCTAssertEqual(systems[1].staffBounds.y, 0.52, accuracy: 0.03)
        XCTAssertLessThan(systems[0].chordZone.maxY, systems[0].staffBounds.minY)
        XCTAssertGreaterThan(systems[0].lyricZone.minY, systems[0].staffBounds.maxY)
    }

    private func makeSyntheticTabPage(width: Int, height: Int, staffTops: [Int]) throws -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let uiImage = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.black.setStroke()
            let cg = context.cgContext
            cg.setLineWidth(2)
            for top in staffTops {
                for line in 0..<6 {
                    let y = CGFloat(top + line * 14)
                    cg.move(to: CGPoint(x: 80, y: y))
                    cg.addLine(to: CGPoint(x: CGFloat(width - 80), y: y))
                    cg.strokePath()
                }
            }
        }
        guard let cgImage = uiImage.cgImage else {
            throw SheetOCRError.invalidImage
        }
        return cgImage
    }
}
