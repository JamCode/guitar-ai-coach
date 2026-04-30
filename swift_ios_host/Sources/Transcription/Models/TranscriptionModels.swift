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

/// 与后端 `timingVariants.*` 对齐的一组展示用时间轴与和弦谱片段。
struct TranscriptionTimingVariantBundle: Codable, Equatable, Hashable {
    let displaySegments: [TranscriptionSegment]
    let simplifiedDisplaySegments: [TranscriptionSegment]
    let chordChartSegments: [TranscriptionSegment]
}

/// 后端返回的 normal / noAbsorb / timing（踩点优先）变体；旧接口可能缺少 `timing`。
struct TranscriptionTimingVariants: Codable, Equatable, Hashable {
    let normal: TranscriptionTimingVariantBundle
    let noAbsorb: TranscriptionTimingVariantBundle
    let timing: TranscriptionTimingVariantBundle?
    /// 踩点精简：基于 `timing` 的二次压缩；旧接口无该键。
    let timingCompact: TranscriptionTimingVariantBundle?
    /// 可弹精简：面向完整和弦谱可读性，允许更强压缩。
    let playableCompact: TranscriptionTimingVariantBundle?
}

struct TranscriptionTimingVariantStatsRow: Codable, Equatable, Hashable {
    let displayCount: Int
    let simplifiedCount: Int
    let chordChartCount: Int
}

/// `timingVariantStats.timing`：含吸收/保留短段/吸附边界计数。
struct TranscriptionTimingPriorityStatsRow: Codable, Equatable, Hashable {
    let displayCount: Int
    let simplifiedCount: Int
    let chordChartCount: Int
    let absorbedCount: Int
    let keptShortCount: Int
    let snappedBoundaryCount: Int
}

/// `timingVariantStats.timingCompact`：踩点精简统计。
struct TranscriptionTimingCompactStatsRow: Codable, Equatable, Hashable {
    let displayCount: Int
    let simplifiedCount: Int
    let chordChartCount: Int
    let compressedCount: Int
    let preservedTransitionCount: Int
}

/// `timingVariantStats.playableCompact`：可弹精简统计。
struct TranscriptionPlayableCompactStatsRow: Codable, Equatable, Hashable {
    let displayCount: Int
    let simplifiedCount: Int
    let chordChartCount: Int
    let compressedCount: Int
    let simplifiedChordNameCount: Int
    let preservedTransitionCount: Int
    let targetDensityAppliedCount: Int
}

struct TranscriptionTimingVariantStats: Codable, Equatable, Hashable {
    let normal: TranscriptionTimingVariantStatsRow
    let noAbsorb: TranscriptionTimingVariantStatsRow
    /// 踩点优先变体统计；旧后端无该键时为 nil。
    let timing: TranscriptionTimingPriorityStatsRow?
    /// 踩点精简统计；旧后端无该键时为 nil。
    let timingCompact: TranscriptionTimingCompactStatsRow?
    /// 可弹精简统计；旧后端无该键时为 nil。
    let playableCompact: TranscriptionPlayableCompactStatsRow?
}

/// 扒歌结果页 DEBUG：默认 / 原始边界 / 踩点优先 / 踩点精简（不影响音频播放）。
enum TranscriptionChordBoundaryDebugMode: String, CaseIterable, Identifiable, Equatable {
    case normal
    case noAbsorbRawEdges
    case timingPriority
    case timingCompact
    case playableCompact

    var id: String { rawValue }

    var pickerLabel: String {
        switch self {
        case .normal: return "默认"
        case .noAbsorbRawEdges: return "原始边界"
        case .timingPriority: return "踩点优先"
        case .timingCompact: return "踩点精简"
        case .playableCompact: return "可弹精简"
        }
    }

    /// DEBUG 结果页可选边界模式（无 `timing` 变体时不展示「踩点优先」）。
    static func debugPickerModes(for entry: TranscriptionHistoryEntry) -> [TranscriptionChordBoundaryDebugMode] {
        var arr: [TranscriptionChordBoundaryDebugMode] = [.normal, .noAbsorbRawEdges]
        #if DEBUG
        if entry.timingVariants?.timing != nil {
            arr.append(.timingPriority)
        }
        if entry.timingVariants?.timingCompact != nil {
            arr.append(.timingCompact)
        }
        if entry.timingVariants?.playableCompact != nil {
            arr.append(.playableCompact)
        }
        #endif
        return arr
    }
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
            message: "正在生成参考和弦谱..."
        )
    }

    static func completed() -> TranscriptionProgressState {
        TranscriptionProgressState(
            stage: .completed,
            progress: 1.0,
            message: "参考和弦谱生成完成"
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
    /// 用户修订后的参考和弦谱；仅影响参考和弦谱页面。
    let editedChordChartSegments: [TranscriptionSegment]?
    /// 用户修订后的参考和弦谱分行结构；用于保留“不满 4 个和弦也不自动补齐”的布局。
    let editedChordChartRowSizes: [Int]?
    /// 用户最近一次保存参考和弦谱编辑的时间戳（毫秒）。
    let editedAtMs: Int?
    /// 远程 ONNX 返回的 A/B 边界变体；旧数据或本地识别为 nil。
    let timingVariants: TranscriptionTimingVariants?
    /// 与 `timingVariants` 配套的计数统计（可选持久化便于排查）。
    let timingVariantStats: TranscriptionTimingVariantStats?
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
        case editedChordChartSegments
        case editedChordChartRowSizes
        case editedAtMs
        case timingVariants
        case timingVariantStats
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
        editedChordChartSegments: [TranscriptionSegment]? = nil,
        editedChordChartRowSizes: [Int]? = nil,
        editedAtMs: Int? = nil,
        timingVariants: TranscriptionTimingVariants? = nil,
        timingVariantStats: TranscriptionTimingVariantStats? = nil,
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
        self.editedChordChartSegments = editedChordChartSegments
        self.editedChordChartRowSizes = editedChordChartRowSizes
        self.editedAtMs = editedAtMs
        self.timingVariants = timingVariants
        self.timingVariantStats = timingVariantStats
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
        editedChordChartSegments = try c.decodeIfPresent([TranscriptionSegment].self, forKey: .editedChordChartSegments)
        editedChordChartRowSizes = try c.decodeIfPresent([Int].self, forKey: .editedChordChartRowSizes)
        editedAtMs = try c.decodeIfPresent(Int.self, forKey: .editedAtMs)
        timingVariants = try c.decodeIfPresent(TranscriptionTimingVariants.self, forKey: .timingVariants)
        timingVariantStats = try c.decodeIfPresent(TranscriptionTimingVariantStats.self, forKey: .timingVariantStats)
        backend = try c.decodeIfPresent(String.self, forKey: .backend) ?? "local"
        waveform = try c.decodeIfPresent([Double].self, forKey: .waveform) ?? []
    }
}
