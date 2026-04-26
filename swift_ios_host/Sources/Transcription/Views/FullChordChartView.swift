import SwiftUI
import Core
import Combine

struct FullChordChartView: View {
    let entry: TranscriptionHistoryEntry
    let vm: TranscriptionPlayerViewModel

    @State private var currentSegmentIndex: Int? = nil
    @State private var currentRowIndex: Int? = nil
    @State private var currentChordIndexInRow: Int? = nil

    private let sortedSegments: [TranscriptionSegment]
    private let rows: [[TranscriptionSegment]]

    init(entry: TranscriptionHistoryEntry, vm: TranscriptionPlayerViewModel) {
        self.entry = entry
        self.vm = vm
        let sorted = TranscriptionChordResolver.preparedSegments(from: entry.segments)
        self.sortedSegments = sorted
        self.rows = stride(from: 0, to: sorted.count, by: 4).map { start in
            Array(sorted[start..<min(start + 4, sorted.count)])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                headerCard

                LazyVStack(spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        ChordRowView(
                            rowIndex: rowIndex,
                            row: row,
                            isCurrentRow: rowIndex == currentRowIndex,
                            currentChordIndexInRow: rowIndex == currentRowIndex ? currentChordIndexInRow : nil,
                            onTapRow: {
                                if let first = row.first { vm.seek(first.startMs) }
                            },
                            onTapChord: { seg in
                                vm.seek(seg.startMs)
                            }
                        )
                        .id("row-\(rowIndex)")
                    }
                }
            }
            .padding(SwiftAppTheme.pagePadding)
            .padding(.bottom, 96)
        }
        .onAppear {
            applyHighlight(for: vm.currentTimeMs)
        }
        .onReceive(
            vm.$currentTimeMs
                .map { timeMs in
                    PlaybackSyncResolver.currentIndex(for: timeMs, segments: sortedSegments)
                }
                .removeDuplicates()
        ) { idx in
            currentSegmentIndex = idx
            if let idx {
                currentRowIndex = idx / 4
                currentChordIndexInRow = idx % 4
            } else {
                currentRowIndex = nil
                currentChordIndexInRow = nil
            }
        }
        .navigationTitle("完整和弦谱")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            CompactPlaybackBarHost(vm: vm, durationMs: entry.durationMs)
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }
        .appPageBackground()
    }

    private var headerCard: some View {
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
    }

    private func applyHighlight(for currentTimeMs: Int) {
        let idx = PlaybackSyncResolver.currentIndex(for: currentTimeMs, segments: sortedSegments)
        currentSegmentIndex = idx
        if let idx {
            currentRowIndex = idx / 4
            currentChordIndexInRow = idx % 4
        } else {
            currentRowIndex = nil
            currentChordIndexInRow = nil
        }
    }
}

private struct ChordRowView: View, Equatable {
    let rowIndex: Int
    let row: [TranscriptionSegment]
    let isCurrentRow: Bool
    let currentChordIndexInRow: Int?
    let onTapRow: () -> Void
    let onTapChord: (TranscriptionSegment) -> Void

    static func == (lhs: ChordRowView, rhs: ChordRowView) -> Bool {
        lhs.rowIndex == rhs.rowIndex
            && lhs.row == rhs.row
            && lhs.isCurrentRow == rhs.isCurrentRow
            && lhs.currentChordIndexInRow == rhs.currentChordIndexInRow
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(formatMs(row.first?.startMs ?? 0))
                .font(.caption.monospacedDigit())
                .foregroundStyle(isCurrentRow ? SwiftAppTheme.brand : SwiftAppTheme.muted)
                .frame(width: 44, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(Array(row.enumerated()), id: \.offset) { idx, segment in
                    let isCurrentChord = currentChordIndexInRow == idx
                    Button {
                        onTapChord(segment)
                    } label: {
                        Text(segment.chord)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(isCurrentChord ? .white : SwiftAppTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isCurrentChord ? SwiftAppTheme.brand : (isCurrentRow ? SwiftAppTheme.surfaceSoft.opacity(0.95) : SwiftAppTheme.surfaceSoft))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(isCurrentChord ? SwiftAppTheme.brand : SwiftAppTheme.line, lineWidth: 1)
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
                .fill(SwiftAppTheme.surface.opacity(isCurrentRow ? 0.98 : 0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isCurrentRow ? SwiftAppTheme.brand.opacity(0.5) : SwiftAppTheme.line,
                    lineWidth: isCurrentRow ? 1.3 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTapRow)
    }

    private func formatMs(_ ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct CompactPlaybackBarHost: View {
    @ObservedObject var vm: TranscriptionPlayerViewModel
    let durationMs: Int

    var body: some View {
        CompactPlaybackBar(
            currentTime: vm.currentTimeMs,
            duration: durationMs,
            isPlaying: vm.isPlaying,
            playbackRate: vm.playbackRate,
            isLooping: vm.isLooping,
            onSeek: { vm.seek($0) },
            onPlayPause: { vm.togglePlay() },
            onToggleLoop: { vm.toggleLoop() },
            onChangeRate: { vm.cyclePlaybackRate() }
        )
    }
}

private struct CompactPlaybackBar: View {
    let currentTime: Int
    let duration: Int
    let isPlaying: Bool
    let playbackRate: Double
    let isLooping: Bool
    let onSeek: (Int) -> Void
    let onPlayPause: () -> Void
    let onToggleLoop: () -> Void
    let onChangeRate: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(formatMs(currentTime))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(SwiftAppTheme.muted)
                    .frame(width: 52, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { Double(currentTime) },
                        set: { onSeek(Int($0.rounded())) }
                    ),
                    in: 0...Double(max(duration, 1))
                )
                .tint(SwiftAppTheme.brand)
                .frame(maxWidth: .infinity)

                Text(formatMs(duration))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(SwiftAppTheme.muted)
                    .frame(width: 52, alignment: .trailing)
            }

            HStack {
                Button(String(format: "%.1fx", playbackRate)) {
                    onChangeRate()
                }
                .frame(width: 60, height: 36)
                .buttonStyle(.bordered)
                .tint(SwiftAppTheme.brand)

                Spacer()

                Button {
                    onPlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(SwiftAppTheme.brand))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    onToggleLoop()
                } label: {
                    Image(systemName: "repeat")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(isLooping ? SwiftAppTheme.brand : SwiftAppTheme.muted)
                        .frame(width: 60, height: 36)
                }
                .buttonStyle(.bordered)
                .tint(SwiftAppTheme.brand)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(height: 84)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SwiftAppTheme.surface.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
    }

    private func formatMs(_ ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
