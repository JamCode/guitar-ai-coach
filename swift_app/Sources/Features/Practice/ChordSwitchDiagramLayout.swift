import CoreGraphics
import Foundation

// MARK: - 和弦指法图网格：尺寸相对容器宽度，适配不同屏宽

/// 和弦切换指法区布局（比例均相对 **容器宽度** 或 **列宽**）。
public enum ChordSwitchDiagramLayout {
    public static let maxColumns = 4

    /// 左右外边距 / 容器宽
    public static let horizontalMarginOverWidth: CGFloat = 0.012
    /// 上下外边距 / 容器宽
    public static let verticalMarginOverWidth: CGFloat = 0.014
    /// 列间距 / 容器宽
    public static let columnGutterOverWidth: CGFloat = 0.026
    /// 行间空隙 / 容器宽
    public static let rowGapOverWidth: CGFloat = 0.032

    /// 网格总高度 ÷ 容器宽（用于外层 `.aspectRatio(1/ratio, ...)`）。
    public static func heightOverWidthRatio(chordCount: Int, includeRomanLine: Bool) -> CGFloat {
        let rows = rowCount(for: chordCount)
        // 不要用 unit width (=1) 推导比例：
        // metrics() 里有 `max(2, innerPad)` 这类绝对下限，unit width 会把比例放大，导致外层高度虚高。
        // 使用接近真实卡片宽度的探测宽，得到稳定且可缩放的高宽比。
        let probeWidth: CGFloat = 360
        let m = metrics(containerWidth: probeWidth, includeRomanLine: includeRomanLine)
        return totalStripHeight(m: m, rows: rows) / probeWidth
    }

    public static func metrics(containerWidth: CGFloat, includeRomanLine: Bool) -> Metrics {
        let w = max(containerWidth, 1)
        let outer = w * horizontalMarginOverWidth
        let gutter = w * columnGutterOverWidth
        let cols = CGFloat(Self.maxColumns)
        let colW = (w - outer * 2 - gutter * (cols - 1)) / cols

        // 指法卡片：图 + 左右 padding 填满列宽
        let diagramW = colW * diagramWidthFractionOfColumn
        let innerPad = (colW - diagramW) / 2
        let diagramH = diagramW * diagramHeightOverWidth
        let corner = max(4, colW * cornerRadiusOverColumn)
        let vGap = colW * cellVStackSpacingOverColumn
        // 行高一律相对容器宽，避免在「单位宽」推演比例时被 `max(11, …)` 放大成错误的高宽比
        let romanH = includeRomanLine ? max(w * 0.028, colW * romanLineHeightOverColumn) : 0
        let symH = max(w * 0.03, colW * symbolLineHeightOverColumn)
        let placeholderW = colW * 0.98
        let placeholderH = colW * placeholderHeightOverColumn

        return Metrics(
            containerWidth: w,
            outerHorizontalPadding: outer,
            columnGutter: gutter,
            columnWidth: colW,
            diagramWidth: diagramW,
            diagramHeight: diagramH,
            diagramInnerPadding: max(2, innerPad),
            cornerRadius: corner,
            cellVStackSpacing: vGap,
            romanLineHeight: romanH,
            symbolLineHeight: symH,
            placeholderWidth: placeholderW,
            placeholderHeight: placeholderH,
            includeRomanLine: includeRomanLine
        )
    }

    public static func totalStripHeight(m: Metrics, rows: Int) -> CGFloat {
        let rowGap = m.containerWidth * rowGapOverWidth
        let vEdge = m.containerWidth * verticalMarginOverWidth * 2
        let romanBlock: CGFloat = m.includeRomanLine ? (m.romanLineHeight + m.cellVStackSpacing * 0.35) : 0
        let rowCore = m.diagramHeight + 2 * m.diagramInnerPadding + m.cellVStackSpacing + romanBlock + m.symbolLineHeight
        return vEdge + CGFloat(rows) * rowCore + CGFloat(max(0, rows - 1)) * rowGap
    }

    private static func rowCount(for chordCount: Int) -> Int {
        max(1, (max(0, chordCount) + maxColumns - 1) / maxColumns)
    }

    /// 指法品格区域宽 / 列宽（与两侧 padding 之和为 1）
    private static let diagramWidthFractionOfColumn: CGFloat = 0.78
    /// 指法图高 / 宽
    private static let diagramHeightOverWidth: CGFloat = 1.32
    private static let cornerRadiusOverColumn: CGFloat = 0.14
    private static let cellVStackSpacingOverColumn: CGFloat = 0.065
    private static let romanLineHeightOverColumn: CGFloat = 0.11
    private static let symbolLineHeightOverColumn: CGFloat = 0.1
    private static let placeholderHeightOverColumn: CGFloat = 1.22

    public struct Metrics: Sendable {
        public let containerWidth: CGFloat
        public let outerHorizontalPadding: CGFloat
        public let columnGutter: CGFloat
        public let columnWidth: CGFloat
        public let diagramWidth: CGFloat
        public let diagramHeight: CGFloat
        public let diagramInnerPadding: CGFloat
        public let cornerRadius: CGFloat
        public let cellVStackSpacing: CGFloat
        public let romanLineHeight: CGFloat
        public let symbolLineHeight: CGFloat
        public let placeholderWidth: CGFloat
        public let placeholderHeight: CGFloat
        public let includeRomanLine: Bool
    }
}
