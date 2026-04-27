import Foundation

struct RawChordFrame: Equatable {
    let startMs: Int
    let endMs: Int
    let chord: String
}

protocol ChordRecognizer {
    func recognize(samples: [Float], sampleRate: Double) async throws -> (frames: [RawChordFrame], originalKey: String)
}

struct TranscriptionResultPayload: Equatable {
    let fileName: String
    let durationMs: Int
    let originalKey: String
    let segments: [TranscriptionSegment]
    let waveform: [Double]
}

enum TranscriptionEngine {
    static func mergeSegments(_ raw: [RawChordFrame]) -> [TranscriptionSegment] {
        guard var current = raw.first else {
            return []
        }

        var merged: [TranscriptionSegment] = []
        for frame in raw.dropFirst() {
            if frame.chord == current.chord, frame.startMs == current.endMs {
                current = RawChordFrame(startMs: current.startMs, endMs: frame.endMs, chord: current.chord)
            } else {
                merged.append(
                    TranscriptionSegment(startMs: current.startMs, endMs: current.endMs, chord: current.chord)
                )
                current = frame
            }
        }

        merged.append(TranscriptionSegment(startMs: current.startMs, endMs: current.endMs, chord: current.chord))
        return merged
    }
}

struct TranscriptionOrchestrator {
    let recognizer: ChordRecognizer

    func recognize(
        fileName: String,
        durationMs: Int,
        samples: [Float],
        sampleRate: Double
    ) async throws -> TranscriptionResultPayload {
        let raw = try await recognizer.recognize(samples: samples, sampleRate: sampleRate)
        return TranscriptionResultPayload(
            fileName: fileName,
            durationMs: durationMs,
            originalKey: raw.originalKey,
            segments: TranscriptionEngine.mergeSegments(raw.frames),
            waveform: TranscriptionWaveformService.buildSummary(samples: samples, binCount: 180)
        )
    }
}

enum RemoteChordRecognitionError: LocalizedError {
    case network
    case timeout
    case invalidResponse
    case backendFailed

    var errorDescription: String? {
        switch self {
        case .network, .invalidResponse, .backendFailed:
            return "识别失败，请稍后重试"
        case .timeout:
            return "识别超时，请稍后重试"
        }
    }
}

struct RemoteServerTiming: Decodable, Sendable {
    let receiveSec: Double
    let ingestSec: Double
    let inferenceSec: Double
    let totalSec: Double

    private enum CodingKeys: String, CodingKey {
        case receiveSec = "receive_sec"
        case ingestSec = "ingest_sec"
        case inferenceSec = "inference_sec"
        case totalSec = "total_sec"
    }
}

struct RemoteChordRecognitionResult: Decodable {
    let success: Bool
    let duration: Double?
    let key: String?
    let segments: [RemoteChordSegment]
    let displaySegments: [RemoteChordSegment]
    let simplifiedDisplaySegments: [RemoteChordSegment]?
    let chordChartSegments: [RemoteChordSegment]?
    let timing: RemoteServerTiming?

    private enum CodingKeys: String, CodingKey {
        case success
        case duration
        case key
        case segments
        case displaySegments
        case simplifiedDisplaySegments
        case chordChartSegments
        case timing
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        segments = try c.decodeIfPresent([RemoteChordSegment].self, forKey: .segments) ?? []
        displaySegments = try c.decodeIfPresent([RemoteChordSegment].self, forKey: .displaySegments) ?? []
        simplifiedDisplaySegments = try c.decodeIfPresent([RemoteChordSegment].self, forKey: .simplifiedDisplaySegments)
        chordChartSegments = try c.decodeIfPresent([RemoteChordSegment].self, forKey: .chordChartSegments)
        timing = try c.decodeIfPresent(RemoteServerTiming.self, forKey: .timing)
    }
}

struct RemoteChordTranscribeOutcome: Sendable {
    let result: RemoteChordRecognitionResult
    let originalMediaBytes: Int?
    let uploadFileBytes: Int
    let uploadSeconds: Double?
    let clientTotalSeconds: Double
}

struct RemoteChordSegment: Decodable {
    let start: Double
    let end: Double
    let chord: String

    func toTranscriptionSegment() -> TranscriptionSegment {
        TranscriptionSegment(
            startMs: Int((start * 1000).rounded()),
            endMs: Int((end * 1000).rounded()),
            chord: chord
        )
    }
}

enum RemoteChordRecognitionService {
    static let endpoint = URL(string: "https://wanghanai.xyz/api/chord-onnx/transcribe")!
    static let healthEndpoint = URL(string: "https://wanghanai.xyz/api/chord-onnx/health")!

    /// - Parameters:
    ///   - fileURL: 待上传的音频文件（优先 compressed m4a）。
    ///   - multipartFilename: multipart 中的 filename，服务端仅作记录。
    ///   - originalMediaBytes: 用户所选原始视频/音频文件大小（若可得），用于调试日志。
    static func transcribeAudio(
        fileURL: URL,
        multipartFilename: String = "compressed.m4a",
        originalMediaBytes: Int? = nil,
        onUploadProgress: @escaping @Sendable (Double) -> Void = { _ in },
        onAnalyzingStarted: @escaping @Sendable () -> Void = {}
    ) async throws -> RemoteChordTranscribeOutcome {
        let boundary = "Boundary-\(UUID().uuidString)"
        let audioData = try Data(contentsOf: fileURL)
        let mimeType: String = {
            switch fileURL.pathExtension.lowercased() {
            case "wav": return "audio/wav"
            case "mp3": return "audio/mpeg"
            default: return "audio/m4a"
            }
        }()

        let body = makeMultipartBody(
            boundary: boundary,
            fieldName: "file",
            fileName: multipartFilename,
            mimeType: mimeType,
            fileData: audioData
        )

        let tmpMultipart = FileManager.default.temporaryDirectory
            .appendingPathComponent("chord-multipart-\(UUID().uuidString).dat")
        try Task.checkCancellation()
        try body.write(to: tmpMultipart, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: tmpMultipart)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let appToken = AppSecrets.chordOnnxAppToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !appToken.isEmpty {
            request.setValue(appToken, forHTTPHeaderField: "X-App-Token")
        }
        #if DEBUG
        if appToken.isEmpty {
            print("[RemoteChord] missing CHORD_ONNX_APP_TOKEN build setting; upload may be rejected")
        }
        #endif

        let clientStarted = Date()
        let (data, response, uploadSeconds): (Data, URLResponse, Double?)
        do {
            (data, response, uploadSeconds) = try await MultipartUploadSession.upload(
                request: request,
                multipartBodyFileURL: tmpMultipart,
                onUploadProgress: onUploadProgress,
                onUploadCompleted: onAnalyzingStarted
            )
        } catch let e as URLError {
            if e.code == .cancelled {
                throw CancellationError()
            }
            if e.code == .timedOut {
                throw RemoteChordRecognitionError.timeout
            }
            throw RemoteChordRecognitionError.network
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RemoteChordRecognitionError.network
        }

        let clientTotalSeconds = Date().timeIntervalSince(clientStarted)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RemoteChordRecognitionError.network
        }
        let decoded: RemoteChordRecognitionResult
        do {
            decoded = try JSONDecoder().decode(RemoteChordRecognitionResult.self, from: data)
        } catch {
            throw RemoteChordRecognitionError.invalidResponse
        }
        guard decoded.success else {
            throw RemoteChordRecognitionError.backendFailed
        }

        #if DEBUG
        let t = decoded.timing
        print(
            String(
                format: "[RemoteChord] originalMediaBytes=%@ uploadFileBytes=%d uploadSec=%@ clientTotalSec=%.3f server receive=%.3f ingest=%.3f infer=%.3f total=%.3f",
                originalMediaBytes.map { String($0) } ?? "nil",
                audioData.count,
                uploadSeconds.map { String(format: "%.3f", $0) } ?? "nil",
                clientTotalSeconds,
                t?.receiveSec ?? -1,
                t?.ingestSec ?? -1,
                t?.inferenceSec ?? -1,
                t?.totalSec ?? -1
            )
        )
        #endif

        return RemoteChordTranscribeOutcome(
            result: decoded,
            originalMediaBytes: originalMediaBytes,
            uploadFileBytes: audioData.count,
            uploadSeconds: uploadSeconds,
            clientTotalSeconds: clientTotalSeconds
        )
    }

    /// 首次进入页面时做一次轻量网络预检，尽早触发系统网络授权弹窗（若系统版本会弹）。
    static func preflightNetworkAccess() async {
        var request = URLRequest(url: healthEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 8
        let session = URLSession(configuration: config)
        _ = try? await session.data(for: request)
    }

    private static func makeMultipartBody(
        boundary: String,
        fieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) -> Data {
        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        data.append(fileData)
        data.append("\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }
}

/// 使用 `uploadTask(fromFile:)` 以便拿到真实上传进度；请求体写入临时文件。
private final class MultipartUploadSession: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    private let request: URLRequest
    private let multipartBodyFileURL: URL
    private let continuation: CheckedContinuation<(Data, URLResponse, Double?), Error>
    private let cancellationToken: MultipartUploadCancellationToken
    private let onUploadProgress: @Sendable (Double) -> Void
    private let onUploadCompleted: @Sendable () -> Void

    private var session: URLSession!
    private var responseData = Data()
    private let wallClockStart = Date()
    private var firstBodyByteSentAt: Date?
    private var uploadCompletedAt: Date?
    private var didNotifyUploadCompleted = false
    private var didResumeContinuation = false

    private init(
        request: URLRequest,
        multipartBodyFileURL: URL,
        continuation: CheckedContinuation<(Data, URLResponse, Double?), Error>,
        cancellationToken: MultipartUploadCancellationToken,
        onUploadProgress: @escaping @Sendable (Double) -> Void,
        onUploadCompleted: @escaping @Sendable () -> Void
    ) {
        self.request = request
        self.multipartBodyFileURL = multipartBodyFileURL
        self.continuation = continuation
        self.cancellationToken = cancellationToken
        self.onUploadProgress = onUploadProgress
        self.onUploadCompleted = onUploadCompleted
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.uploadTask(with: request, fromFile: multipartBodyFileURL)
        cancellationToken.set(task)
        task.resume()
    }

    static func upload(
        request: URLRequest,
        multipartBodyFileURL: URL,
        onUploadProgress: @escaping @Sendable (Double) -> Void,
        onUploadCompleted: @escaping @Sendable () -> Void
    ) async throws -> (Data, URLResponse, Double?) {
        let cancellationToken = MultipartUploadCancellationToken()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse, Double?), Error>) in
                _ = MultipartUploadSession(
                    request: request,
                    multipartBodyFileURL: multipartBodyFileURL,
                    continuation: continuation,
                    cancellationToken: cancellationToken,
                    onUploadProgress: onUploadProgress,
                    onUploadCompleted: onUploadCompleted
                )
            }
        } onCancel: {
            cancellationToken.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        if firstBodyByteSentAt == nil, bytesSent > 0 {
            firstBodyByteSentAt = Date()
        }
        if totalBytesExpectedToSend > 0 {
            let fraction = min(1.0, max(0.0, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
            onUploadProgress(fraction)
            if totalBytesSent >= totalBytesExpectedToSend {
                uploadCompletedAt = Date()
                notifyUploadCompletedIfNeeded()
            }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        if let error {
            resume(throwing: error)
            return
        }
        guard let response = task.response else {
            resume(throwing: URLError(.badServerResponse))
            return
        }
        let uploadSeconds: Double?
        if let a = firstBodyByteSentAt, let b = uploadCompletedAt {
            uploadSeconds = b.timeIntervalSince(a)
        } else if let b = uploadCompletedAt {
            uploadSeconds = b.timeIntervalSince(wallClockStart)
        } else {
            uploadSeconds = nil
        }
        resume(returning: (responseData, response, uploadSeconds))
    }

    private func notifyUploadCompletedIfNeeded() {
        guard !didNotifyUploadCompleted else { return }
        didNotifyUploadCompleted = true
        onUploadCompleted()
    }

    private func resume(returning value: (Data, URLResponse, Double?)) {
        guard !didResumeContinuation else { return }
        didResumeContinuation = true
        continuation.resume(returning: value)
    }

    private func resume(throwing error: Error) {
        guard !didResumeContinuation else { return }
        didResumeContinuation = true
        continuation.resume(throwing: error)
    }
}

private final class MultipartUploadCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var isCancelled = false

    func set(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel {
            task.cancel()
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}
