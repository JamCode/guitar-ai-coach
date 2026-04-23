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

    init(entry: TranscriptionHistoryEntry) {
        self.entry = entry
        _vm = StateObject(wrappedValue: TranscriptionPlayerViewModel(entry: entry))
    }

    var body: some View {
        let currentIndex = PlaybackSyncResolver.currentIndex(for: vm.currentTimeMs, segments: entry.segments)
        let currentSegment = currentIndex.flatMap { entry.segments.indices.contains($0) ? entry.segments[$0] : nil }
        let upcomingSegments = PlaybackSyncResolver.upcomingSegments(for: vm.currentTimeMs, segments: entry.segments)

        ScrollView {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.fileName)
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                        .lineLimit(1)
                    Text("原调：\(entry.originalKey)")
                        .font(.subheadline)
                        .foregroundStyle(SwiftAppTheme.muted)
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
                    durationMs: entry.durationMs,
                    currentTimeMs: vm.currentTimeMs,
                    waveformSamples: entry.waveform,
                    onScrubMs: vm.seek
                )

                PlaybackControlsView(
                    currentTimeMs: $vm.currentTimeMs,
                    durationMs: entry.durationMs,
                    isPlaying: vm.isPlaying,
                    onSeek: vm.seek,
                    onTogglePlay: vm.togglePlay
                )

                UpcomingChordsView(segments: upcomingSegments)
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("识别结果")
        .appPageBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { vm.prepareIfNeeded() }
        .onChange(of: vm.isPlaying) { _, isPlaying in
            UIApplication.shared.isIdleTimerDisabled = isPlaying
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            vm.teardown()
        }
        .alert("播放失败", isPresented: $vm.showingPlaybackError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(vm.playbackErrorMessage)
        }
    }
}

@MainActor
final class TranscriptionPlayerViewModel: ObservableObject {
    @Published var currentTimeMs = 0
    @Published var isPlaying = false
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
            playbackErrorMessage = "原始媒体文件不存在，暂时无法播放。"
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
            return
        }
        if currentTimeMs >= max(0, entry.durationMs - 250) {
            seek(0)
        }
        player.play()
        isPlaying = true
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
        isPlaying = false
        currentTimeMs = entry.durationMs
    }
}
