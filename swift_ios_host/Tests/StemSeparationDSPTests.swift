import XCTest
@testable import SwiftEarHost

final class StemSeparationDSPTests: XCTestCase {
    func testMakeSegmentRanges_usesConfiguredOverlap() throws {
        let ranges = try StemSeparationDSP.makeSegmentRanges(
            sampleCount: 100,
            sampleRate: 10,
            chunkDurationSec: 4,
            overlapRatio: 0.5
        )

        XCTAssertEqual(
            ranges,
            [
                StemSegmentRange(index: 0, startSample: 0, endSample: 40),
                StemSegmentRange(index: 1, startSample: 20, endSample: 60),
                StemSegmentRange(index: 2, startSample: 40, endSample: 80),
                StemSegmentRange(index: 3, startSample: 60, endSample: 100),
            ]
        )
    }

    func testLinearResample_downsamplesByRatio() {
        let output = StemSeparationDSP.linearResample(
            samples: [0, 1, 2, 3, 4, 5, 6, 7],
            sourceSampleRate: 8,
            targetSampleRate: 4
        )

        XCTAssertEqual(output, [0, 2, 4, 6])
    }

    func testStitch_crossfadesOverlappingSegments() throws {
        let stitched = try StemSeparationDSP.stitch(
            segments: [
                (
                    range: StemSegmentRange(index: 0, startSample: 0, endSample: 4),
                    stems: [.vocals: [1, 1, 1, 1]]
                ),
                (
                    range: StemSegmentRange(index: 1, startSample: 2, endSample: 6),
                    stems: [.vocals: [3, 3, 3, 3]]
                ),
            ],
            outputSampleCount: 6,
            expectedStems: [.vocals]
        )

        let vocals = try XCTUnwrap(stitched[.vocals])
        XCTAssertEqual(vocals.count, 6)
        XCTAssertEqual(vocals[0], Float(1), accuracy: 0.0001)
        XCTAssertEqual(vocals[1], Float(1), accuracy: 0.0001)
        XCTAssertEqual(vocals[2], Float(1.6667), accuracy: 0.0001)
        XCTAssertEqual(vocals[3], Float(2.3333), accuracy: 0.0001)
        XCTAssertEqual(vocals[4], Float(3), accuracy: 0.0001)
        XCTAssertEqual(vocals[5], Float(3), accuracy: 0.0001)
    }

    func testSpectrogramProcessor_roundTripsTone() throws {
        let processor = try XCTUnwrap(StemSeparationSpectrogramProcessor())
        let sampleRate = 44_100.0
        let count = 44_100
        let samples = (0..<count).map {
            Float(sin(2 * Double.pi * 440 * Double($0) / sampleRate) * 0.2)
        }

        let reconstructed = processor.fftRoundTripForTesting(samples)

        XCTAssertEqual(reconstructed.count, samples.count)
        let start = 4096
        let end = samples.count - 4096
        var maxError: Float = 0
        for i in start..<end {
            maxError = max(maxError, abs(reconstructed[i] - samples[i]))
        }
        XCTAssertLessThan(maxError, 0.01)
    }
}
