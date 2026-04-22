import Foundation

/// 调音器指针在 ±50 cent 刻度条上的归一化位置计算。
///
/// 从 `MeterBar` 内联逻辑独立出来，便于在 `@testable` 单元测试中做纯逻辑回归，
/// 同时保证 UI 与测试共享同一套边界与截断规则（超过 ±50 cent 即贴边显示）。
public enum TunerMeterMetrics {
    public static let rangeCents: Double = 50

    /// 将 cents 偏移映射为 `[0, 1]` 的归一化位置，`0.5` 表示居中。
    /// 超出 ±`rangeCents` 的偏移会被夹紧到端点，避免指针消失在条外。
    public static func normalizedPosition(for cents: Double) -> Double {
        let clamped = min(rangeCents, max(-rangeCents, cents))
        return (clamped + rangeCents) / (2.0 * rangeCents)
    }
}
