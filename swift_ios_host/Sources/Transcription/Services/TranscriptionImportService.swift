import Foundation

enum TranscriptionImportError: LocalizedError, Equatable {
    case unsupportedFileType
    case durationTooLong
    case audioTrackReadFailed
    case audioExportFailed
    case noStableChordDetected

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "当前只支持 mp3、m4a、wav、aac、mp4、mov"
        case .durationTooLong:
            return "当前只支持 6 分钟以内的文件"
        case .audioTrackReadFailed:
            return "这个文件的音轨读取失败，请换一个文件再试"
        case .audioExportFailed:
            return "导出音频失败，请换一个文件再试"
        case .noStableChordDetected:
            return "这次没能稳定识别出和弦，换一个更清晰的文件再试试"
        }
    }
}

enum TranscriptionImportService {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "mp4", "mov"]
    static let maxDurationMs = 6 * 60 * 1000

    static func validate(fileName: String, durationMs: Int) throws {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw TranscriptionImportError.unsupportedFileType
        }
        guard durationMs <= maxDurationMs else {
            throw TranscriptionImportError.durationTooLong
        }
    }
}
