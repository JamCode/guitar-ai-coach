import ChordChart
import Chords
import Core
import Practice
import SwiftUI

/// 和弦切换练习：指法图 + 符号；每行最多 4 个；尺寸随容器宽度按比例缩放。
///
/// 使用 `Color.clear.aspectRatio` 先占住「宽 × 高」比例，再在其上 `GeometryReader` 取尺寸，
/// 避免单独把 `GeometryReader` 放在 `VStack` 里时高度未定义导致宽度塌成一条线、指法图缩成点。
struct ChordPracticeDiagramStrip: View {
    let chordSymbols: [String]

    private var widthToHeight: CGFloat {
        1 / ChordSwitchDiagramLayout.heightOverWidthRatio(
            chordCount: chordSymbols.count,
            includeRomanLine: false
        )
    }

    var body: some View {
        Color.clear
            // `Color.clear` 无固有宽度；在 `VStack(alignment: .leading)` 里若不先占满横宽，
            // `aspectRatio` 会按极小宽度解析，GeometryReader 里指法图缩成点而符号仍有 `max(10,…)` 下限。
            .frame(maxWidth: .infinity)
            .aspectRatio(widthToHeight, contentMode: .fit)
            .overlay(
                GeometryReader { geo in
                    let w = max(geo.size.width, 1)
                    let m = ChordSwitchDiagramLayout.metrics(containerWidth: w, includeRomanLine: false)
                    let rowGap = w * ChordSwitchDiagramLayout.rowGapOverWidth
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: m.columnGutter),
                            count: ChordSwitchDiagramLayout.maxColumns
                        ),
                        alignment: .leading,
                        spacing: rowGap
                    ) {
                        ForEach(Array(chordSymbols.enumerated()), id: \.offset) { _, sym in
                            ChordPracticeDiagramCell(symbol: sym, metrics: m)
                        }
                    }
                    .padding(.horizontal, m.outerHorizontalPadding)
                    .padding(.vertical, w * ChordSwitchDiagramLayout.verticalMarginOverWidth)
                    .frame(width: w, height: geo.size.height, alignment: .topLeading)
                }
            )
    }
}

private struct ChordPracticeDiagramCell: View {
    let symbol: String
    let metrics: ChordSwitchDiagramLayout.Metrics

    private var symbolFontSize: CGFloat {
        max(10, metrics.columnWidth * 0.11)
    }

    var body: some View {
        VStack(spacing: metrics.cellVStackSpacing) {
            Group {
                if let entry = ChordChartData.chordChartEntry(symbol: symbol) {
                    ChordDiagramView(frets: entry.frets)
                        .frame(width: metrics.diagramWidth, height: metrics.diagramHeight)
                        .padding(metrics.diagramInnerPadding)
                        .background(SwiftAppTheme.surfaceSoft)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                                .stroke(SwiftAppTheme.line.opacity(0.85), lineWidth: 1)
                        )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                            .fill(SwiftAppTheme.surfaceSoft)
                        Text(AppL10n.t("chord_practice_not_found"))
                            .font(.system(size: max(9, metrics.columnWidth * 0.09)))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(SwiftAppTheme.muted)
                            .padding(metrics.diagramInnerPadding * 0.6)
                    }
                    .frame(width: metrics.placeholderWidth, height: metrics.placeholderHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                            .stroke(SwiftAppTheme.line.opacity(0.85), lineWidth: 1)
                    )
                }
            }

            Text(symbol)
                .font(.system(size: symbolFontSize, weight: .semibold, design: .default))
                .foregroundStyle(SwiftAppTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
