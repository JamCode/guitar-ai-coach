import SwiftUI
import UIKit
import AVFoundation
import Core

enum PlaybackSyncResolver {
    static func currentIndex(for currentTimeMs: Int, segments: [TranscriptionSegment]) -> Int? {
        segments.firstIndex { $0.startMs <= currentTimeMs && currentTimeMs < $0.endMs }
    }

    static func upcomingSegments(
        for currentTimeMs: Int,
        segments: [TranscriptionSegment],
        limit: Int = 5
    ) -> [TranscriptionSegment] {
        guard !segments.isEmpty else { return [] }
        if let idx = currentIndex(for: currentTimeMs, segments: segments) {
            return Array(segments.dropFirst(idx + 1).prefix(limit))
        }
        if let futureIndex = segments.firstIndex(where: { currentTimeMs < $0.startMs }) {
            return Array(segments.dropFirst(futureIndex).prefix(limit))
        }
        return []
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

    var body: some View {
        let currentIndex = PlaybackSyncResolver.currentIndex(for: vm.currentTimeMs, segments: entry.segments)
        let currentSegment = currentIndex.flatMap { entry.segments.indices.contains($0) ? entry.segments[$0] : nil }
        let upcomingSegments = PlaybackSyncResolver.upcomingSegments(for: vm.currentTimeMs, segments: entry.segments, limit: 3)

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

                CurrentChordCard(
                    currentSegment: currentSegment,
                    currentTimeMs: vm.currentTimeMs,
                    durationMs: entry.durationMs
                )

                ChordTimelineView(
                    segments: entry.segments,
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
                    Button("查看完整和弦谱") {
                        showingFullChordChart = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(isPresented: $showingFullChordChart) {
            FullChordChartView(entry: entry, vm: vm)
        }
        .task { vm.prepareIfNeeded() }
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
}
