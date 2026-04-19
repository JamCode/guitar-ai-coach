import ChordChart
import Chords
import Core
import SwiftUI

/// 和弦切换练习：横向指法图 + 符号（宿主 App 与 `ChordChartData` 对齐）。
struct ChordPracticeDiagramStrip: View {
    let chordSymbols: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(chordSymbols.enumerated()), id: \.offset) { _, sym in
                    ChordPracticeDiagramCell(symbol: sym)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct ChordPracticeDiagramCell: View {
    let symbol: String

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let entry = ChordChartData.chordChartEntry(symbol: symbol) {
                    ChordDiagramView(frets: entry.frets)
                        .frame(width: 72, height: 92)
                        .padding(6)
                        .background(SwiftAppTheme.surfaceSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(SwiftAppTheme.line.opacity(0.85), lineWidth: 1)
                        )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(SwiftAppTheme.surfaceSoft)
                        Text("无本地指法")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(SwiftAppTheme.muted)
                            .padding(6)
                    }
                    .frame(width: 84, height: 104)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(SwiftAppTheme.line.opacity(0.85), lineWidth: 1)
                    )
                }
            }

            Text(symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.text)
        }
    }
}
