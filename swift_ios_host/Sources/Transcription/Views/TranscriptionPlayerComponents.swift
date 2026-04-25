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

private enum ChordTimelinePalette {
    static let colors: [Color] = [
        Color(hex: 0xFF5B6CF0),
        Color(hex: 0xFF2D9CDB),
        Color(hex: 0xFF17B897),
        Color(hex: 0xFFF2A54A),
        Color(hex: 0xFFF15A76),
        Color(hex: 0xFF8B6CFF),
    ]

    static func fill(for index: Int) -> Color {
        colors[index % colors.count]
    }
}

/// 和弦时间轴的几何换算：片段宽度与持续时间成比例，拖动时根据中心刻度换算时间。
private enum ChordTimelineGeometry {
    static func layout(
        segments: [TranscriptionSegment],
        durationMs: Int,
        visibleWidth: CGFloat,
        pagePadding: CGFloat,
        minSegmentWidth: CGFloat,
        widthStretch: CGFloat
    ) -> (starts: [CGFloat], widths: [CGFloat], contentWidth: CGFloat) {
        let dur = max(1, durationMs)
        let n = segments.count
        guard n > 0 else { return ([], [], pagePadding * 2) }

        var rawWidths: [CGFloat] = []
        rawWidths.reserveCapacity(n)
        for seg in segments {
            let segDur = max(1, seg.endMs - seg.startMs)
            rawWidths.append(CGFloat(segDur) / CGFloat(dur) * visibleWidth * widthStretch)
        }
        let minRaw = rawWidths.min() ?? 0
        let scale: CGFloat = (minRaw > 0 && minRaw < minSegmentWidth) ? (minSegmentWidth / minRaw) : 1
        let widths = rawWidths.map { $0 * scale }

        var starts: [CGFloat] = []
        starts.reserveCapacity(n)
        var x = pagePadding
        for width in widths {
            starts.append(x)
            x += width
        }
        return (starts, widths, x + pagePadding)
    }

    static func xAtTime(
        _ ms: Int,
        segments: [TranscriptionSegment],
        starts: [CGFloat],
        widths: [CGFloat],
        durationMs: Int
    ) -> CGFloat {
        let n = segments.count
        guard n > 0, starts.count == n, widths.count == n else { return 0 }
        let t = min(max(ms, 0), max(0, durationMs))

        for i in 0..<n {
            let seg = segments[i]
            if t < seg.startMs {
                return starts[i]
            }
            if t < seg.endMs {
                let denom = max(1, seg.endMs - seg.startMs)
                let frac = CGFloat(min(max(0, t - seg.startMs), denom)) / CGFloat(denom)
                return starts[i] + frac * widths[i]
            }
        }
        return starts[n - 1] + widths[n - 1]
    }

    static func timeAtX(
        _ x: CGFloat,
        segments: [TranscriptionSegment],
        starts: [CGFloat],
        widths: [CGFloat],
        durationMs: Int
    ) -> Int {
        let n = segments.count
        guard n > 0, starts.count == n, widths.count == n else { return 0 }
        let leftBound = starts[0]
        let rightBound = starts[n - 1] + widths[n - 1]
        let clampedX = min(max(x, leftBound), rightBound)

        for i in 0..<n {
            let left = starts[i]
            let right = left + widths[i]
            guard clampedX <= right else { continue }
            let seg = segments[i]
            let span = max(1, seg.endMs - seg.startMs)
            let frac = Double((clampedX - left) / max(widths[i], 1))
            let time = Double(seg.startMs) + frac * Double(span)
            return min(max(Int(time.rounded()), 0), max(0, durationMs))
        }
        return max(0, durationMs)
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
    let durationMs: Int
    let currentTimeMs: Int
    let waveformSamples: [Double]
    let onScrubMs: (Int) -> Void

    @State private var dragAnchorMs: Int?

    private let minSegmentWidth: CGFloat = 52
    private let widthStretch: CGFloat = 1.1
    private let segmentHeight: CGFloat = 46

    var body: some View {
        GeometryReader { proxy in
            let visibleWidth = proxy.size.width
            let pagePadding = SwiftAppTheme.pagePadding
            let metrics = ChordTimelineGeometry.layout(
                segments: segments,
                durationMs: durationMs,
                visibleWidth: visibleWidth,
                pagePadding: pagePadding,
                minSegmentWidth: minSegmentWidth,
                widthStretch: widthStretch
            )
            let xNow = ChordTimelineGeometry.xAtTime(
                currentTimeMs,
                segments: segments,
                starts: metrics.starts,
                widths: metrics.widths,
                durationMs: durationMs
            )
            let scrollShift = visibleWidth / 2 - xNow
            let tickFractions: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
            let tickTimes = tickFractions.map { fraction in
                let screenX = pagePadding + (visibleWidth - pagePadding * 2) * fraction
                let contentX = screenX - scrollShift
                return ChordTimelineGeometry.timeAtX(
                    contentX,
                    segments: segments,
                    starts: metrics.starts,
                    widths: metrics.widths,
                    durationMs: durationMs
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ForEach(Array(tickTimes.enumerated()), id: \.offset) { idx, time in
                        Text(TranscriptionPlayerFormatting.formatMs(time))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(idx == 2 ? SwiftAppTheme.brand : SwiftAppTheme.muted)
                            .frame(maxWidth: .infinity, alignment: idx == 0 ? .leading : (idx == tickTimes.count - 1 ? .trailing : .center))
                    }
                }
                .padding(.horizontal, 2)

                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(SwiftAppTheme.surface)

                    if segments.isEmpty {
                        Text("暂无和弦时间轴")
                            .font(.subheadline)
                            .foregroundStyle(SwiftAppTheme.muted)
                    } else {
                        Canvas { context, size in
                            let values = waveformSamples.isEmpty ? Array(repeating: 0.16, count: 64) : waveformSamples
                            let width = max(metrics.contentWidth - pagePadding * 2, 1)
                            let step = width / CGFloat(max(values.count - 1, 1))
                            let midY = size.height * 0.56
                            for (idx, sample) in values.enumerated() {
                                let x = pagePadding + CGFloat(idx) * step + scrollShift
                                guard x >= -4, x <= size.width + 4 else { continue }
                                let amp = CGFloat(min(max(sample, 0), 1)) * size.height * 0.18
                                var path = Path()
                                path.move(to: CGPoint(x: x, y: midY - amp))
                                path.addLine(to: CGPoint(x: x, y: midY + amp))
                                context.stroke(
                                    path,
                                    with: .color(SwiftAppTheme.muted.opacity(0.22)),
                                    lineWidth: 2
                                )
                            }
                        }

                        ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                            let width = idx < metrics.widths.count ? metrics.widths[idx] : minSegmentWidth
                            let startX = idx < metrics.starts.count ? metrics.starts[idx] : pagePadding
                            let color = ChordTimelinePalette.fill(for: idx)
                            let isCurrent = idx == currentIndex
                            Button {
                                onScrubMs(min(max(segment.startMs, 0), max(0, durationMs)))
                            } label: {
                                Text(segment.chord)
                                    .font(width < 70 ? .caption2.weight(.semibold) : .footnote.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.horizontal, 6)
                            }
                            .buttonStyle(.plain)
                            .frame(width: width, height: segmentHeight)
                            .background(color.opacity(isCurrent ? 0.98 : 0.88))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isCurrent ? SwiftAppTheme.brand : .white.opacity(0.08), lineWidth: isCurrent ? 2 : 1)
                            )
                            .shadow(color: isCurrent ? SwiftAppTheme.brand.opacity(0.22) : .clear, radius: 10, x: 0, y: 6)
                            .offset(x: startX + scrollShift, y: 110)
                        }
                    }

                    Rectangle()
                        .fill(SwiftAppTheme.brand)
                        .frame(width: 2)
                        .shadow(color: SwiftAppTheme.brand.opacity(0.35), radius: 6, x: 0, y: 0)
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            guard !segments.isEmpty, durationMs > 0 else { return }
                            if dragAnchorMs == nil {
                                dragAnchorMs = currentTimeMs
                            }
                            guard let anchorMs = dragAnchorMs else { return }
                            let anchorX = ChordTimelineGeometry.xAtTime(
                                anchorMs,
                                segments: segments,
                                starts: metrics.starts,
                                widths: metrics.widths,
                                durationMs: durationMs
                            )
                            let newCenterX = anchorX - value.translation.width
                            let nextMs = ChordTimelineGeometry.timeAtX(
                                newCenterX,
                                segments: segments,
                                starts: metrics.starts,
                                widths: metrics.widths,
                                durationMs: durationMs
                            )
                            onScrubMs(nextMs)
                        }
                        .onEnded { _ in
                            dragAnchorMs = nil
                        }
                )
            }
        }
        .frame(height: 214)
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
                                Text(TranscriptionPlayerFormatting.formatDurationShort(segment.endMs - segment.startMs))
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
