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

    func testLocalChordDecoder_decodesBasicQualitiesAndSlashChord() {
        let decoder = LocalChordOutputDecoder()
        let output = Self.makeModelOutput(
            frames: [
                .init(root: 0, bass: 0, intervals: [0, 4, 7]),      // C
                .init(root: 2, bass: 2, intervals: [0, 3, 7]),      // Dm
                .init(root: 4, bass: 4, intervals: [0, 4, 7, 10]),  // E7
                .init(root: 5, bass: 5, intervals: [0, 3, 7, 10]),  // Fm7
                .init(root: 7, bass: 7, intervals: [0, 5, 7]),      // Gsus4
                .init(root: 9, bass: 9, intervals: [0, 2, 7]),      // Asus2
                .init(root: 11, bass: 11, intervals: [0, 3, 6]),    // Bdim
                .init(root: 8, bass: 8, intervals: [0, 4, 8]),      // Abaug
                .init(root: 6, bass: 6, intervals: [0, 7]),         // F#5
                .init(root: 0, bass: 7, intervals: [0, 4, 7]),      // C/G
            ]
        )

        let segments = decoder.decode(output: output, frameOffsetMs: 0)
        let chords = segments.map(\.chord)

        XCTAssertTrue(chords.contains("C"))
        XCTAssertTrue(chords.contains("Dm"))
        XCTAssertTrue(chords.contains("E7"))
        XCTAssertTrue(chords.contains("Fm7"))
        XCTAssertTrue(chords.contains("Gsus4"))
        XCTAssertTrue(chords.contains("Asus2"))
        XCTAssertTrue(chords.contains("Bdim"))
        XCTAssertTrue(chords.contains("Abaug"))
        XCTAssertTrue(chords.contains("F#5"))
        XCTAssertTrue(chords.contains("C/G"))
    }

    func testLocalChordPostprocessor_buildsPlayableCompactVariant() {
        let raw = [
            TranscriptionSegment(startMs: 0, endMs: 1_000, chord: "Cmaj7"),
            TranscriptionSegment(startMs: 1_000, endMs: 1_250, chord: "G"),
            TranscriptionSegment(startMs: 1_250, endMs: 2_500, chord: "Cmaj7"),
            TranscriptionSegment(startMs: 2_500, endMs: 3_800, chord: "Am7"),
        ]

        let result = LocalChordPostprocessor().buildResult(rawSegments: raw, durationMs: 3_800)

        XCTAssertEqual(result.originalKey, "C")
        XCTAssertFalse(result.displaySegments.isEmpty)
        XCTAssertFalse(result.timingVariants.playableCompact?.displaySegments.isEmpty ?? true)
        XCTAssertLessThanOrEqual(
            result.timingVariants.playableCompact?.displaySegments.count ?? Int.max,
            result.timingVariants.normal.displaySegments.count
        )
    }

    @MainActor
    func testProcessingMode_defaultsToFastChordRecognition() {
        let vm = TranscriptionHomeViewModel()

        XCTAssertEqual(vm.selectedProcessingMode, .chordOnlyFast)
        XCTAssertEqual(TranscriptionProcessingMode.chordOnlyFast.title, "快速扒歌")
        XCTAssertEqual(TranscriptionProcessingMode.stemSeparationOnly.title, "分离人声/伴奏")
    }

    func testStemProgressMessagesAreStable() {
        let separating = TranscriptionProgressState.separatingStems(0.42)
        XCTAssertEqual(separating.stage, .separatingStems)
        XCTAssertEqual(separating.percentage, 43)
        XCTAssertEqual(separating.message, "正在分离人声/伴奏 42%...")

        let extracting = TranscriptionProgressState.extractingAccompanimentForChord(0.5)
        XCTAssertEqual(extracting.stage, .separatingStems)
        XCTAssertEqual(extracting.percentage, 26)
        XCTAssertEqual(extracting.message, "检测到人声，正在提取伴奏 50%...")

        let saved = TranscriptionProgressState.completedStems()
        XCTAssertEqual(saved.stage, .completed)
        XCTAssertEqual(saved.message, "人声/伴奏分离完成")
    }

    func testChordAudioPreprocessorUsesOriginalAudioWhenNoVocalIsDetected() async throws {
        let media = DecodedTranscriptionMedia(
            fileName: "instrumental.wav",
            durationMs: 1_000,
            pcmSamples: Array(repeating: 0.4, count: 100),
            sampleRate: 100
        )
        let preprocessor = ChordRecognitionAudioPreprocessor(
            configuration: Self.testStemConfiguration,
            runnerFactory: { InstrumentalStemRunner() }
        )

        let result = try await preprocessor.prepare(media: media) { _ in }

        XCTAssertEqual(result.media, media)
        XCTAssertFalse(result.vocalPresence.shouldUseSeparatedAccompaniment)
    }

    func testChordAudioPreprocessorExtractsAccompanimentWhenVocalIsDetected() async throws {
        let media = DecodedTranscriptionMedia(
            fileName: "vocal-mix.wav",
            durationMs: 1_000,
            pcmSamples: Array(repeating: 0.5, count: 100),
            sampleRate: 100
        )
        var progress: [TranscriptionProgressState] = []
        let preprocessor = ChordRecognitionAudioPreprocessor(
            configuration: Self.testStemConfiguration,
            runnerFactory: { VocalMixStemRunner() }
        )

        let result = try await preprocessor.prepare(media: media) { state in
            progress.append(state)
        }

        XCTAssertEqual(result.media.sampleRate, 100)
        XCTAssertEqual(result.media.pcmSamples.count, 100)
        XCTAssertEqual(result.media.pcmSamples.first ?? 0, 0.15, accuracy: 0.0001)
        XCTAssertTrue(result.vocalPresence.shouldUseSeparatedAccompaniment)
        XCTAssertTrue(progress.contains { $0.message.contains("正在提取伴奏") })
    }

    func testStemSeparationModelIsBundledWithApp() {
        let packageURL = Bundle.main.url(forResource: "stemseparation", withExtension: "mlpackage")
        let compiledURL = Bundle.main.url(forResource: "stemseparation", withExtension: "mlmodelc")

        XCTAssertTrue(packageURL != nil || compiledURL != nil)
    }

    func testChordRecognitionFeatureExtractorUsesFixedModelShape() {
        let extractor = LocalChordFeatureExtractor()
        let short = [Float](repeating: 0, count: 2_048)
        let chunks = extractor.makeChunks(samples: short)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].features.count, LocalChordFeatureExtractor.nBins * LocalChordFeatureExtractor.chunkFrames)
        XCTAssertEqual(LocalChordFeatureExtractor.chunkFrames, 862)

        let long = [Float](repeating: 0, count: LocalChordFeatureExtractor.chunkSamples + 1)
        XCTAssertEqual(extractor.makeChunks(samples: long).count, 2)
    }

    func testChordRecognitionModelIsBundledWithApp() {
        let packageURL = Bundle.main.url(forResource: "chordrecognition", withExtension: "mlpackage")
        let compiledURL = Bundle.main.url(forResource: "chordrecognition", withExtension: "mlmodelc")

        XCTAssertTrue(packageURL != nil || compiledURL != nil)
    }

    private struct FrameSpec {
        let root: Int
        let bass: Int
        let intervals: [Int]
    }

    private static func makeModelOutput(frames: [FrameSpec]) -> LocalChordModelOutput {
        var root = [Float]()
        var bass = [Float]()
        var chroma = [Float]()
        for frame in frames {
            root.append(contentsOf: logits(classCount: 13, hot: frame.root))
            bass.append(contentsOf: logits(classCount: 13, hot: frame.bass))
            var chord = [Float](repeating: -5, count: 12)
            for interval in frame.intervals {
                chord[(frame.root + interval) % 12] = 5
            }
            chroma.append(contentsOf: chord)
        }
        return LocalChordModelOutput(
            rootLogits: root,
            bassLogits: bass,
            chordLogits: chroma,
            frameCount: frames.count
        )
    }

    private static func logits(classCount: Int, hot: Int) -> [Float] {
        var values = [Float](repeating: -5, count: classCount)
        values[hot] = 5
        return values
    }

    private static let testStemConfiguration = StemSeparationConfiguration(
        targetSampleRate: 100,
        chunkDurationSec: 0.4,
        overlapRatio: 0.5,
        stems: [.vocals, .accompaniment]
    )
}

private struct FakeChordRecognizer: ChordRecognizer {
    let frames: [RawChordFrame]
    let originalKey: String

    func recognize(samples _: [Float], sampleRate _: Double) async throws -> (frames: [RawChordFrame], originalKey: String) {
        (frames, originalKey)
    }
}

private struct InstrumentalStemRunner: StemSeparationModelRunning {
    let stems: [StemKind] = [.vocals, .accompaniment]

    func separate(samples: [Float], sampleRate _: Double) async throws -> [StemKind: [Float]] {
        [
            .vocals: Array(repeating: 0, count: samples.count),
            .accompaniment: samples,
        ]
    }
}

private struct VocalMixStemRunner: StemSeparationModelRunning {
    let stems: [StemKind] = [.vocals, .accompaniment]

    func separate(samples: [Float], sampleRate _: Double) async throws -> [StemKind: [Float]] {
        [
            .vocals: samples.map { $0 * 0.8 },
            .accompaniment: samples.map { $0 * 0.3 },
        ]
    }
}
