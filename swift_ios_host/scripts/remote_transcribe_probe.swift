import AVFoundation
import Foundation

struct ProbeConfig {
    var endpoint = URL(string: "https://wanghanai.xyz/api/chord-onnx/transcribe")!
    var token = ProcessInfo.processInfo.environment["CHORD_ONNX_APP_TOKEN"] ?? "wang"
    var outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("swift_ios_host/logs/remote-transcribe-probe", isDirectory: true)
    var inputs: [URL] = []
}

enum ProbeError: LocalizedError {
    case usage(String)
    case exportFailed(String)
    case invalidHTTP

    var errorDescription: String? {
        switch self {
        case let .usage(msg), let .exportFailed(msg):
            return msg
        case .invalidHTTP:
            return "invalid HTTP response"
        }
    }
}

struct RemoteServerTiming: Decodable {
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

struct ParsedProbeSummary {
    let success: Bool
    let key: String?
    let segmentCount: Int
    let displayCount: Int
    let chartCount: Int
    let timing: RemoteServerTiming?
}

func parseArgs() throws -> ProbeConfig {
    var config = ProbeConfig()
    var args = Array(CommandLine.arguments.dropFirst())
    while let first = args.first, first.hasPrefix("--") {
        let flag = args.removeFirst()
        switch flag {
        case "--help":
            throw ProbeError.usage(
                """
                Usage:
                  xcrun swift swift_ios_host/scripts/remote_transcribe_probe.swift -- <input.mp4|m4a|wav> [more inputs]

                Options:
                  --endpoint <url>     Remote API endpoint
                  --token <token>      CHORD_ONNX_APP_TOKEN override
                  --out-dir <dir>      Directory for compressed uploads and JSON responses
                  --help               Show this help
                """
            )
        case "--endpoint":
            guard let value = args.first, let url = URL(string: value) else {
                throw ProbeError.usage("missing or invalid value for --endpoint")
            }
            args.removeFirst()
            config.endpoint = url
        case "--token":
            guard let value = args.first else {
                throw ProbeError.usage("missing value for --token")
            }
            args.removeFirst()
            config.token = value
        case "--out-dir":
            guard let value = args.first else {
                throw ProbeError.usage("missing value for --out-dir")
            }
            args.removeFirst()
            let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let pathURL = value.hasPrefix("/") ? URL(fileURLWithPath: value) : base.appendingPathComponent(value)
            config.outputDir = pathURL
        case "--":
            break
        default:
            throw ProbeError.usage("unknown option: \(flag)")
        }
        if flag == "--" { break }
    }

    if let first = args.first, first == "--" {
        args.removeFirst()
    }

    guard !args.isEmpty else {
        throw ProbeError.usage("missing input files. Use --help for usage.")
    }

    config.inputs = args.map { raw in
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return raw.hasPrefix("/") ? URL(fileURLWithPath: raw) : base.appendingPathComponent(raw)
    }
    return config
}

func exportCompressedM4AForRemoteUpload(from sourceURL: URL, to destinationURL: URL) async throws {
    let asset = AVURLAsset(url: sourceURL)
    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
        throw ProbeError.exportFailed("cannot create AppleM4A export session for \(sourceURL.lastPathComponent)")
    }
    let fm = FileManager.default
    if fm.fileExists(atPath: destinationURL.path) {
        try fm.removeItem(at: destinationURL)
    }
    session.outputURL = destinationURL
    session.outputFileType = .m4a
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        session.exportAsynchronously {
            continuation.resume()
        }
    }
    guard session.status == .completed else {
        throw ProbeError.exportFailed(
            "AppleM4A export failed for \(sourceURL.lastPathComponent): \(session.error?.localizedDescription ?? "unknown")"
        )
    }
}

func makeMultipartBody(
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

func sanitizeName(_ raw: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
}

func formatSeconds(_ value: Double?) -> String {
    guard let value else { return "nil" }
    return String(format: "%.3f", value)
}

func jsonValue(_ value: Double?) -> Any {
    guard let value else { return NSNull() }
    return value
}

func parseSummary(from data: Data) -> ParsedProbeSummary? {
    guard
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return nil
    }
    let success = (obj["success"] as? Bool) ?? false
    let key = obj["key"] as? String
    let segmentCount = (obj["segments"] as? [Any])?.count ?? 0
    let displayCount = (obj["displaySegments"] as? [Any])?.count ?? 0
    let chartCount = (obj["chordChartSegments"] as? [Any])?.count ?? 0

    let timing: RemoteServerTiming?
    if let timingObj = obj["timing"],
       JSONSerialization.isValidJSONObject(timingObj),
       let timingData = try? JSONSerialization.data(withJSONObject: timingObj),
       let decoded = try? JSONDecoder().decode(RemoteServerTiming.self, from: timingData) {
        timing = decoded
    } else {
        timing = nil
    }

    return ParsedProbeSummary(
        success: success,
        key: key,
        segmentCount: segmentCount,
        displayCount: displayCount,
        chartCount: chartCount,
        timing: timing
    )
}

func postMultipartBody(
    request: URLRequest,
    multipartBody: Data
) async throws -> (Data, URLResponse, Double?) {
    var request = request
    request.httpBody = multipartBody
    request.setValue(String(multipartBody.count), forHTTPHeaderField: "Content-Length")

    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 600
    config.timeoutIntervalForResource = 600
    let session = URLSession(configuration: config)
    let started = Date()
    let (data, response) = try await session.data(for: request)
    let elapsed = Date().timeIntervalSince(started)
    session.finishTasksAndInvalidate()
    return (data, response, elapsed)
}

func runProbe(config: ProbeConfig) async throws {
    try FileManager.default.createDirectory(at: config.outputDir, withIntermediateDirectories: true)
    var summary: [[String: Any]] = []

    for input in config.inputs {
        let started = Date()
        let stem = sanitizeName(input.deletingPathExtension().lastPathComponent)
        let compressedURL = config.outputDir.appendingPathComponent("\(stem)-compressed.m4a")
        let responseURL = config.outputDir.appendingPathComponent("\(stem).json")

        print("[probe] compressing \(input.lastPathComponent)")
        try await exportCompressedM4AForRemoteUpload(from: input, to: compressedURL)
        let compressedData = try Data(contentsOf: compressedURL)
        print("[probe] upload bytes=\(compressedData.count) file=\(compressedURL.lastPathComponent)")

        let boundary = "Boundary-\(UUID().uuidString)"
        let multipart = makeMultipartBody(
            boundary: boundary,
            fieldName: "file",
            fileName: "compressed.m4a",
            mimeType: "audio/m4a",
            fileData: compressedData
        )
        let multipartURL = config.outputDir.appendingPathComponent("\(stem)-multipart.dat")
        try multipart.write(to: multipartURL, options: .atomic)

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(config.token, forHTTPHeaderField: "X-App-Token")

        print("[probe] upload start...")
        let (data, response, uploadSeconds) = try await postMultipartBody(
            request: request,
            multipartBody: multipart
        )
        guard let http = response as? HTTPURLResponse else {
            throw ProbeError.invalidHTTP
        }
        try data.write(to: responseURL, options: .atomic)
        let wall = Date().timeIntervalSince(started)

        print("[probe] status=\(http.statusCode) total=\(String(format: "%.3f", wall))s upload_call=\(formatSeconds(uploadSeconds))s")

        if let decoded = parseSummary(from: data) {
            print(
                "[probe] success=\(decoded.success) key=\(decoded.key ?? "nil") segs=\(decoded.segmentCount) display=\(decoded.displayCount) chart=\(decoded.chartCount)"
            )
            if let timing = decoded.timing {
                print(
                    "[probe] server receive=\(String(format: "%.3f", timing.receiveSec)) ingest=\(String(format: "%.3f", timing.ingestSec)) infer=\(String(format: "%.3f", timing.inferenceSec)) total=\(String(format: "%.3f", timing.totalSec))"
                )
            }
            summary.append([
                "input": input.path,
                "compressed": compressedURL.path,
                "response": responseURL.path,
                "http_status": http.statusCode,
                "success": decoded.success,
                "segments": decoded.segmentCount,
                "displaySegments": decoded.displayCount,
                "chordChartSegments": decoded.chartCount,
                "wall_sec": wall,
                "upload_sec": jsonValue(uploadSeconds),
            ])
        } else {
            let text = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
            print("[probe] non-json response: \(text.prefix(300))")
            summary.append([
                "input": input.path,
                "compressed": compressedURL.path,
                "response": responseURL.path,
                "http_status": http.statusCode,
                "success": false,
                "wall_sec": wall,
                "upload_sec": jsonValue(uploadSeconds),
            ])
        }
    }

    let summaryURL = config.outputDir.appendingPathComponent("_summary.json")
    let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: summaryURL, options: .atomic)
    print("[probe] summary -> \(summaryURL.path)")
}

do {
    let config = try parseArgs()
    try await runProbe(config: config)
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
