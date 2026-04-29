import SwiftUI
import UIKit
import AVFoundation
import Core

enum PlaybackSyncResolver {
    static func currentIndex(for currentTimeMs: Int, segments: [TranscriptionSegment]) -> Int? {
        TranscriptionChordResolver.index(at: currentTimeMs, in: segments)
    }

    static func upcomingSegments(
        for currentTimeMs: Int,
        segments: [TranscriptionSegment],
        limit: Int = 5
    ) -> [TranscriptionSegment] {
        guard !segments.isEmpty else { return [] }
        if let idx = TranscriptionChordResolver.index(at: currentTimeMs, in: segments) {
            return Array(segments.dropFirst(idx + 1).prefix(limit))
        }
        if let futureIndex = segments.firstIndex(where: { currentTimeMs < $0.startMs }) {
            return Array(segments.dropFirst(futureIndex).prefix(limit))
        }
        return []
    }
}

enum TranscriptionChordResolver {
    /// 结果页时间轴后处理：默认与历史行为一致；`backendNoShortAbsorptionEdges` 用于已关闭短段吸收的后端变体，避免客户端再次吸收。
    enum DisplayTimelineSanitizer: Equatable {
        case fullClientPipeline
        case backendNoShortAbsorptionEdges
    }

    struct DisplayTuning {
        static let minDisplayChordDurationMs = 500
        static let sameSecondConflictWindowMs = 1000
        static let keepBothThresholdMs = 750
        static let gapToleranceMs = 200
    }

    static func preparedSegments(from raw: [TranscriptionSegment]) -> [TranscriptionSegment] {
        let sorted = raw.sorted { lhs, rhs in
            if lhs.startMs == rhs.startMs { return lhs.endMs < rhs.endMs }
            return lhs.startMs < rhs.startMs
        }
        let filtered = sorted.filter { isValidChord($0.chord) }
        return filtered.isEmpty ? sorted : filtered
    }

    static func makeDisplayChordSegments(
        rawSegments: [TranscriptionSegment],
        sanitizer: DisplayTimelineSanitizer = .fullClientPipeline
    ) -> [TranscriptionSegment] {
        if sanitizer == .backendNoShortAbsorptionEdges {
            return mergeAdjacentSameChords(preparedSegments(from: rawSegments))
        }

        let sorted = rawSegments.sorted { lhs, rhs in
            if lhs.startMs == rhs.startMs { return lhs.endMs < rhs.endMs }
            return lhs.startMs < rhs.startMs
        }
        let validOnly = sorted.filter { isValidChord($0.chord) && $0.endMs > $0.startMs }
        var working = mergeAdjacentSameChords(validOnly)

        var mergedShortCount = 0
        var changed = true
        while changed {
            changed = false
            guard !working.isEmpty else { break }
            var idx = 0
            while idx < working.count {
                let seg = working[idx]
                let dur = seg.endMs - seg.startMs
                if dur >= DisplayTuning.minDisplayChordDurationMs {
                    idx += 1
                    continue
                }
                if let target = mergeTargetIndex(for: idx, in: working) {
                    let targetSeg = working[target]
                    let merged = mergeSegments(seg, targetSeg)
                    let first = min(idx, target)
                    let second = max(idx, target)
                    working[second] = merged
                    working.remove(at: first)
                    changed = true
                    mergedShortCount += 1
                    idx = max(0, first - 1)
                } else {
                    idx += 1
                }
            }
            working = mergeAdjacentSameChords(working)
        }

        let beforeConflict = countSameSecondConflicts(working)
        var sampleBefore: [TranscriptionSegment] = []
        var sampleAfter: [TranscriptionSegment] = []
        let perSecondResolved = resolveSameSecondConflicts(
            segments: working,
            sampleBefore: &sampleBefore,
            sampleAfter: &sampleAfter
        )
        var cleaned = mergeAdjacentSameChords(perSecondResolved)
        cleaned = normalizeMonotonic(segments: cleaned)

        #if DEBUG
        if beforeConflict > 0 || mergedShortCount > 0 {
            print("[TranscriptionDisplaySegments] raw=\(rawSegments.count) display=\(cleaned.count) shortMerged=\(mergedShortCount) sameSecondConflicts=\(beforeConflict)")
            if let b = sampleBefore.first, let a = sampleAfter.first {
                print("[TranscriptionDisplaySegments] before: \(formatDebugSegment(b))")
                print("[TranscriptionDisplaySegments] after:  \(formatDebugSegment(a))")
            }
        }
        #endif

        return cleaned
    }

    static func index(at currentTimeMs: Int, in segments: [TranscriptionSegment], gapToleranceMs: Int = DisplayTuning.gapToleranceMs) -> Int? {
        guard !segments.isEmpty else { return nil }

        if let exact = segments.firstIndex(where: { $0.startMs <= currentTimeMs && currentTimeMs < $0.endMs }) {
            return exact
        }

        if currentTimeMs < segments[0].startMs { return 0 }
        if let last = segments.indices.last, currentTimeMs >= segments[last].endMs { return last }

        if let prev = segments.lastIndex(where: { $0.endMs <= currentTimeMs }),
           let next = segments.indices.dropFirst(prev + 1).first {
            let prevGap = currentTimeMs - segments[prev].endMs
            let nextGap = segments[next].startMs - currentTimeMs
            if prevGap >= 0, nextGap >= 0, min(prevGap, nextGap) <= gapToleranceMs {
                return prevGap <= nextGap ? prev : next
            }
        }
        return nil
    }

    static func nearestValidSegment(at currentTimeMs: Int, in segments: [TranscriptionSegment]) -> TranscriptionSegment? {
        guard !segments.isEmpty else { return nil }
        let idx = index(at: currentTimeMs, in: segments) ?? 0

        if isValidChord(segments[idx].chord) { return segments[idx] }
        if let prev = segments[0...idx].last(where: { isValidChord($0.chord) }) { return prev }
        if idx + 1 < segments.count, let next = segments[(idx + 1)...].first(where: { isValidChord($0.chord) }) { return next }
        return nil
    }

    static func isValidChord(_ chord: String) -> Bool {
        !ChordFingeringResolver.isInvalidChordName(chord)
    }

    static func mergeAdjacentSameChords(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        guard !segments.isEmpty else { return [] }
        var merged: [TranscriptionSegment] = [segments[0]]
        for seg in segments.dropFirst() {
            guard let last = merged.last else {
                merged.append(seg)
                continue
            }
            let sameChord = ChordFingeringResolver.normalizeChordName(last.chord) == ChordFingeringResolver.normalizeChordName(seg.chord)
            let touching = seg.startMs <= last.endMs + DisplayTuning.gapToleranceMs
            if sameChord && touching {
                merged[merged.count - 1] = TranscriptionSegment(
                    startMs: last.startMs,
                    endMs: max(last.endMs, seg.endMs),
                    chord: last.chord
                )
            } else {
                merged.append(seg)
            }
        }
        return merged
    }

    private static func mergeTargetIndex(for idx: Int, in segments: [TranscriptionSegment]) -> Int? {
        let current = segments[idx]
        let prevIdx = idx > 0 ? idx - 1 : nil
        let nextIdx = idx + 1 < segments.count ? idx + 1 : nil

        if let prevIdx, ChordFingeringResolver.normalizeChordName(segments[prevIdx].chord) == ChordFingeringResolver.normalizeChordName(current.chord) {
            return prevIdx
        }
        if let nextIdx, ChordFingeringResolver.normalizeChordName(segments[nextIdx].chord) == ChordFingeringResolver.normalizeChordName(current.chord) {
            return nextIdx
        }

        switch (prevIdx, nextIdx) {
        case let (p?, n?):
            let pDur = segments[p].endMs - segments[p].startMs
            let nDur = segments[n].endMs - segments[n].startMs
            return pDur >= nDur ? p : n
        case let (p?, nil):
            return p
        case let (nil, n?):
            return n
        default:
            return nil
        }
    }

    private static func mergeSegments(_ a: TranscriptionSegment, _ b: TranscriptionSegment) -> TranscriptionSegment {
        let keepChord: String
        if (a.endMs - a.startMs) >= (b.endMs - b.startMs) {
            keepChord = a.chord
        } else {
            keepChord = b.chord
        }
        return TranscriptionSegment(
            startMs: min(a.startMs, b.startMs),
            endMs: max(a.endMs, b.endMs),
            chord: keepChord
        )
    }

    private static func resolveSameSecondConflicts(
        segments: [TranscriptionSegment],
        sampleBefore: inout [TranscriptionSegment],
        sampleAfter: inout [TranscriptionSegment]
    ) -> [TranscriptionSegment] {
        let groups = Dictionary(grouping: segments) { max(0, $0.startMs / DisplayTuning.sameSecondConflictWindowMs) }
        var kept: [TranscriptionSegment] = []
        for key in groups.keys.sorted() {
            let bucket = groups[key]!.sorted { ($0.endMs - $0.startMs) > ($1.endMs - $1.startMs) }
            let uniqueChordCount = Set(bucket.map { ChordFingeringResolver.normalizeChordName($0.chord) }).count
            if uniqueChordCount <= 1 {
                kept.append(contentsOf: bucket)
                continue
            }
            let longOnes = bucket.filter { ($0.endMs - $0.startMs) >= DisplayTuning.keepBothThresholdMs }
            if longOnes.count >= 2 {
                kept.append(contentsOf: longOnes.prefix(1))
            } else if let first = bucket.first {
                if sampleBefore.isEmpty {
                    sampleBefore = bucket
                    sampleAfter = [first]
                }
                kept.append(first)
            }
        }
        return kept.sorted { lhs, rhs in
            if lhs.startMs == rhs.startMs { return lhs.endMs < rhs.endMs }
            return lhs.startMs < rhs.startMs
        }
    }

    private static func normalizeMonotonic(segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        guard !segments.isEmpty else { return [] }
        var normalized: [TranscriptionSegment] = []
        for seg in segments {
            let start = max(seg.startMs, normalized.last?.endMs ?? seg.startMs)
            let end = max(seg.endMs, start + 1)
            if let last = normalized.last, last.startMs == start, last.chord == seg.chord {
                normalized[normalized.count - 1] = TranscriptionSegment(startMs: last.startMs, endMs: max(last.endMs, end), chord: last.chord)
            } else {
                normalized.append(TranscriptionSegment(startMs: start, endMs: end, chord: seg.chord))
            }
        }
        return normalized
    }

    private static func countSameSecondConflicts(_ segments: [TranscriptionSegment]) -> Int {
        let groups = Dictionary(grouping: segments) { max(0, $0.startMs / DisplayTuning.sameSecondConflictWindowMs) }
        return groups.values.reduce(0) { partial, bucket in
            let distinct = Set(bucket.map { ChordFingeringResolver.normalizeChordName($0.chord) }).count
            return partial + (distinct > 1 ? 1 : 0)
        }
    }

    private static func formatDebugSegment(_ segment: TranscriptionSegment) -> String {
        let startSec = Double(segment.startMs) / 1000.0
        let endSec = Double(segment.endMs) / 1000.0
        let duration = Double(segment.endMs - segment.startMs) / 1000.0
        return String(format: "%.2f~%.2f %@ duration %.2fs", startSec, endSec, segment.chord, duration)
    }
}

struct TranscriptionResultView: View {
    let entry: TranscriptionHistoryEntry
    @StateObject private var vm: TranscriptionPlayerViewModel
    @State private var showingFullChordChart = false

    init(entry: TranscriptionHistoryEntry) {
        self.entry = entry
        _vm = StateObject(wrappedValue: TranscriptionPlayerViewModel(entry: entry))
    }

    private var preparedFullChordChartSegments: [TranscriptionSegment] {
        let raw = vm.activeChordChartSource(from: entry)
        let sanitizer = vm.displaySanitizer(for: entry)
        return TranscriptionChordResolver.makeDisplayChordSegments(rawSegments: raw, sanitizer: sanitizer)
    }

    var body: some View {
        let timelineRaw = vm.activeTimelineSegments(from: entry)
        let sanitizer = vm.displaySanitizer(for: entry)
        let prepared = TranscriptionChordResolver.makeDisplayChordSegments(rawSegments: timelineRaw, sanitizer: sanitizer)
        let currentIndex = PlaybackSyncResolver.currentIndex(for: vm.currentTimeMs, segments: prepared)
        let currentSegment = TranscriptionChordResolver.nearestValidSegment(at: vm.currentTimeMs, in: prepared)
        let upcomingSegments = PlaybackSyncResolver.upcomingSegments(for: vm.currentTimeMs, segments: prepared, limit: 3)

        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(SwiftAppTheme.text)
                        .lineLimit(1)
                    Text(String(format: AppL10n.t("transcribe_original_key"), entry.originalKey))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.brand)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(LocalizedStringResource("transcribe_result_disclaimer", bundle: .main))
                    .font(.footnote)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
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

                #if DEBUG
                if entry.timingVariants != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("边界模式")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SwiftAppTheme.muted)
                        Picker(
                            "边界模式",
                            selection: Binding(
                                get: { vm.chordBoundaryDebugMode },
                                set: { vm.chordBoundaryDebugMode = $0 }
                            )
                        ) {
                            ForEach(TranscriptionChordBoundaryDebugMode.debugPickerModes(for: entry), id: \.self) { mode in
                                Text(mode.pickerLabel).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
                #endif

                CurrentChordCard(
                    currentSegment: currentSegment,
                    currentTimeMs: vm.currentTimeMs,
                    durationMs: entry.durationMs
                )

                ChordTimelineView(
                    segments: prepared,
                    currentIndex: currentIndex,
                    currentTimeMs: vm.currentTimeMs,
                    onScrubMs: vm.seek
                )

                PlaybackControlsView(
                    currentTimeMs: $vm.currentTimeMs,
                    durationMs: entry.durationMs,
                    isPlaying: vm.isPlaying,
                    onSeek: vm.seek,
                    onTogglePlay: vm.togglePlay
                )

                UpcomingChordsView(
                    segments: upcomingSegments,
                    currentTimeMs: vm.currentTimeMs,
                    onOpenFullChordChart: { showingFullChordChart = true }
                )
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle(LocalizedStringResource("transcribe_result_title", bundle: .main))
        .appPageBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("查看参考和弦谱") {
                        showingFullChordChart = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(isPresented: $showingFullChordChart) {
            FullChordChartView(entry: entry, vm: vm, preparedChartSegments: preparedFullChordChartSegments)
        }
        .task { vm.prepareIfNeeded() }
        .onReceive(
            vm.$currentTimeMs
                .map { timeMs in
                    TranscriptionChordResolver.index(at: timeMs, in: prepared)
                }
                .removeDuplicates()
        ) { idx in
            #if DEBUG
            if let idx {
                let seg = prepared[idx]
                let normalized = ChordFingeringResolver.normalizeChordName(seg.chord)
                let fingering = ChordFingeringResolver.resolve(seg.chord)
                if !TranscriptionChordResolver.isValidChord(seg.chord) || fingering == nil {
                    let start = max(0, idx - 3)
                    let end = min(prepared.count, idx + 4)
                    let nearby = prepared[start..<end].map { "[\($0.startMs)-\($0.endMs)] \($0.chord)" }.joined(separator: " | ")
                    let rowStart = (idx / 4) * 4
                    let rowEnd = min(prepared.count, rowStart + 4)
                    let row = prepared[rowStart..<rowEnd].map(\.chord).joined(separator: ", ")
                    print("[TranscriptionChordDebug] time=\(vm.currentTimeMs) matched=[\(seg.startMs)-\(seg.endMs)] raw=\(seg.chord) normalized=\(normalized) fingeringKey=\(fingering?.symbol ?? "nil") nearby=\(nearby) row=\(row)")
                }
            } else {
                let nearby = prepared.prefix(3).map { "[\($0.startMs)-\($0.endMs)] \($0.chord)" }.joined(separator: " | ")
                print("[TranscriptionChordDebug] time=\(vm.currentTimeMs) noExactMatch nearby=\(nearby)")
            }
            #endif
        }
        .onChange(of: vm.isPlaying) { _, isPlaying in
            UIApplication.shared.isIdleTimerDisabled = isPlaying
        }
        .onDisappear {
            guard !showingFullChordChart else { return }
            UIApplication.shared.isIdleTimerDisabled = false
            vm.teardown()
        }
        .alert(LocalizedStringResource("transcribe_playback_failed_title", bundle: .main), isPresented: $vm.showingPlaybackError) {
            Button(LocalizedStringResource("button_ok", bundle: .main), role: .cancel) {}
        } message: {
            Text(vm.playbackErrorMessage)
        }
    }
}

@MainActor
final class TranscriptionPlayerViewModel: ObservableObject {
    @Published var currentTimeMs = 0
    @Published var isPlaying = false
    @Published var playbackRate: Double = 1.0
    @Published var isLooping = false
    @Published var showingPlaybackError = false
    @Published var playbackErrorMessage = ""
    /// DEBUG：在默认与 `timingVariants.noAbsorb` 之间切换时间轴/谱面数据源（Release 下不展示入口，属性保持默认）。
    @Published var chordBoundaryDebugMode: TranscriptionChordBoundaryDebugMode = .normal

    private let entry: TranscriptionHistoryEntry
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var didRegisterEndObserver = false
    private var isPrepared = false

    init(entry: TranscriptionHistoryEntry) {
        self.entry = entry
    }

    func prepareIfNeeded() {
        guard !isPrepared else { return }
        guard
            let docsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            let url = TranscriptionMediaPathResolver.resolve(
                storedMediaPath: entry.storedMediaPath,
                docsRoot: docsRoot
            )
        else {
            playbackErrorMessage = AppL10n.t("transcribe_playback_missing_file")
            showingPlaybackError = true
            return
        }

        let player = AVPlayer(url: url)
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            currentTimeMs = Int((time.seconds * 1000).rounded())
        }

        if !didRegisterEndObserver {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePlaybackEnded),
                name: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem
            )
            didRegisterEndObserver = true
        }

        self.player = player
        isPrepared = true
    }

    func togglePlay() {
        guard player != nil else {
            prepareIfNeeded()
            if self.player == nil {
                return
            }
            togglePlay()
            return
        }
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            syncIdleTimer()
            return
        }
        if currentTimeMs >= max(0, entry.durationMs - 250) {
            seek(0)
        }
        player.playImmediately(atRate: Float(playbackRate))
        isPlaying = true
        syncIdleTimer()
    }

    func seek(_ ms: Int) {
        guard let player else { return }
        let clamped = max(0, min(entry.durationMs, ms))
        currentTimeMs = clamped
        let time = CMTime(seconds: Double(clamped) / 1000, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func teardown() {
        player?.pause()
        isPlaying = false
        syncIdleTimer()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        NotificationCenter.default.removeObserver(self)
        didRegisterEndObserver = false
        player = nil
        isPrepared = false
    }

    @objc
    private func handlePlaybackEnded() {
        guard let player else { return }
        if isLooping {
            seek(0)
            player.playImmediately(atRate: Float(playbackRate))
            isPlaying = true
            syncIdleTimer()
            return
        }
        isPlaying = false
        currentTimeMs = entry.durationMs
        syncIdleTimer()
    }

    func cyclePlaybackRate() {
        let options: [Double] = [1.0, 1.25, 1.5]
        guard let idx = options.firstIndex(where: { abs($0 - playbackRate) < 0.001 }) else {
            playbackRate = 1.0
            applyPlaybackRateIfNeeded()
            return
        }
        playbackRate = options[(idx + 1) % options.count]
        applyPlaybackRateIfNeeded()
    }

    func toggleLoop() {
        isLooping.toggle()
    }

    private func applyPlaybackRateIfNeeded() {
        guard isPlaying else { return }
        player?.rate = Float(playbackRate)
    }

    private func syncIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = isPlaying
    }

    func activeTimelineSegments(from entry: TranscriptionHistoryEntry) -> [TranscriptionSegment] {
        switch chordBoundaryDebugMode {
        case .normal:
            return entry.displaySegments.isEmpty ? entry.segments : entry.displaySegments
        case .noAbsorbRawEdges:
            if let no = entry.timingVariants?.noAbsorb, !no.displaySegments.isEmpty {
                return no.displaySegments
            }
            return entry.displaySegments.isEmpty ? entry.segments : entry.displaySegments
        case .timingPriority:
            // 播放高亮 / 当前和弦必须与踩点时间轴一致：只用 display（与后端 simplifiedDisplay 同源），禁止 chordChartSegments（谱面二次吸收会破坏踩点）。
            if let t = entry.timingVariants?.timing, !t.displaySegments.isEmpty {
                return t.displaySegments
            }
            return entry.displaySegments.isEmpty ? entry.segments : entry.displaySegments
        case .timingCompact:
            if let tc = entry.timingVariants?.timingCompact, !tc.displaySegments.isEmpty {
                return tc.displaySegments
            }
            return entry.displaySegments.isEmpty ? entry.segments : entry.displaySegments
        }
    }

    func activeChordChartSource(from entry: TranscriptionHistoryEntry) -> [TranscriptionSegment] {
        switch chordBoundaryDebugMode {
        case .normal:
            return Self.defaultChordChartSource(from: entry)
        case .noAbsorbRawEdges:
            if let no = entry.timingVariants?.noAbsorb {
                if !no.chordChartSegments.isEmpty { return no.chordChartSegments }
                if !no.simplifiedDisplaySegments.isEmpty { return no.simplifiedDisplaySegments }
                if !no.displaySegments.isEmpty { return no.displaySegments }
            }
            return Self.defaultChordChartSource(from: entry)
        case .timingPriority:
            // 完整参考谱允许使用 chordChartSegments（谱面吸收）；与结果页时间轴数据源分离。
            if let t = entry.timingVariants?.timing {
                if !t.chordChartSegments.isEmpty { return t.chordChartSegments }
                if !t.simplifiedDisplaySegments.isEmpty { return t.simplifiedDisplaySegments }
                if !t.displaySegments.isEmpty { return t.displaySegments }
            }
            return Self.defaultChordChartSource(from: entry)
        case .timingCompact:
            if let tc = entry.timingVariants?.timingCompact {
                if !tc.chordChartSegments.isEmpty { return tc.chordChartSegments }
                if !tc.simplifiedDisplaySegments.isEmpty { return tc.simplifiedDisplaySegments }
                if !tc.displaySegments.isEmpty { return tc.displaySegments }
            }
            return Self.defaultChordChartSource(from: entry)
        }
    }

    func displaySanitizer(for entry: TranscriptionHistoryEntry) -> TranscriptionChordResolver.DisplayTimelineSanitizer {
        if chordBoundaryDebugMode == .noAbsorbRawEdges, entry.timingVariants?.noAbsorb != nil {
            return .backendNoShortAbsorptionEdges
        }
        if chordBoundaryDebugMode == .timingPriority, entry.timingVariants?.timing != nil {
            return .backendNoShortAbsorptionEdges
        }
        if chordBoundaryDebugMode == .timingCompact, entry.timingVariants?.timingCompact != nil {
            return .backendNoShortAbsorptionEdges
        }
        return .fullClientPipeline
    }

    private static func defaultChordChartSource(from entry: TranscriptionHistoryEntry) -> [TranscriptionSegment] {
        if !entry.chordChartSegments.isEmpty { return entry.chordChartSegments }
        return entry.displaySegments.isEmpty ? entry.segments : entry.displaySegments
    }
}
