import SwiftUI
import Core

struct FullChordChartView: View {
    let entry: TranscriptionHistoryEntry
    @ObservedObject var vm: TranscriptionPlayerViewModel
    @State private var suppressAutoScrollUntil: Date = .distantPast

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

    private var currentSegmentIndex: Int? {
        PlaybackSyncResolver.currentIndex(for: vm.currentTimeMs, segments: sortedSegments)
    }

    private var currentRowIndex: Int? {
        guard let idx = currentSegmentIndex else { return nil }
        return idx / 4
    }

    var body: some View {
        ScrollViewReader { proxy in
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

                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        let isCurrentRow = rowIndex == currentRowIndex
                        HStack(spacing: 10) {
                            Text(formatMs(row.first?.startMs ?? 0))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(isCurrentRow ? SwiftAppTheme.brand : SwiftAppTheme.muted)
                                .frame(width: 44, alignment: .leading)

                            HStack(spacing: 6) {
                                ForEach(Array(row.enumerated()), id: \.offset) { segOffset, segment in
                                    let globalIndex = rowIndex * 4 + segOffset
                                    let isCurrentSegment = globalIndex == currentSegmentIndex
                                    Button {
                                        vm.seek(segment.startMs)
                                    } label: {
                                        Text(segment.chord)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(isCurrentSegment ? .white : SwiftAppTheme.text)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                            .padding(.horizontal, 10)
                                            .frame(height: 34)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(isCurrentSegment ? SwiftAppTheme.brand : (isCurrentRow ? SwiftAppTheme.surfaceSoft.opacity(0.92) : SwiftAppTheme.surfaceSoft))
                                            )
                                            .overlay(
                                                Capsule(style: .continuous)
                                                    .stroke(isCurrentSegment ? SwiftAppTheme.brand : SwiftAppTheme.line, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
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
                                .stroke(
                                    isCurrentRow ? SwiftAppTheme.brand.opacity(0.55) : SwiftAppTheme.line,
                                    lineWidth: isCurrentRow ? 1.4 : 1
                                )
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let first = row.first {
                                vm.seek(first.startMs)
                            }
                        }
                        .id("row-\(rowIndex)")
                    }
                }
                .padding(SwiftAppTheme.pagePadding)
                .padding(.bottom, 138)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { _ in
                            suppressAutoScrollUntil = Date().addingTimeInterval(2.5)
                        }
                )
            }
            .onChange(of: currentRowIndex) { _, next in
                guard let next else { return }
                guard Date() >= suppressAutoScrollUntil else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("row-\(next)", anchor: .center)
                }
            }
        }
        .navigationTitle("完整和弦谱")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            FullChordChartMiniPlayerBar(vm: vm, durationMs: entry.durationMs)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .background(.clear)
        }
        .appPageBackground()
    }

    private func formatMs(_ ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct FullChordChartMiniPlayerBar: View {
    @ObservedObject var vm: TranscriptionPlayerViewModel
    let durationMs: Int

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(formatMs(vm.currentTimeMs))
                Spacer()
                Text(formatMs(durationMs))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(SwiftAppTheme.muted)

            Slider(
                value: Binding(
                    get: { Double(vm.currentTimeMs) },
                    set: { vm.seek(Int($0.rounded())) }
                ),
                in: 0...Double(max(durationMs, 1))
            )
            .tint(SwiftAppTheme.brand)

            HStack {
                Button(String(format: "%.1fx", vm.playbackRate)) {
                    vm.cyclePlaybackRate()
                }
                .buttonStyle(.bordered)
                .tint(SwiftAppTheme.brand)

                Spacer()

                Button {
                    vm.togglePlay()
                } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(SwiftAppTheme.brand))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    vm.toggleLoop()
                } label: {
                    Image(systemName: "repeat")
                        .font(.headline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(vm.isLooping ? SwiftAppTheme.brand : SwiftAppTheme.muted)
                }
                .buttonStyle(.bordered)
                .tint(SwiftAppTheme.brand)
            }
        }
        .padding(14)
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SwiftAppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
    }

    private func formatMs(_ ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
