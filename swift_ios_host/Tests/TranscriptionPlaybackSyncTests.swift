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
}
