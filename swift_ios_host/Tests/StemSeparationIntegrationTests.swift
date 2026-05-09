import XCTest
@testable import SwiftEarHost

final class StemSeparationIntegrationTests: XCTestCase {
    func testRealCoreMLSeparation_whenEnvironmentProvidesMedia() async throws {
        let environment = ProcessInfo.processInfo.environment
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let modelPath = environment["STEM_SEPARATION_MODEL_PATH"] ?? repoRoot.appendingPathComponent("ios_stem_model/stemseparation.mlpackage").path
        let mediaURLs: [URL]
        if let mediaPath = environment["STEM_SEPARATION_TEST_MEDIA"] {
            mediaURLs = [URL(fileURLWithPath: mediaPath)]
        } else {
            mediaURLs = ["zouzou.mp4", "yanyuan.mp4"]
                .map { repoRoot.appendingPathComponent($0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        guard !mediaURLs.isEmpty, FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("Set STEM_SEPARATION_TEST_MEDIA and STEM_SEPARATION_MODEL_PATH to run real stem separation.")
        }

        let trimSeconds = Double(environment["STEM_SEPARATION_TEST_SECONDS"] ?? "15") ?? 15
        for mediaURL in mediaURLs {
            try await runSeparationSmokeTest(
                mediaURL: mediaURL,
                modelPath: modelPath,
                trimSeconds: trimSeconds,
                outputDirectory: outputDirectory(environment: environment, repoRoot: repoRoot)
            )
        }
    }

    private func runSeparationSmokeTest(
        mediaURL: URL,
        modelPath: String,
        trimSeconds: Double,
        outputDirectory: URL
    ) async throws {
        let media = try await TranscriptionMediaDecoder.decode(url: mediaURL)
        let targetSampleRate = 44_100.0
        let resampled = StemSeparationDSP.linearResample(
            samples: media.pcmSamples,
            sourceSampleRate: media.sampleRate,
            targetSampleRate: targetSampleRate
        )
        let trimmedCount = min(resampled.count, Int(targetSampleRate * trimSeconds))
        let trimmedMedia = DecodedTranscriptionMedia(
            fileName: media.fileName,
            durationMs: Int((Double(trimmedCount) / targetSampleRate * 1000).rounded()),
            pcmSamples: Array(resampled.prefix(trimmedCount)),
            sampleRate: targetSampleRate
        )

        let engine = StemSeparationEngine(
            configuration: StemSeparationConfiguration(
                targetSampleRate: targetSampleRate,
                chunkDurationSec: 512.0 * 1024.0 / targetSampleRate,
                overlapRatio: 0,
                stems: [.vocals, .accompaniment]
            ),
            modelRunner: try CoreMLStemSeparationRunner(modelURL: URL(fileURLWithPath: modelPath))
        )

        let result = try await engine.separate(media: trimmedMedia, outputDirectory: outputDirectory)

        let vocals = try XCTUnwrap(result.stems[.vocals])
        let accompaniment = try XCTUnwrap(result.stems[.accompaniment])
        XCTAssertTrue(FileManager.default.fileExists(atPath: vocals))
        XCTAssertTrue(FileManager.default.fileExists(atPath: accompaniment))
        XCTAssertGreaterThan((try FileManager.default.attributesOfItem(atPath: vocals)[.size] as? NSNumber)?.intValue ?? 0, 44_100)
        XCTAssertGreaterThan((try FileManager.default.attributesOfItem(atPath: accompaniment)[.size] as? NSNumber)?.intValue ?? 0, 44_100)
        print("Stem separation integration output:", result.stems)
    }

    private func outputDirectory(environment: [String: String], repoRoot: URL) -> URL {
        let base = environment["STEM_SEPARATION_OUTPUT_DIR"].map(URL.init(fileURLWithPath:))
            ?? repoRoot.appendingPathComponent("stem_separation_test_outputs", isDirectory: true)
        return base.appendingPathComponent("stem-separation-integration-\(UUID().uuidString)", isDirectory: true)
    }
}
