import XCTest
@testable import SwiftEarHost

final class TranscriptionPlaybackSyncTests: XCTestCase {
    func testCurrentChordIndex_returnsMatchingSegment() {
        let segments = [
            TranscriptionSegment(startMs: 0, endMs: 4_000, chord: "E"),
            TranscriptionSegment(startMs: 4_000, endMs: 8_000, chord: "B"),
            TranscriptionSegment(startMs: 8_000, endMs: 12_000, chord: "C#m"),
        ]

        XCTAssertEqual(PlaybackSyncResolver.currentIndex(for: 5_000, segments: segments), 1)
        XCTAssertEqual(PlaybackSyncResolver.currentIndex(for: 10_000, segments: segments), 2)
        XCTAssertEqual(PlaybackSyncResolver.currentIndex(for: 12_000, segments: segments), 2)
    }

    func testUpcomingSegments_returnsNextFewSegmentsAfterCurrentTime() {
        let segments = [
            TranscriptionSegment(startMs: 0, endMs: 4_000, chord: "E"),
            TranscriptionSegment(startMs: 4_000, endMs: 8_000, chord: "B"),
            TranscriptionSegment(startMs: 8_000, endMs: 12_000, chord: "C#m"),
            TranscriptionSegment(startMs: 12_000, endMs: 16_000, chord: "A"),
            TranscriptionSegment(startMs: 16_000, endMs: 20_000, chord: "D"),
        ]

        XCTAssertEqual(
            PlaybackSyncResolver.upcomingSegments(for: 5_000, segments: segments, limit: 3).map(\.chord),
            ["C#m", "A", "D"]
        )
        XCTAssertEqual(
            PlaybackSyncResolver.upcomingSegments(for: 19_500, segments: segments).map(\.chord),
            []
        )
    }

    func testMakeDisplayChordSegments_resolvesSameSecondConflictByKeepingMainChord() {
        let raw = [
            TranscriptionSegment(startMs: 34_500, endMs: 35_100, chord: "Em"),
            // Same display second, different chords:
            TranscriptionSegment(startMs: 35_100, endMs: 35_420, chord: "D/F#"), // 0.32s
            TranscriptionSegment(startMs: 35_420, endMs: 36_320, chord: "D"), // 0.90s
            TranscriptionSegment(startMs: 36_320, endMs: 37_100, chord: "G")
        ]

        let display = TranscriptionChordResolver.makeDisplayChordSegments(rawSegments: raw)

        let bucket = display.filter { ($0.startMs / 1_000) == 35 }
        XCTAssertEqual(bucket.count, 1, "same second should keep one main chord in UI list")
        XCTAssertEqual(bucket.first?.chord, "D")
        XCTAssertTrue(hasNoSameSecondDifferentChords(display))
    }

    func testMakeDisplayChordSegments_mergesVeryShortSegmentToNeighbor() {
        let raw = [
            TranscriptionSegment(startMs: 10_000, endMs: 10_900, chord: "C"),
            TranscriptionSegment(startMs: 10_900, endMs: 11_150, chord: "G/B"), // 0.25s short
            TranscriptionSegment(startMs: 11_150, endMs: 12_100, chord: "G")
        ]

        let display = TranscriptionChordResolver.makeDisplayChordSegments(rawSegments: raw)

        XCTAssertTrue(display.count <= 2, "short segment should be merged/absorbed")
        XCTAssertTrue(hasNoSameSecondDifferentChords(display))
        XCTAssertTrue(display.allSatisfy { $0.endMs > $0.startMs })
    }

    private func hasNoSameSecondDifferentChords(_ segments: [TranscriptionSegment]) -> Bool {
        let groups = Dictionary(grouping: segments) { $0.startMs / 1_000 }
        for bucket in groups.values {
            let unique = Set(bucket.map { ChordFingeringResolver.normalizeChordName($0.chord) })
            if unique.count > 1 {
                return false
            }
        }
        return true
    }
}
