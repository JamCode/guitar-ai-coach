import Foundation

/// 节拍器音色（后续可映射到不同合成参数或采样）。
public enum MetronomeSoundPreset: String, CaseIterable, Sendable, Identifiable {
    case click = "Click"
    case wood = "Wood"

    public var id: String { rawValue }
}

/// 用户可调参数快照；与 `MetronomeEngine` 解耦，便于持久化或注入练习页。
public struct MetronomeConfig: Equatable, Sendable {
    public static let bpmRange = 40...240

    public var bpm: Int
    public var timeSignature: MetronomeTimeSignature
    /// 0...1，映射到输出混音节点音量。
    public var volume: Double
    public var soundPreset: MetronomeSoundPreset

    public init(
        bpm: Int = 100,
        timeSignature: MetronomeTimeSignature = .fourFour,
        volume: Double = 0.85,
        soundPreset: MetronomeSoundPreset = .click
    ) {
        self.bpm = Self.clampBPM(bpm)
        self.timeSignature = timeSignature
        self.volume = Self.clampUnit(volume)
        self.soundPreset = soundPreset
    }

    public static func clampBPM(_ value: Int) -> Int {
        min(bpmRange.upperBound, max(bpmRange.lowerBound, value))
    }

    public static func clampUnit(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    /// 当前 BPM 下相邻两拍之间的时间间隔（秒）。
    public var beatIntervalSeconds: Double {
        60.0 / Double(bpm)
    }
}
