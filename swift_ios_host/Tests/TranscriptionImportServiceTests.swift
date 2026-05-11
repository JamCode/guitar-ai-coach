import XCTest
@testable import SwiftEarHost

final class TranscriptionImportServiceTests: XCTestCase {
    func testChordRecognitionProgressMessagesAreLocalOnly() {
        let preparing = TranscriptionProgressState.preparing(0.08)
        XCTAssertEqual(preparing.stage, .preparing)
        XCTAssertEqual(preparing.message, "正在准备音频...")

        let analyzing = TranscriptionProgressState.analyzing()
        XCTAssertEqual(analyzing.stage, .analyzing)
        XCTAssertEqual(analyzing.message, "正在分析和弦...")

        let chart = TranscriptionProgressState.generatingChart()
        XCTAssertEqual(chart.stage, .generatingChart)
        XCTAssertEqual(chart.message, "正在生成参考和弦谱...")
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

    /// 全链路：yanyuan.mp4 → 本地 Core ML 扒歌。
    /// 运行前在仓库根创建空文件 `.chord_local_e2e` 并确保 `ios_chord_model/chordrecognition.mlpackage` 已存在。
    func testYanyuanE2E_localChordRecognition() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let e2eFlag = repoRoot.appendingPathComponent(".chord_local_e2e")
        guard FileManager.default.fileExists(atPath: e2eFlag.path) else {
            throw XCTSkip("create empty \(e2eFlag.path) to enable local chord e2e")
        }

        let inputURL = repoRoot.appendingPathComponent("yanyuan.mp4")
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw XCTSkip("missing fixture: \(inputURL.path)")
        }

        let t0 = Date()
        let decoded = try await TranscriptionMediaDecoder.decode(url: inputURL)
        let result = try await LocalChordRecognitionService(modelURL: nil).transcribe(media: decoded)
        let wallSec = Date().timeIntervalSince(t0)

        print(
            String(
                format: "[E2E] localWall=%.3f duration=%.2fs key=%@ rawSegs=%d displaySegs=%d chartSegs=%d",
                wallSec,
                Double(result.durationMs) / 1000.0,
                result.originalKey,
                result.segments.count,
                result.displaySegments.count,
                result.chordChartSegments.count
            )
        )

        XCTAssertGreaterThan(result.durationMs, 0)
        XCTAssertGreaterThan(result.displaySegments.count, 0, "expected chord segments from local model")
    }
}
