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
