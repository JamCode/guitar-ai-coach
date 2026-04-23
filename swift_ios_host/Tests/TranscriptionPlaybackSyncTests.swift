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
        XCTAssertEqual(PlaybackSyncResolver.currentIndex(for: 12_000, segments: segments), nil)
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
}
