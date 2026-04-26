import SwiftUI
import Core

struct FullChordChartView: View {
    let entry: TranscriptionHistoryEntry

    private var sortedSegments: [TranscriptionSegment] {
        entry.segments.sorted { lhs, rhs in
            if lhs.startMs == rhs.startMs { return lhs.endMs < rhs.endMs }
            return lhs.startMs < rhs.startMs
        }
    }

    private var rows: [[TranscriptionSegment]] {
        stride(from: 0, to: sortedSegments.count, by: 4).map { start in
            Array(sortedSegments[start..<min(start + 4, sortedSegments.count)])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(SwiftAppTheme.text)
                        .lineLimit(1)
                    Text("原调：\(entry.originalKey)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.brand)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(SwiftAppTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(SwiftAppTheme.line, lineWidth: 1)
                )

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        Text(formatMs(row.first?.startMs ?? 0))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SwiftAppTheme.muted)
                            .frame(width: 44, alignment: .leading)

                        HStack(spacing: 6) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, segment in
                                Text(segment.chord)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(SwiftAppTheme.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .padding(.horizontal, 10)
                                    .frame(height: 34)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(SwiftAppTheme.surfaceSoft)
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(SwiftAppTheme.line, lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .frame(height: 58, alignment: .center)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(SwiftAppTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(SwiftAppTheme.line, lineWidth: 1)
                    )
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("完整和弦谱")
        .navigationBarTitleDisplayMode(.inline)
        .appPageBackground()
    }

    private func formatMs(_ ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
