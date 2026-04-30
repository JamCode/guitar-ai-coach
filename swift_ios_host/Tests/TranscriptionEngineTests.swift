import XCTest
@testable import SwiftEarHost

final class TranscriptionEngineTests: XCTestCase {
    func testMergeSegments_mergesAdjacentIdenticalChords() {
        let raw = [
            RawChordFrame(startMs: 0, endMs: 1_000, chord: "E"),
            RawChordFrame(startMs: 1_000, endMs: 2_000, chord: "E"),
            RawChordFrame(startMs: 2_000, endMs: 3_000, chord: "B"),
        ]

        let merged = TranscriptionEngine.mergeSegments(raw)

        XCTAssertEqual(
            merged,
            [
                TranscriptionSegment(startMs: 0, endMs: 2_000, chord: "E"),
                TranscriptionSegment(startMs: 2_000, endMs: 3_000, chord: "B"),
            ]
        )
    }

    func testRecognize_usesInjectedRecognizerAndReturnsMergedSegments() async throws {
        let recognizer = FakeChordRecognizer(
            frames: [
                RawChordFrame(startMs: 0, endMs: 500, chord: "E"),
                RawChordFrame(startMs: 500, endMs: 1_000, chord: "E"),
                RawChordFrame(startMs: 1_000, endMs: 1_500, chord: "B"),
            ],
            originalKey: "E"
        )

        let result = try await TranscriptionOrchestrator(recognizer: recognizer).recognize(
            fileName: "demo.m4a",
            durationMs: 1_500,
            samples: [0, 0.2, -0.3, 0.5],
            sampleRate: 22_050
        )

        XCTAssertEqual(result.fileName, "demo.m4a")
        XCTAssertEqual(result.originalKey, "E")
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0], TranscriptionSegment(startMs: 0, endMs: 1_000, chord: "E"))
        XCTAssertFalse(result.waveform.isEmpty)
    }

    func testRemoteChordRecognitionResult_decodesPlayableCompactVariant() throws {
        let json = """
        {
          "success": true,
          "key": "B",
          "segments": [{"start": 0.0, "end": 1.0, "chord": "B"}],
          "displaySegments": [{"start": 0.0, "end": 1.0, "chord": "B"}],
          "chordChartSegments": [{"start": 0.0, "end": 1.0, "chord": "B"}],
          "timingVariants": {
            "normal": {
              "displaySegments": [{"start": 0.0, "end": 1.0, "chord": "B"}],
              "simplifiedDisplaySegments": [{"start": 0.0, "end": 1.0, "chord": "B"}],
              "chordChartSegments": [{"start": 0.0, "end": 1.0, "chord": "B"}]
            },
            "noAbsorb": {
              "displaySegments": [{"start": 0.0, "end": 1.0, "chord": "B"}],
              "simplifiedDisplaySegments": [{"start": 0.0, "end": 1.0, "chord": "B"}],
              "chordChartSegments": [{"start": 0.0, "end": 1.0, "chord": "B"}]
            },
            "playableCompact": {
              "displaySegments": [{"start": 0.0, "end": 2.0, "chord": "B"}],
              "simplifiedDisplaySegments": [{"start": 0.0, "end": 2.0, "chord": "B"}],
              "chordChartSegments": [{"start": 0.0, "end": 2.0, "chord": "B"}]
            }
          }
        }
        """

        let decoded = try JSONDecoder().decode(
            RemoteChordRecognitionResult.self,
            from: Data(json.utf8)
        )

        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.key, "B")
        XCTAssertEqual(decoded.timingVariants?.playableCompact?.displaySegments.first?.chord, "B")
        XCTAssertEqual(decoded.timingVariants?.playableCompact?.displaySegments.first?.endMs, 2_000)
    }
}

private struct FakeChordRecognizer: ChordRecognizer {
    let frames: [RawChordFrame]
    let originalKey: String

    func recognize(samples _: [Float], sampleRate _: Double) async throws -> (frames: [RawChordFrame], originalKey: String) {
        (frames, originalKey)
    }
}
