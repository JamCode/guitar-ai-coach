import XCTest
@testable import SwiftEarHost

final class TranscriptionOnnxPipelineTests: XCTestCase {
    func testFeatureExtractor_extracts144BinsForTwentySecondChunk() throws {
        let sampleRate = 44_100.0
        let durationSec = 20.0
        let sampleCount = Int(sampleRate * durationSec)
        let samples = (0..<sampleCount).map { index in
            Float(sin(2.0 * Double.pi * 440.0 * Double(index) / sampleRate))
        }

        let tensor = try TranscriptionCQTFeatureExtractor().extractChunk(samples: samples, sampleRate: sampleRate)

        XCTAssertEqual(tensor.shape, [1, 1, 144, 862])
        XCTAssertEqual(tensor.values.count, 144 * 862)
        XCTAssertGreaterThan(tensor.values.max() ?? 0, 0.01)
    }

    func testLabelDecoder_mergesCommonChordFrames() {
        let cMajor = [1.0, 0, 0, 0, 1.0, 0, 0, 1.0, 0, 0, 0, 0]
        let gMajor = [0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 1.0]

        let frames = OnnxChordLabelDecoder.decodeFrames(
            rootIndices: [0, 0, 7, 7],
            bassIndices: [0, 0, 7, 7],
            chordProbabilities: [cMajor, cMajor, gMajor, gMajor],
            frameDurationMs: 100,
            threshold: 0.5,
            minDurationMs: 50
        )

        XCTAssertEqual(
            frames,
            [
                RawChordFrame(startMs: 0, endMs: 200, chord: "C"),
                RawChordFrame(startMs: 200, endMs: 400, chord: "G"),
            ]
        )
    }
}
