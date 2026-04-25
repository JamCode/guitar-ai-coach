import SwiftUI
import Chords
import Core

private enum TranscriptionPlayerFormatting {
    static func formatMs(_ ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    static func formatDurationShort(_ ms: Int) -> String {
        let totalSeconds = max(1, Int((Double(ms) / 1000).rounded()))
        if totalSeconds < 60 {
            return String(format: "%02ds", totalSeconds)
        }
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

struct CurrentChordCard: View {
    let currentSegment: TranscriptionSegment?
    let currentTimeMs: Int
    let durationMs: Int

    var body: some View {
        let chord = currentSegment?.chord ?? "—"
        let fingering = currentSegment.flatMap { ChordFingeringResolver.resolve($0.chord) }

        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("当前和弦")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(SwiftAppTheme.brandSoft)
                    )

                Text(chord)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(SwiftAppTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text("\(TranscriptionPlayerFormatting.formatMs(currentTimeMs)) / \(TranscriptionPlayerFormatting.formatMs(durationMs))")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(SwiftAppTheme.muted)
            }

            Spacer(minLength: 12)

            Group {
                if let fingering {
                    ChordDiagramView(frets: fingering.frets)
                        .frame(width: 112, height: 132)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(SwiftAppTheme.surfaceSoft)
                        .overlay(
                            Text("暂无\n指法")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(SwiftAppTheme.muted)
                        )
                        .frame(width: 112, height: 132)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(SwiftAppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
        .shadow(color: SwiftAppTheme.brand.opacity(0.12), radius: 18, x: 0, y: 10)
    }
}

struct ChordTimelineView: View {
    let segments: [TranscriptionSegment]
    let currentIndex: Int?
    let currentTimeMs: Int
    let onScrubMs: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("和弦时间轴")
                .appSectionTitle()

            if segments.isEmpty {
                Text("暂无和弦片段")
                    .font(.footnote)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(SwiftAppTheme.surface)
                    )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(nearbySegments.enumerated()), id: \.offset) { _, item in
                            let isCurrent = item.index == currentIndex
                            Button {
                                onScrubMs(item.segment.startMs)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(TranscriptionPlayerFormatting.formatMs(item.segment.startMs))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(isCurrent ? .white.opacity(0.92) : SwiftAppTheme.muted)
                                    Text(item.segment.chord)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(isCurrent ? .white : SwiftAppTheme.text)
                                        .lineLimit(1)
                                }
                                .frame(width: 92, alignment: .leading)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isCurrent ? SwiftAppTheme.brand : SwiftAppTheme.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isCurrent ? SwiftAppTheme.brand : SwiftAppTheme.line, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var nearbySegments: [(index: Int, segment: TranscriptionSegment)] {
        guard !segments.isEmpty else { return [] }
        let center = currentIndex ?? fallbackIndex
        let start = max(0, center - 2)
        let end = min(segments.count, start + 5)
        let adjustedStart = max(0, end - 5)
        return (adjustedStart..<end).map { idx in
            (index: idx, segment: segments[idx])
        }
    }

    private var fallbackIndex: Int {
        if let firstFuture = segments.firstIndex(where: { currentTimeMs < $0.startMs }) {
            return firstFuture
        }
        return max(0, segments.count - 1)
    }
}

struct PlaybackControlsView: View {
    @Binding var currentTimeMs: Int
    let durationMs: Int
    let isPlaying: Bool
    let onSeek: (Int) -> Void
    let onTogglePlay: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(TranscriptionPlayerFormatting.formatMs(currentTimeMs))
                Spacer()
                Text(TranscriptionPlayerFormatting.formatMs(durationMs))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(SwiftAppTheme.muted)

            Slider(
                value: Binding(
                    get: { Double(currentTimeMs) },
                    set: {
                        let next = Int($0.rounded())
                        currentTimeMs = next
                        onSeek(next)
                    }
                ),
                in: 0...Double(max(durationMs, 1))
            )
            .tint(SwiftAppTheme.brand)

            HStack {
                Button("1.0x") {}
                    .buttonStyle(.bordered)
                    .tint(SwiftAppTheme.brand)

                Spacer()

                Button(action: onTogglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .background(Circle().fill(SwiftAppTheme.brand))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                } label: {
                    Image(systemName: "repeat")
                        .font(.headline.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(SwiftAppTheme.brand)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SwiftAppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
    }
}

struct UpcomingChordsView: View {
    let segments: [TranscriptionSegment]
    let currentTimeMs: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("接下来和弦")
                .appSectionTitle()

            if segments.isEmpty {
                Text("当前已经接近结尾")
                    .font(.footnote)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(SwiftAppTheme.surface)
                    )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(idx == 0 ? "下一个" : "接着")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(SwiftAppTheme.muted)
                                Text(segment.chord)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(SwiftAppTheme.text)
                                    .lineLimit(1)
                                Text(TranscriptionPlayerFormatting.formatDurationShort(max(0, segment.startMs - currentTimeMs)))
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(SwiftAppTheme.brand)
                            }
                            .frame(width: 92, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(idx == 0 ? SwiftAppTheme.surfaceSoft : SwiftAppTheme.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(idx == 0 ? SwiftAppTheme.brand.opacity(0.45) : SwiftAppTheme.line, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }
}
