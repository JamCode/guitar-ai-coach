import Foundation

/// 和弦切换题目的 UI 文案占位约定（与 `ChordSwitchGenerator` 输出一致时可逐字段替换）。
public enum ChordSwitchPromptTemplate {
    public static let titleLine = "【{level}】和弦切换 · {beatRule} · BPM {bpmMin}–{bpmMax}"

    public static let segmentLine = "第{index}组：{chordsArrow}"

    public static let flatLine = "顺序：{chordsArrow}"

    public static let ruleNoBarre = "开放把位，无大横按。"
    public static let ruleMiniBarre = "含小横按（如 F、Bb 常见按法）。"
    public static let ruleFullBarre = "含大横按 / 封闭 / 高把位与扩展和弦。"
}
