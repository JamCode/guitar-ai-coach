import Foundation

enum StemSeparationError: LocalizedError, Equatable {
    case emptyInput
    case invalidConfiguration
    case missingStem(StemKind)
    case modelNotConfigured
    case modelOutputInvalid
    case outputWriteFailed

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "音频内容为空"
        case .invalidConfiguration:
            return "音轨分离配置无效"
        case let .missingStem(stem):
            return "模型未返回 \(stem.rawValue) 音轨"
        case .modelNotConfigured:
            return "本地音轨分离模型尚未配置"
        case .modelOutputInvalid:
            return "本地音轨分离模型输出无效"
        case .outputWriteFailed:
            return "分离音轨写入失败"
        }
    }
}

enum StemKind: String, Codable, CaseIterable, Hashable {
    case vocals
    case accompaniment
}

struct StemSeparationConfiguration: Equatable {
    let targetSampleRate: Double
    let chunkDurationSec: Double
    let overlapRatio: Double
    let stems: [StemKind]

    static let twoStemDefault = StemSeparationConfiguration(
        targetSampleRate: 44_100,
        chunkDurationSec: 512.0 * 1024.0 / 44_100.0,
        overlapRatio: 0.25,
        stems: [.vocals, .accompaniment]
    )
}

struct StemSeparationProgress: Equatable {
    enum Stage: String, Equatable {
        case preparing
        case separating
        case writing
        case completed
    }

    let stage: Stage
    let completedSegments: Int
    let totalSegments: Int

    var fraction: Double {
        guard totalSegments > 0 else { return 0 }
        return min(1, max(0, Double(completedSegments) / Double(totalSegments)))
    }
}

struct StemSeparationResult: Codable, Equatable, Hashable {
    let id: String
    let fileName: String
    let customName: String?
    let durationMs: Int
    let sampleRate: Double
    let createdAtMs: Int
    let stems: [StemKind: String]

    init(
        id: String,
        fileName: String,
        customName: String? = nil,
        durationMs: Int,
        sampleRate: Double,
        createdAtMs: Int,
        stems: [StemKind: String]
    ) {
        self.id = id
        self.fileName = fileName
        self.customName = customName
        self.durationMs = durationMs
        self.sampleRate = sampleRate
        self.createdAtMs = createdAtMs
        self.stems = stems
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case customName
        case durationMs
        case sampleRate
        case createdAtMs
        case stems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        fileName = try c.decode(String.self, forKey: .fileName)
        customName = try c.decodeIfPresent(String.self, forKey: .customName)
        durationMs = try c.decode(Int.self, forKey: .durationMs)
        sampleRate = try c.decode(Double.self, forKey: .sampleRate)
        createdAtMs = try c.decode(Int.self, forKey: .createdAtMs)
        stems = try c.decode([StemKind: String].self, forKey: .stems)
    }
}

struct StemSegmentRange: Equatable {
    let index: Int
    let startSample: Int
    let endSample: Int
}
