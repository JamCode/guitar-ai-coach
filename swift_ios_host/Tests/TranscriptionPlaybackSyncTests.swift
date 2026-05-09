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

    @MainActor
    func testPlayerViewModel_activeTimelineSegments_prefersSavedEditedChart() {
        let edited = [
            TranscriptionSegment(startMs: 0, endMs: 2_000, chord: "Am"),
            TranscriptionSegment(startMs: 2_000, endMs: 4_000, chord: "F"),
        ]
        let playableDisplay = [
            TranscriptionSegment(startMs: 0, endMs: 2_000, chord: "C"),
            TranscriptionSegment(startMs: 2_000, endMs: 4_000, chord: "G"),
        ]
        let entry = makeEntry(
            displaySegments: [TranscriptionSegment(startMs: 0, endMs: 4_000, chord: "E")],
            chordChartSegments: [TranscriptionSegment(startMs: 0, endMs: 4_000, chord: "E")],
            editedChordChartSegments: edited,
            timingVariants: makeTimingVariants(playableDisplay: playableDisplay, playableChart: playableDisplay)
        )
        let vm = TranscriptionPlayerViewModel(entry: entry)

        XCTAssertEqual(vm.activeTimelineSegments(from: entry), edited)
        XCTAssertEqual(vm.displaySanitizer(for: entry), .backendNoShortAbsorptionEdges)
    }

    @MainActor
    func testPlayerViewModel_prefersPlayableCompactWhenNoSavedEditExists() {
        let playableDisplay = [
            TranscriptionSegment(startMs: 0, endMs: 3_000, chord: "G"),
            TranscriptionSegment(startMs: 3_000, endMs: 6_000, chord: "D"),
        ]
        let playableChart = [
            TranscriptionSegment(startMs: 0, endMs: 6_000, chord: "G")
        ]
        let fallbackDisplay = [
            TranscriptionSegment(startMs: 0, endMs: 6_000, chord: "C")
        ]
        let fallbackChart = [
            TranscriptionSegment(startMs: 0, endMs: 6_000, chord: "F")
        ]
        let entry = makeEntry(
            displaySegments: fallbackDisplay,
            chordChartSegments: fallbackChart,
            timingVariants: makeTimingVariants(playableDisplay: playableDisplay, playableChart: playableChart)
        )
        let vm = TranscriptionPlayerViewModel(entry: entry)

        XCTAssertEqual(vm.activeTimelineSegments(from: entry), playableDisplay)
        XCTAssertEqual(vm.activeChordChartSource(from: entry), playableChart)
        XCTAssertEqual(vm.displaySanitizer(for: entry), .backendNoShortAbsorptionEdges)
    }

    @MainActor
    func testPlayerViewModel_fallsBackToStoredSegmentsWithoutPlayableCompact() {
        let display = [
            TranscriptionSegment(startMs: 0, endMs: 3_000, chord: "Dm")
        ]
        let chart = [
            TranscriptionSegment(startMs: 0, endMs: 3_000, chord: "A7")
        ]
        let entry = makeEntry(
            displaySegments: display,
            chordChartSegments: chart,
            timingVariants: nil
        )
        let vm = TranscriptionPlayerViewModel(entry: entry)

        XCTAssertEqual(vm.activeTimelineSegments(from: entry), display)
        XCTAssertEqual(vm.activeChordChartSource(from: entry), chart)
        XCTAssertEqual(vm.displaySanitizer(for: entry), .fullClientPipeline)
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

    private func makeEntry(
        displaySegments: [TranscriptionSegment],
        chordChartSegments: [TranscriptionSegment],
        editedChordChartSegments: [TranscriptionSegment]? = nil,
        timingVariants: TranscriptionTimingVariants? = nil
    ) -> TranscriptionHistoryEntry {
        TranscriptionHistoryEntry(
            id: "test-entry",
            sourceType: .files,
            fileName: "demo.m4a",
            customName: "demo",
            storedMediaPath: "transcription_media/demo.m4a",
            durationMs: 6_000,
            originalKey: "C",
            createdAtMs: 0,
            segments: displaySegments,
            displaySegments: displaySegments,
            chordChartSegments: chordChartSegments,
            editedChordChartSegments: editedChordChartSegments,
            editedChordChartRowSizes: editedChordChartSegments.map { [$0.count] },
            editedAtMs: editedChordChartSegments == nil ? nil : 1,
            timingVariants: timingVariants,
            timingVariantStats: nil,
            backend: "remote",
            waveform: []
        )
    }

    private func makeTimingVariants(
        playableDisplay: [TranscriptionSegment],
        playableChart: [TranscriptionSegment]
    ) -> TranscriptionTimingVariants {
        let baseBundle = TranscriptionTimingVariantBundle(
            displaySegments: [],
            simplifiedDisplaySegments: [],
            chordChartSegments: []
        )
        let playableBundle = TranscriptionTimingVariantBundle(
            displaySegments: playableDisplay,
            simplifiedDisplaySegments: playableDisplay,
            chordChartSegments: playableChart
        )
        return TranscriptionTimingVariants(
            normal: baseBundle,
            noAbsorb: baseBundle,
            timing: nil,
            timingCompact: nil,
            playableCompact: playableBundle
        )
    }
}
