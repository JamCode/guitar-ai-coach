import XCTest
@testable import SwiftEarHost

final class TranscriptionImportServiceTests: XCTestCase {
    func testProgressStateMapsUploadFractionToConfiguredRange() {
        let start = TranscriptionProgressState.uploading(uploadFraction: 0)
        XCTAssertEqual(start.stage, .uploading)
        XCTAssertEqual(start.progress, 0.10, accuracy: 0.0001)
        XCTAssertEqual(start.message, "正在上传歌曲 0%...")

        let middle = TranscriptionProgressState.uploading(uploadFraction: 0.5)
        XCTAssertEqual(middle.progress, 0.275, accuracy: 0.0001)
        XCTAssertEqual(middle.message, "正在上传歌曲 50%...")

        let end = TranscriptionProgressState.uploading(uploadFraction: 1)
        XCTAssertEqual(end.progress, 0.45, accuracy: 0.0001)
        XCTAssertEqual(end.message, "正在上传歌曲 100%...")
    }

    func testProgressStateKeepsFailedProgress() {
        let analyzing = TranscriptionProgressState.analyzing(0.72)
        let failed = analyzing.failed(message: "识别失败，请稍后重试")

        XCTAssertEqual(failed.stage, .failed)
        XCTAssertEqual(failed.progress, 0.72, accuracy: 0.0001)
        XCTAssertEqual(failed.message, "识别失败，请稍后重试")
    }

    func testAnalyzingProgressCapsBeforeCompleted() {
        let analyzing = TranscriptionProgressState.analyzing(0.99)

        XCTAssertEqual(analyzing.stage, .analyzing)
        XCTAssertEqual(analyzing.progress, 0.88, accuracy: 0.0001)
        XCTAssertEqual(analyzing.percentage, 88)
    }

    func testValidateSupportedExtension_acceptsConfiguredFormats() {
        XCTAssertNoThrow(try TranscriptionImportService.validate(fileName: "demo.mp3", durationMs: 30_000))
        XCTAssertNoThrow(try TranscriptionImportService.validate(fileName: "demo.mov", durationMs: 30_000))
    }

    func testValidateUnsupportedExtension_throwsFriendlyError() {
        XCTAssertThrowsError(try TranscriptionImportService.validate(fileName: "demo.ogg", durationMs: 30_000)) { error in
            XCTAssertEqual((error as? TranscriptionImportError), .unsupportedFileType)
        }
    }

    func testValidateDurationOverSixMinutes_throwsFriendlyError() {
        XCTAssertThrowsError(try TranscriptionImportService.validate(fileName: "demo.mp4", durationMs: 360_001)) { error in
            XCTAssertEqual((error as? TranscriptionImportError), .durationTooLong)
        }
    }

    func testCompressedUploadExport_withYanyuanFixture() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // swift_ios_host
            .deletingLastPathComponent() // repo root
        let inputURL = repoRoot.appendingPathComponent("yanyuan.mp4")
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw XCTSkip("missing fixture: \(inputURL.path)")
        }

        let outputDir = repoRoot
            .appendingPathComponent("logs")
            .appendingPathComponent("transcription-tests")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outputURL = outputDir.appendingPathComponent("yanyuan-compressed.m4a")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let inBytes = (try FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(inBytes, 0)

        try await TranscriptionMediaDecoder.exportCompressedM4AForRemoteUpload(
            from: inputURL,
            to: outputURL,
            aacBitrate: 96_000
        )

        let outBytes = (try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.intValue ?? 0
        let inMB = Double(inBytes) / 1024.0 / 1024.0
        let outMB = Double(outBytes) / 1024.0 / 1024.0
        print(
            String(
                format: "[TranscriptionTest] input=%d bytes (%.2f MB), output=%d bytes (%.2f MB), outputPath=%@",
                inBytes,
                inMB,
                outBytes,
                outMB,
                outputURL.path
            )
        )
        XCTAssertGreaterThan(outBytes, 0, "compressed output should exist")
        XCTAssertLessThan(outBytes, inBytes, "compressed output should be smaller than source")
    }

    /// 全链路：yanyuan.mp4 → 压缩 m4a → 线上 `POST /api/chord-onnx/transcribe`（需本机可访问公网）
    /// 运行前在**仓库根**创建空文件 ` .chord_remote_e2e`（xcodebuild 不能可靠传入环境变量给测试进程）：
    /// `touch /path/to/guitar-ai-coach/.chord_remote_e2e`
    /// 然后：`-only-testing:SwiftEarHostTests/TranscriptionImportServiceTests/testYanyuanE2E_compressedM4A_remoteTranscribe`
    func testYanyuanE2E_compressedM4A_remoteTranscribe() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let e2eFlag = repoRoot.appendingPathComponent(".chord_remote_e2e")
        guard FileManager.default.fileExists(atPath: e2eFlag.path) else {
            throw XCTSkip("create empty \(e2eFlag.path) to enable remote e2e (see comment above)")
        }

        let inputURL = repoRoot.appendingPathComponent("yanyuan.mp4")
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw XCTSkip("missing fixture: \(inputURL.path)")
        }

        let inBytes = (try FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber)?.intValue ?? 0
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("e2e-yanyuan-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: outURL) }

        let tExport = Date()
        try await TranscriptionMediaDecoder.exportCompressedM4AForRemoteUpload(
            from: inputURL,
            to: outURL,
            aacBitrate: 96_000
        )
        let exportSec = Date().timeIntervalSince(tExport)

        let outFileBytes = (try FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(outFileBytes, 0)

        let t0 = Date()
        let outcome = try await RemoteChordRecognitionService.transcribeAudio(
            fileURL: outURL,
            multipartFilename: "compressed.m4a",
            originalMediaBytes: inBytes
        )
        let wallSec = Date().timeIntervalSince(t0)

        let t = outcome.result.timing
        print(
            String(
                format: "[E2E] exportSec=%.3f uploadFileBytes=%d exportSec+remoteWall=%.3f clientTotal=%.3f uploadSec=%@ " +
                "serverReceive=%.3f serverInfer=%.3f serverTotal=%.3f success=%@ duration=%.2fs key=%@ segs=%d",
                exportSec,
                outFileBytes,
                exportSec + wallSec,
                outcome.clientTotalSeconds,
                outcome.uploadSeconds.map { String(format: "%.3f", $0) } ?? "nil",
                t?.receiveSec ?? -1,
                t?.inferenceSec ?? -1,
                t?.totalSec ?? -1,
                String(describing: outcome.result.success),
                outcome.result.duration ?? -1,
                outcome.result.key ?? "nil",
                outcome.result.segments.count
            )
        )

        XCTAssertTrue(outcome.result.success)
        XCTAssertNotNil(outcome.result.duration, "remote should return audio duration")
        XCTAssertGreaterThan(outcome.result.segments.count, 0, "expected chord segments from remote")
    }
}
