import Foundation

/// 远程扒歌服务的客户端。将音频文件上传到后端 ONNX 服务，解析返回的和弦识别结果。
enum RemoteChordRecognitionService {
    private static let defaultEndpoint = URL(string: "https://wanghanai.xyz/api/chord-onnx/transcribe")!
    private static let timeoutSeconds = 600.0

    // MARK: - Server Response Models

    private struct RemoteResponse: Decodable {
        let success: Bool
        let duration: Double
        let key: String
        let segments: [RemoteSegment]
        let displaySegments: [RemoteSegment]
        let simplifiedDisplaySegments: [RemoteSegment]
        let chordChartSegments: [RemoteSegment]
        let timingVariants: RemoteTimingVariants?
        let timingVariantStats: RemoteTimingVariantStats?
    }

    private struct RemoteSegment: Decodable {
        let start: Double
        let end: Double
        let chord: String
    }

    private struct RemoteTimingVariants: Decodable {
        let normal: RemoteTimingBundle
        let noAbsorb: RemoteTimingBundle
        let timing: RemoteTimingBundle?
        let timingCompact: RemoteTimingBundle?
        let playableCompact: RemoteTimingBundle?
    }

    private struct RemoteTimingBundle: Decodable {
        let displaySegments: [RemoteSegment]
        let simplifiedDisplaySegments: [RemoteSegment]
        let chordChartSegments: [RemoteSegment]
    }

    private struct RemoteTimingVariantStats: Decodable {
        let normal: RemoteStatsRow
        let noAbsorb: RemoteStatsRow
        let timing: RemoteTimingStatsRow?
        let timingCompact: RemoteCompactStatsRow?
        let playableCompact: RemotePlayableStatsRow?
    }

    private struct RemoteStatsRow: Decodable {
        let displayCount: Int
        let simplifiedCount: Int
        let chartSegmentCount: Int?
    }

    private struct RemoteTimingStatsRow: Decodable {
        let displayCount: Int
        let simplifiedCount: Int
        let chartSegmentCount: Int?
    }

    private struct RemoteCompactStatsRow: Decodable {
        let displayCount: Int
        let simplifiedCount: Int
        let compressedCount: Int?
    }

    private struct RemotePlayableStatsRow: Decodable {
        let displayCount: Int
        let simplifiedCount: Int
        let compressedCount: Int?
        let simplifiedChordNameCount: Int?
    }

    // MARK: - Public API

    /// 上传音频文件并获取和弦识别结果。
    /// - Parameters:
    ///   - fileURL: 本地音频文件 URL（.wav / .mp3 / .m4a）
    ///   - appToken: 服务端 `X-App-Token`（来自 Build Setting `CHORD_ONNX_APP_TOKEN`）
    ///   - progressHandler: 上传进度回调（0.0 ~ 1.0）
    /// - Returns: 解析后的本地结果
    static func transcribeAudio(
        fileURL: URL,
        appToken: String,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> LocalChordRecognitionResult {
        // 构造 multipart form-data
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: fileURL))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: defaultEndpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(appToken, forHTTPHeaderField: "X-App-Token")
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        request.timeoutInterval = timeoutSeconds

        // 写入临时文件以实现上传进度追踪
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("upload_\(UUID().uuidString).dat")
        try body.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let session = URLSession(configuration: .default, delegate: UploadProgressDelegate(progressHandler: progressHandler), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.upload(for: request, fromFile: tempFile)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionImportError.noStableChordDetected
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw RemoteError.unauthorized
        case 503:
            throw RemoteError.serviceUnavailable
        default:
            throw RemoteError.httpError(httpResponse.statusCode)
        }

        let remote = try JSONDecoder().decode(RemoteResponse.self, from: data)
        guard remote.success else {
            throw RemoteError.invalidResponse
        }

        return mapToLocal(remote, originalFileURL: fileURL)
    }

    // MARK: - Mapping

    private static func mapToLocal(_ remote: RemoteResponse, originalFileURL: URL) -> LocalChordRecognitionResult {
        let durationMs = Int((remote.duration * 1000).rounded())

        let segments = remote.segments.map { mapSegment($0) }
        let displaySegments = remote.displaySegments.map { mapSegment($0) }
        let chartSegments = remote.chordChartSegments.map { mapSegment($0) }

        let variants = mapTimingVariants(remote.timingVariants) ?? TranscriptionTimingVariants(
            normal: .init(displaySegments: [], simplifiedDisplaySegments: [], chordChartSegments: []),
            noAbsorb: .init(displaySegments: [], simplifiedDisplaySegments: [], chordChartSegments: []),
            timing: nil,
            timingCompact: nil,
            playableCompact: nil
        )
        let stats = mapTimingVariantStats(remote.timingVariantStats) ?? TranscriptionTimingVariantStats(
            normal: .init(displayCount: 0, simplifiedCount: 0, chordChartCount: 0),
            noAbsorb: .init(displayCount: 0, simplifiedCount: 0, chordChartCount: 0),
            timing: nil,
            timingCompact: nil,
            playableCompact: nil
        )

        return LocalChordRecognitionResult(
            durationMs: durationMs,
            originalKey: remote.key,
            segments: segments,
            displaySegments: displaySegments,
            chordChartSegments: chartSegments,
            timingVariants: variants,
            timingVariantStats: stats
        )
    }

    private static func mapSegment(_ s: RemoteSegment) -> TranscriptionSegment {
        TranscriptionSegment(
            startMs: Int((s.start * 1000).rounded()),
            endMs: Int((s.end * 1000).rounded()),
            chord: s.chord
        )
    }

    private static func mapTimingVariants(_ remote: RemoteTimingVariants?) -> TranscriptionTimingVariants? {
        guard let remote else { return nil }
        return TranscriptionTimingVariants(
            normal: mapBundle(remote.normal),
            noAbsorb: mapBundle(remote.noAbsorb),
            timing: remote.timing.map { mapBundle($0) },
            timingCompact: remote.timingCompact.map { mapBundle($0) },
            playableCompact: remote.playableCompact.map { mapBundle($0) }
        )
    }

    private static func mapBundle(_ bundle: RemoteTimingBundle) -> TranscriptionTimingVariantBundle {
        TranscriptionTimingVariantBundle(
            displaySegments: bundle.displaySegments.map { mapSegment($0) },
            simplifiedDisplaySegments: bundle.simplifiedDisplaySegments.map { mapSegment($0) },
            chordChartSegments: bundle.chordChartSegments.map { mapSegment($0) }
        )
    }

    private static func mapTimingVariantStats(_ remote: RemoteTimingVariantStats?) -> TranscriptionTimingVariantStats? {
        guard let remote else { return nil }
        return TranscriptionTimingVariantStats(
            normal: .init(displayCount: remote.normal.displayCount, simplifiedCount: remote.normal.simplifiedCount, chordChartCount: remote.normal.chartSegmentCount ?? 0),
            noAbsorb: .init(displayCount: remote.noAbsorb.displayCount, simplifiedCount: remote.noAbsorb.simplifiedCount, chordChartCount: remote.noAbsorb.chartSegmentCount ?? 0),
            timing: remote.timing.map { .init(displayCount: $0.displayCount, simplifiedCount: $0.simplifiedCount, chordChartCount: $0.chartSegmentCount ?? 0, absorbedCount: 0, keptShortCount: 0, snappedBoundaryCount: 0) },
            timingCompact: remote.timingCompact.map { .init(displayCount: $0.displayCount, simplifiedCount: $0.simplifiedCount, chordChartCount: 0, compressedCount: $0.compressedCount ?? 0, preservedTransitionCount: 0) },
            playableCompact: remote.playableCompact.map { .init(displayCount: $0.displayCount, simplifiedCount: $0.simplifiedCount, chordChartCount: 0, compressedCount: $0.compressedCount ?? 0, simplifiedChordNameCount: $0.simplifiedChordNameCount ?? 0, preservedTransitionCount: 0, targetDensityAppliedCount: 0) }
        )
    }

    // MARK: - Errors

    enum RemoteError: LocalizedError, Equatable {
        case unauthorized
        case serviceUnavailable
        case httpError(Int)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "服务认证失败，请联系开发者"
            case .serviceUnavailable:
                return "扒歌服务暂不可用，请稍后再试"
            case .httpError(let code):
                return "服务器错误 (\(code))，请稍后再试"
            case .invalidResponse:
                return "服务器返回数据异常，请稍后再试"
            }
        }
    }
}

// MARK: - Upload Progress Delegate

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    let progressHandler: (@Sendable (Double) -> Void)?

    init(progressHandler: (@Sendable (Double) -> Void)?) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        progressHandler?(min(1.0, max(0.0, fraction)))
    }
}
