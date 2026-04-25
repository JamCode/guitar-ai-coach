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
    let segments: [TranscriptionSegment]
    let waveform: [Double]

    var displayName: String {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fileName : trimmed
    }
}
