import SwiftUI
import UIKit
import AVFoundation
import Core

enum PlaybackSyncResolver {
    static func currentIndex(for currentTimeMs: Int, segments: [TranscriptionSegment]) -> Int? {
        segments.firstIndex { $0.startMs <= currentTimeMs && currentTimeMs < $0.endMs }
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
        let progress = entry.durationMs > 0 ? Double(vm.currentTimeMs) / Double(entry.durationMs) : 0
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(.headline)
                    .foregroundStyle(SwiftAppTheme.text)
                Text(String(format: AppL10n.t("transcribe_original_key"), entry.originalKey))
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SwiftAppTheme.pagePadding)

            ChordRibbonView(
                segments: entry.segments,
                currentIndex: currentIndex,
                durationMs: entry.durationMs,
                currentTimeMs: vm.currentTimeMs,
                onScrubMs: vm.seek
            )
                .padding(.bottom, 12)

            WaveformView(samples: entry.waveform, progress: progress) { progress01 in
                guard entry.durationMs > 0 else { return }
                let ms = Int((min(max(progress01, 0), 1) * Double(entry.durationMs)).rounded())
                vm.seek(ms)
            }
                .frame(height: 280)
                .padding(.horizontal, SwiftAppTheme.pagePadding)

            PlaybackScrubberView(
                currentTimeMs: $vm.currentTimeMs,
                durationMs: entry.durationMs,
                isPlaying: vm.isPlaying,
                onSeek: vm.seek,
                onTogglePlay: vm.togglePlay
            )
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle(LocalizedStringResource("transcribe_result_title", bundle: .main))
        .appPageBackground()
        .task { vm.prepareIfNeeded() }
        .onChange(of: vm.isPlaying) { _, isPlaying in
            UIApplication.shared.isIdleTimerDisabled = isPlaying
        }
        .onDisappear {
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
        let url = URL(fileURLWithPath: entry.storedMediaPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
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
