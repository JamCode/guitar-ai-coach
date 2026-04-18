import XCTest
@testable import SwiftEarHost

final class TranscriptionWaveformServiceTests: XCTestCase {
    func testBuildSummary_downsamplesToRequestedBinCount() {
        let samples = (0..<1_000).map { _ in Float.random(in: -1...1) }
        let bins = TranscriptionWaveformService.buildSummary(samples: samples, binCount: 50)

        XCTAssertEqual(bins.count, 50)
        XCTAssertTrue(bins.allSatisfy { $0 >= 0 })
    }
}
