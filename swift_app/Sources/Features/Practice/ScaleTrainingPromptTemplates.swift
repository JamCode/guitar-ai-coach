import Foundation

// MARK: - 用户可见文案模板（占位符由界面或生成器填充）

/// 音阶训练题目的**字符串模板**（工程化拼接约定）。
public enum ScaleTrainingPromptTemplate {
    /// 主标题行：`【初级】C大调 · 自然大调 · Mi 指型`
    public static let titleLine = "【{level}】{keyDisplay} · {scale} · {pattern}"

    /// 规则行：`弹奏方向：上行。节奏：八分音符。节拍器 60–70 BPM。`
    public static let ruleLine = "弹奏方向：{direction}。节奏：{rhythm}。节拍器 {bpmMin}–{bpmMax} BPM。"

    /// 附加说明行（多条用换行拼接）：`{extraLines}`
    public static let extraBlock = "{extraLines}"

    /// 单步列表行：`六弦 8品 · c3（1）`
    public static let stepLine = "{stringZh} {fret}品 · {pitch}（{degree}）"
}
