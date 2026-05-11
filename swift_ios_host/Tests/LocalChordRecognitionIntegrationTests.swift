import XCTest
@testable import SwiftEarHost

final class LocalChordRecognitionIntegrationTests: XCTestCase {
    func testLocalChordRecognition_printsChordSegmentsForLocalAudio() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["RUN_LOCAL_CHORD_TEST"] == "1"
            || repoConfigValue(".chord_local_test_media") != nil
            || FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(".chord_force_separated_accompaniment").path)
            || FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(".chord_local_e2e").path) else {
            throw XCTSkip("Set RUN_LOCAL_CHORD_TEST=1, create .chord_local_e2e, or write a media path to .chord_local_test_media to run local chord recognition.")
        }

        let mediaURL = try resolveMediaURL(environment: environment)
        let modelURL = environment["CHORD_RECOGNITION_MODEL_PATH"].map(URL.init(fileURLWithPath:))
        let forceSeparatedAccompaniment = environment["CHORD_RECOGNITION_FORCE_SEPARATED_ACCOMPANIMENT"] == "1"
            || FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(".chord_force_separated_accompaniment").path)
        let outputSuffix = forceSeparatedAccompaniment ? "-separated-accompaniment-local-chords.txt" : "-local-chords.txt"
        let outputURL = outputDirectory(environment: environment).appendingPathComponent(mediaURL.deletingPathExtension().lastPathComponent + outputSuffix)

        let startedAt = Date()
        let decoded = try await TranscriptionMediaDecoder.decode(url: mediaURL)
        let input: DecodedTranscriptionMedia
        let inputDescription: String
        let vocalPresence: VocalPresenceDecision?
        if forceSeparatedAccompaniment {
            let separated = try await StemSeparationEngine(modelRunner: try CoreMLStemSeparationRunner())
                .separateStems(media: decoded) { progress in
                    print("[LocalChordTest] stem \(progress.stage) \(progress.completedSegments)/\(progress.totalSegments)")
                }
            guard let accompaniment = separated.stems[.accompaniment], !accompaniment.isEmpty else {
                throw StemSeparationError.missingStem(.accompaniment)
            }
            input = DecodedTranscriptionMedia(
                fileName: decoded.fileName,
                durationMs: decoded.durationMs,
                pcmSamples: accompaniment,
                sampleRate: separated.sampleRate
            )
            inputDescription = "separatedAccompaniment"
            vocalPresence = nil
        } else {
            let preprocessed = try await ChordRecognitionAudioPreprocessor().prepare(media: decoded) { state in
                print("[LocalChordTest] \(state.message)")
            }
            input = preprocessed.media
            inputDescription = "preprocessed"
            vocalPresence = preprocessed.vocalPresence
        }
        let result = try await LocalChordRecognitionService(modelURL: modelURL).transcribe(media: input)
        let elapsed = Date().timeIntervalSince(startedAt)

        let report = Self.report(
            mediaURL: mediaURL,
            inputDescription: inputDescription,
            vocalPresence: vocalPresence,
            result: result,
            elapsed: elapsed
        )
        print(report)

        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.write(to: outputURL, atomically: true, encoding: .utf8)
        print("[LocalChordTest] wrote \(outputURL.path)")

        XCTAssertGreaterThan(result.durationMs, 0)
        XCTAssertFalse(result.displaySegments.isEmpty)
        XCTAssertFalse(result.chordChartSegments.isEmpty)
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func resolveMediaURL(environment: [String: String]) throws -> URL {
        if let path = environment["CHORD_RECOGNITION_TEST_MEDIA"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw XCTSkip("missing CHORD_RECOGNITION_TEST_MEDIA fixture: \(url.path)")
            }
            return url
        }
        if let path = repoConfigValue(".chord_local_test_media") {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw XCTSkip("missing .chord_local_test_media fixture: \(url.path)")
            }
            return url
        }

        let defaultURL = repoRoot.appendingPathComponent("backend/chord_onnx_server/eval_audio/fixed_clips/yanyuan-short-30s.wav")
        guard FileManager.default.fileExists(atPath: defaultURL.path) else {
            throw XCTSkip("missing default fixture: \(defaultURL.path)")
        }
        return defaultURL
    }

    private func outputDirectory(environment: [String: String]) -> URL {
        if let path = environment["CHORD_RECOGNITION_OUTPUT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        if let path = repoConfigValue(".chord_local_test_output_dir") {
            return URL(fileURLWithPath: path)
        }
        return repoRoot.appendingPathComponent("local_chord_test_outputs")
    }

    private func repoConfigValue(_ filename: String) -> String? {
        let url = repoRoot.appendingPathComponent(filename)
        guard let value = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func report(
        mediaURL: URL,
        inputDescription: String,
        vocalPresence: VocalPresenceDecision?,
        result: LocalChordRecognitionResult,
        elapsed: TimeInterval
    ) -> String {
        var lines: [String] = []
        lines.append("===== Local Chord Recognition Result =====")
        lines.append("media: \(mediaURL.path)")
        lines.append("input: \(inputDescription)")
        lines.append(String(format: "wall: %.2fs", elapsed))
        lines.append(String(format: "duration: %.2fs", Double(result.durationMs) / 1000.0))
        if let vocalPresence {
            lines.append("vocalPresence: \(vocalPresence)")
        }
        lines.append("key: \(result.originalKey)")
        lines.append("displaySegments: \(result.displaySegments.count)")
        lines.append("chordChartSegments: \(result.chordChartSegments.count)")
        lines.append("")
        lines.append("----- displaySegments -----")
        lines.append(contentsOf: formattedSegments(result.displaySegments))
        lines.append("")
        lines.append("----- playableCompact -----")
        if let playable = result.timingVariants.playableCompact {
            lines.append(contentsOf: formattedSegments(playable.displaySegments))
        } else {
            lines.append("(none)")
        }
        lines.append("")
        lines.append("----- chart -----")
        lines.append(contentsOf: formattedSegments(result.chordChartSegments))
        lines.append("===== End Local Chord Recognition Result =====")
        return lines.joined(separator: "\n")
    }

    private static func formattedSegments(_ segments: [TranscriptionSegment]) -> [String] {
        segments.enumerated().map { index, segment in
            String(
                format: "%03d  %@ - %@  %@",
                index + 1,
                timestamp(segment.startMs),
                timestamp(segment.endMs),
                segment.chord
            )
        }
    }

    private static func timestamp(_ ms: Int) -> String {
        let totalSeconds = max(0, ms) / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let tenths = (max(0, ms) % 1000) / 100
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
