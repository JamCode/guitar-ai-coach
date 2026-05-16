import Foundation

/// 节拍器支持的拍号；与常见练习场景对齐。
public enum MetronomeTimeSignature: String, CaseIterable, Sendable, Identifiable {
    case twoFour = "2/4"
    case threeFour = "3/4"
    case fourFour = "4/4"
    case sixEight = "6/8"

    public var id: String { rawValue }

    /// 每小节显示的拍点数（UI 圆点数量）。
    public var beatsPerMeasure: Int {
        switch self {
        case .twoFour: return 2
        case .threeFour: return 3
        case .fourFour: return 4
        case .sixEight: return 6
        }
    }

    /// 是否为复合拍子（6/8 等）；当前实现仍按「每拍一个 click」驱动，仅用于展示与后续扩展。
    public var isCompound: Bool {
        switch self {
        case .sixEight: return true
        default: return false
        }
    }
}
