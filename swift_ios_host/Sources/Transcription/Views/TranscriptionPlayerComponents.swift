import SwiftUI
import Chords
import Core

/// 和弦条时间轴：卡片宽度与片段时长成比例，横向拖动时根据中心刻度换算时间并回调 `onScrubMs`，与波形、Slider 共用 `seek` 即可联动。
private enum ChordRibbonTimeline {
    static func layout(
        segments: [TranscriptionSegment],
        durationMs: Int,
        visibleWidth: CGFloat,
        pagePadding: CGFloat,
        cardMinWidth: CGFloat,
        spacing: CGFloat,
        widthStretch: CGFloat
    ) -> (starts: [CGFloat], widths: [CGFloat], contentWidth: CGFloat) {
        let dur = max(1, durationMs)
        let n = segments.count
        guard n > 0 else { return ([], [], pagePadding * 2) }

        var widths: [CGFloat] = []
        widths.reserveCapacity(n)
        for seg in segments {
            let segDur = max(1, seg.endMs - seg.startMs)
            let w = max(cardMinWidth, CGFloat(segDur) / CGFloat(dur) * visibleWidth * widthStretch)
            widths.append(w)
        }

        var starts: [CGFloat] = []
        starts.reserveCapacity(n)
        var x = pagePadding
        for i in 0 ..< n {
            starts.append(x)
            x += widths[i]
            if i < n - 1 { x += spacing }
        }
        let contentWidth = x + pagePadding
        return (starts, widths, contentWidth)
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

        for i in 0 ..< n {
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

        let x0 = starts[0]
        let xEnd = starts[n - 1] + widths[n - 1]
        let cx = min(max(x, x0), xEnd)

        for i in 0 ..< n {
            let left = starts[i]
            let right = left + widths[i]
            guard cx <= right else { continue }
            let seg = segments[i]
            let w = widths[i]
            guard w > 0 else { return min(max(seg.startMs, 0), max(0, durationMs)) }
            let frac = Double((cx - left) / w)
            let span = max(1, seg.endMs - seg.startMs)
            let t = Double(seg.startMs) + frac * Double(span)
            return min(max(Int(t.rounded()), 0), max(0, durationMs))
        }
        return max(0, durationMs)
    }
}

struct ChordRibbonView: View {
    let segments: [TranscriptionSegment]
    let currentIndex: Int?
    let durationMs: Int
    let currentTimeMs: Int
    let onScrubMs: (Int) -> Void

    @State private var dragAnchorMs: Int?

    /// 与 `ChordRibbonTimeline.layout` 的累计坐标一致：不在卡片之间留缝，避免 scrub 落在「无时间」区间。
    private let cardSpacing: CGFloat = 0
    private let cardMinWidth: CGFloat = 52
    /// 略大于一屏，便于左右拖动浏览全曲。
    private let timelineWidthStretch: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let visibleW = proxy.size.width
            let pagePad = SwiftAppTheme.pagePadding
            let (starts, widths, contentW) = ChordRibbonTimeline.layout(
                segments: segments,
                durationMs: durationMs,
                visibleWidth: visibleW,
                pagePadding: pagePad,
                cardMinWidth: cardMinWidth,
                spacing: cardSpacing,
                widthStretch: timelineWidthStretch
            )

            let xNow = ChordRibbonTimeline.xAtTime(
                currentTimeMs,
                segments: segments,
                starts: starts,
                widths: widths,
                durationMs: durationMs
            )
            let scrollShift = visibleW / 2 - xNow

            ZStack {
                RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous)
                    .fill(SwiftAppTheme.surface)

                if segments.isEmpty {
                    Text("暂无和弦序列")
                        .font(.subheadline)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: cardSpacing) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                            let fingering = ChordFingeringResolver.resolve(segment.chord)
                            let w = idx < widths.count ? widths[idx] : cardMinWidth
                            VStack(spacing: 6) {
                                Text(segment.chord)
                                    .font(.headline)
                                    .foregroundStyle(SwiftAppTheme.text)
                                if let fingering {
                                    ChordDiagramView(frets: fingering.frets)
                                        .frame(width: 34, height: 44)
                                } else {
                                    Text("—")
                                        .font(.caption)
                                        .foregroundStyle(SwiftAppTheme.muted)
                                }
                            }
                            .frame(width: w, height: 84)
                            .background(idx == currentIndex ? SwiftAppTheme.surfaceSoft : SwiftAppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(idx == currentIndex ? SwiftAppTheme.brand : SwiftAppTheme.line, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, pagePad)
                    .offset(x: scrollShift)
                }

                Rectangle()
                    .fill(SwiftAppTheme.brand)
                    .frame(width: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous))
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard !segments.isEmpty, durationMs > 0 else { return }
                        if dragAnchorMs == nil {
                            dragAnchorMs = currentTimeMs
                        }
                        guard let anchorMs = dragAnchorMs else { return }

                        let anchorX = ChordRibbonTimeline.xAtTime(
                            anchorMs,
                            segments: segments,
                            starts: starts,
                            widths: widths,
                            durationMs: durationMs
                        )
                        let newCenterX = anchorX + value.translation.width
                        let nextMs = ChordRibbonTimeline.timeAtX(
                            newCenterX,
                            segments: segments,
                            starts: starts,
                            widths: widths,
                            durationMs: durationMs
                        )
                        onScrubMs(nextMs)
                    }
                    .onEnded { _ in
                        dragAnchorMs = nil
                    }
            )
        }
        .frame(height: 100)
    }
}

struct WaveformView: View {
    let samples: [Double]
    let progress: Double
    let onScrubProgress: (_ progress01: Double) -> Void

    @State private var dragAnchorProgress: Double?

    var body: some View {
        GeometryReader { proxy in
            let values = samples.isEmpty ? Array(repeating: 0.15, count: 48) : samples
            let totalWidth = max(proxy.size.width, CGFloat(values.count) * 6)
            let step = totalWidth / CGFloat(max(values.count - 1, 1))
            let offset = CGFloat(min(max(progress, 0), 1)) * totalWidth
            ZStack {
                RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous)
                    .fill(SwiftAppTheme.surface)
                Canvas { context, size in
                    let midY = size.height / 2
                    for (idx, sample) in values.enumerated() {
                        let x = CGFloat(idx) * step - offset + size.width / 2
                        guard x >= -step, x <= size.width + step else { continue }
                        let amp = CGFloat(min(max(sample, 0), 1)) * size.height * 0.42
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: midY - amp))
                        path.addLine(to: CGPoint(x: x, y: midY + amp))
                        context.stroke(path, with: .color(SwiftAppTheme.muted), lineWidth: 3)
                    }
                }

                Rectangle()
                    .fill(SwiftAppTheme.brand)
                    .frame(width: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous))
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        if dragAnchorProgress == nil {
                            dragAnchorProgress = min(max(progress, 0), 1)
                        }
                        guard let anchor = dragAnchorProgress else { return }
                        guard totalWidth > 0 else { return }

                        let deltaProgress = Double(value.translation.width / totalWidth)
                        let next = min(max(anchor + deltaProgress, 0), 1)
                        onScrubProgress(next)
                    }
                    .onEnded { _ in
                        dragAnchorProgress = nil
                    }
            )
        }
    }
}

struct PlaybackScrubberView: View {
    @Binding var currentTimeMs: Int
    let durationMs: Int
    let isPlaying: Bool
    let onSeek: (Int) -> Void
    let onTogglePlay: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(formatMs(currentTimeMs))
                Spacer()
                Text(formatMs(durationMs))
            }
            .font(.caption)
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

            Button(isPlaying ? "暂停" : "播放", action: onTogglePlay)
            .appPrimaryButton()
        }
    }

    private func formatMs(_ ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
