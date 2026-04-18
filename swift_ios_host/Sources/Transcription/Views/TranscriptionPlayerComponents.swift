import SwiftUI
import Chords
import Core

struct ChordRibbonView: View {
    let segments: [TranscriptionSegment]
    let currentIndex: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                        let fingering = ChordFingeringResolver.resolve(segment.chord)
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
                        .frame(width: 64, height: 84)
                        .background(idx == currentIndex ? SwiftAppTheme.surfaceSoft : SwiftAppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(idx == currentIndex ? SwiftAppTheme.brand : SwiftAppTheme.line, lineWidth: 1)
                        )
                        .id(idx)
                    }
                }
                .padding(.horizontal, SwiftAppTheme.pagePadding)
            }
            .onChange(of: currentIndex) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

struct WaveformView: View {
    let samples: [Double]
    let progress: Double

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
