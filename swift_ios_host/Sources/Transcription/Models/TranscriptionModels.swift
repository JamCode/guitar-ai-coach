import Foundation

enum TranscriptionSourceType: String, Codable, Equatable, Hashable {
    case photoLibrary
    case files
}

struct TranscriptionSegment: Codable, Equatable, Hashable {
    let startMs: Int
    let endMs: Int
    let chord: String
}

enum TranscriptionProgressStage: String, Equatable, Sendable {
    case preparing
    case uploading
    case analyzing
    case generatingChart
    case completed
    case failed
}

struct TranscriptionProgressState: Equatable, Sendable {
    let stage: TranscriptionProgressStage
    let progress: Double
    let message: String

    var clampedProgress: Double {
        min(1.0, max(0.0, progress))
    }

    var percentage: Int {
        Int((clampedProgress * 100).rounded())
    }

    var isFailed: Bool {
        stage == .failed
    }

    var isActive: Bool {
        stage != .completed && stage != .failed
    }

    static func preparing(_ progress: Double = 0.0) -> TranscriptionProgressState {
        TranscriptionProgressState(
            stage: .preparing,
            progress: min(0.10, max(0.0, progress)),
            message: "正在准备音频..."
        )
    }

    static func uploading(uploadFraction: Double) -> TranscriptionProgressState {
        let fraction = min(1.0, max(0.0, uploadFraction))
        let uploadPercent = Int((fraction * 100).rounded())
        return TranscriptionProgressState(
            stage: .uploading,
            progress: 0.10 + fraction * 0.35,
            message: "正在上传歌曲 \(uploadPercent)%..."
        )
    }

    static func analyzing(_ progress: Double = 0.45) -> TranscriptionProgressState {
        TranscriptionProgressState(
            stage: .analyzing,
            progress: min(0.88, max(0.45, progress)),
            message: "正在分析和弦..."
        )
    }

    static func generatingChart(_ progress: Double = 0.88) -> TranscriptionProgressState {
        TranscriptionProgressState(
            stage: .generatingChart,
            progress: min(1.0, max(0.88, progress)),
            message: "正在生成和弦谱..."
        )
    }

    static func completed() -> TranscriptionProgressState {
        TranscriptionProgressState(
            stage: .completed,
            progress: 1.0,
            message: "和弦谱生成完成"
        )
    }

    func failed(message: String) -> TranscriptionProgressState {
        TranscriptionProgressState(
            stage: .failed,
            progress: clampedProgress,
            message: message
        )
    }
}

struct TranscriptionHistoryEntry: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let sourceType: TranscriptionSourceType
    let fileName: String
    let customName: String?
    /// 相对 `Documents` 的路径，如 `transcription_media/<uuid>.<ext>`；旧版本可能存绝对路径，读取时用 `TranscriptionMediaPathResolver`。
    let storedMediaPath: String
    let durationMs: Int
    let originalKey: String
    let createdAtMs: Int
    /// Raw segments from backend/local recognizer. Keep for debug only.
    let segments: [TranscriptionSegment]
    /// User-facing segments for result page.
    let displaySegments: [TranscriptionSegment]
    /// User-facing segments for full chord chart.
    let chordChartSegments: [TranscriptionSegment]
    /// Recognition backend source marker. e.g. "remote", "local".
    let backend: String
    let waveform: [Double]

    var displayName: String {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fileName : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceType
        case fileName
        case customName
        case storedMediaPath
        case durationMs
        case originalKey
        case createdAtMs
        case segments
        case displaySegments
        case chordChartSegments
        case backend
        case waveform
    }

    init(
        id: String,
        sourceType: TranscriptionSourceType,
        fileName: String,
        customName: String?,
        storedMediaPath: String,
        durationMs: Int,
        originalKey: String,
        createdAtMs: Int,
        segments: [TranscriptionSegment],
        displaySegments: [TranscriptionSegment],
        chordChartSegments: [TranscriptionSegment],
        backend: String,
        waveform: [Double]
    ) {
        self.id = id
        self.sourceType = sourceType
        self.fileName = fileName
        self.customName = customName
        self.storedMediaPath = storedMediaPath
        self.durationMs = durationMs
        self.originalKey = originalKey
        self.createdAtMs = createdAtMs
        self.segments = segments
        self.displaySegments = displaySegments
        self.chordChartSegments = chordChartSegments
        self.backend = backend
        self.waveform = waveform
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sourceType = try c.decode(TranscriptionSourceType.self, forKey: .sourceType)
        fileName = try c.decode(String.self, forKey: .fileName)
        customName = try c.decodeIfPresent(String.self, forKey: .customName)
        storedMediaPath = try c.decode(String.self, forKey: .storedMediaPath)
        durationMs = try c.decode(Int.self, forKey: .durationMs)
        originalKey = try c.decode(String.self, forKey: .originalKey)
        createdAtMs = try c.decode(Int.self, forKey: .createdAtMs)
        segments = try c.decodeIfPresent([TranscriptionSegment].self, forKey: .segments) ?? []
        let display = try c.decodeIfPresent([TranscriptionSegment].self, forKey: .displaySegments) ?? segments
        displaySegments = display
        chordChartSegments = try c.decodeIfPresent([TranscriptionSegment].self, forKey: .chordChartSegments) ?? display
        backend = try c.decodeIfPresent(String.self, forKey: .backend) ?? "local"
        waveform = try c.decodeIfPresent([Double].self, forKey: .waveform) ?? []
    }
}
