import AVFoundation
import SwiftUI
import Core

struct StemSeparationResultView: View {
    let result: StemSeparationResult
    @StateObject private var player = StemTrackPlayer()
    @State private var displayResult: StemSeparationResult
    @State private var showingRenameAlert = false
    @State private var renameText = ""

    init(result: StemSeparationResult) {
        self.result = result
        _displayResult = State(initialValue: result)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                metadataCard
                trackCard(stem: .vocals)
                trackCard(stem: .accompaniment)
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("分轨结果")
        .appPageBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("改名") {
                    renameText = displayResult.displayName
                    showingRenameAlert = true
                }
            }
        }
        .alert("修改记录名称", isPresented: $showingRenameAlert) {
            TextField("例如：周杰伦-晴天", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                Task { await renameResult() }
            }
        } message: {
            Text("修改后会在分轨历史和结果页显示新名称。")
        }
        .onDisappear {
            player.stop()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayResult.displayName)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(SwiftAppTheme.text)
                .lineLimit(1)
            Text("人声/伴奏已保存在本机")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.brand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataRow(title: "时长", value: displayResult.durationText)
            metadataRow(title: "采样率", value: "\(Int(displayResult.sampleRate.rounded())) Hz")
            metadataRow(title: "创建时间", value: displayResult.createdAtText)
        }
        .appCard()
    }

    private func metadataRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(SwiftAppTheme.muted)
            Spacer()
            Text(value)
                .foregroundStyle(SwiftAppTheme.text)
        }
        .font(.subheadline)
    }

    private func trackCard(stem: StemKind) -> some View {
        let path = displayResult.stems[stem] ?? ""
        let url = URL(fileURLWithPath: path)
        let exists = FileManager.default.fileExists(atPath: path)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    player.toggle(stem: stem, url: url)
                } label: {
                    Image(systemName: player.isPlaying(stem) ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(exists ? SwiftAppTheme.brand : SwiftAppTheme.muted)
                }
                .disabled(!exists)
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(stem.title)
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                    Text(exists ? stem.subtitle : "文件不存在")
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                }

                Spacer(minLength: 8)

                if exists {
                    ShareLink(item: url, preview: SharePreview("\(displayResult.displayName)-\(stem.title)")) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(SwiftAppTheme.brand)
                    }
                }
            }

            StemPlaybackControls(
                stem: stem,
                url: url,
                exists: exists,
                duration: max(Double(displayResult.durationMs) / 1000.0, player.duration),
                currentTime: player.activeStem == stem ? player.currentTime : 0,
                playbackRate: player.playbackRate,
                isActive: player.activeStem == stem,
                onSeek: { player.seek(stem: stem, url: url, to: $0) },
                onRateChange: player.setPlaybackRate
            )
        }
        .appCard()
    }

    private func renameResult() async {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("stem_separation", isDirectory: true)
        else { return }
        try? await StemSeparationStore(rootURL: root).rename(id: displayResult.id, customName: trimmed)
        displayResult = StemSeparationResult(
            id: displayResult.id,
            fileName: displayResult.fileName,
            customName: trimmed,
            durationMs: displayResult.durationMs,
            sampleRate: displayResult.sampleRate,
            createdAtMs: displayResult.createdAtMs,
            stems: displayResult.stems
        )
    }
}

@MainActor
private final class StemTrackPlayer: ObservableObject {
    @Published private(set) var activeStem: StemKind?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var playbackRate: Float = 1.0
    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    func toggle(stem: StemKind, url: URL) {
        if activeStem == stem, player?.isPlaying == true {
            pause()
            return
        }
        if activeStem != stem || player == nil {
            prepare(stem: stem, url: url)
        }
        guard let player else { return }
        player.enableRate = true
        player.rate = playbackRate
        player.play()
        startProgressTimer()
    }

    func seek(stem: StemKind, url: URL, to seconds: TimeInterval) {
        if activeStem != stem || player == nil {
            prepare(stem: stem, url: url)
        }
        guard let player else { return }
        let clamped = max(0, min(player.duration, seconds))
        player.currentTime = clamped
        currentTime = clamped
        duration = player.duration
    }

    func isPlaying(_ stem: StemKind) -> Bool {
        activeStem == stem && player?.isPlaying == true
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        guard let player else { return }
        player.enableRate = true
        if player.isPlaying {
            player.rate = rate
        }
    }

    private func prepare(stem: StemKind, url: URL) {
        progressTimer?.invalidate()
        progressTimer = nil
        do {
            let next = try AVAudioPlayer(contentsOf: url)
            next.enableRate = true
            next.rate = playbackRate
            next.prepareToPlay()
            player = next
            activeStem = stem
            currentTime = next.currentTime
            duration = next.duration
        } catch {
            stop()
        }
    }

    private func pause() {
        player?.pause()
        progressTimer?.invalidate()
        progressTimer = nil
        if let player {
            currentTime = player.currentTime
            duration = player.duration
        }
    }

    func stop() {
        player?.stop()
        player = nil
        activeStem = nil
        currentTime = 0
        duration = 0
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                self.duration = player.duration
                if !player.isPlaying, player.currentTime >= max(0, player.duration - 0.05) {
                    self.progressTimer?.invalidate()
                    self.progressTimer = nil
                }
            }
        }
    }
}

private struct StemPlaybackControls: View {
    let stem: StemKind
    let url: URL
    let exists: Bool
    let duration: TimeInterval
    let currentTime: TimeInterval
    let playbackRate: Float
    let isActive: Bool
    let onSeek: (TimeInterval) -> Void
    let onRateChange: (Float) -> Void

    private let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StemWaveformPlaceholder(isActive: isActive)

            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { min(max(0, currentTime), max(duration, 0.01)) },
                        set: { onSeek($0) }
                    ),
                    in: 0...max(duration, 0.01)
                )
                .disabled(!exists)

                HStack {
                    Text(formatTime(currentTime))
                    Spacer()
                    Text(formatTime(duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(SwiftAppTheme.muted)
            }

            HStack(spacing: 8) {
                ForEach(speedOptions, id: \.self) { rate in
                    Button {
                        onRateChange(rate)
                    } label: {
                        Text(speedTitle(rate))
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: 42)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isSelected(rate) ? SwiftAppTheme.brand.opacity(0.16) : SwiftAppTheme.surfaceSoft)
                    )
                    .overlay(
                        Capsule()
                            .stroke(isSelected(rate) ? SwiftAppTheme.brand.opacity(0.55) : SwiftAppTheme.line, lineWidth: 1)
                    )
                    .foregroundStyle(isSelected(rate) ? SwiftAppTheme.brand : SwiftAppTheme.text)
                    .disabled(!exists)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(stem.title)播放进度和速度")
    }

    private func isSelected(_ rate: Float) -> Bool {
        abs(playbackRate - rate) < 0.001
    }

    private func speedTitle(_ rate: Float) -> String {
        if rate == 1.0 { return "1x" }
        return String(format: "%.2gx", rate)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct StemWaveformPlaceholder: View {
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<28, id: \.self) { idx in
                Capsule()
                    .fill(isActive ? SwiftAppTheme.brand.opacity(0.75) : SwiftAppTheme.line)
                    .frame(width: 3, height: CGFloat(8 + (idx * 7 % 22)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 34)
        .accessibilityHidden(true)
    }
}

extension StemSeparationResult {
    var displayName: String {
        let custom = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty { return custom }
        let fallback = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "未命名歌曲" : fallback
    }

    var durationText: String {
        let totalSeconds = max(0, Int((Double(durationMs) / 1000.0).rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    var createdAtText: String {
        let date = Date(timeIntervalSince1970: Double(createdAtMs) / 1000.0)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private extension StemKind {
    var title: String {
        switch self {
        case .vocals:
            return "人声"
        case .accompaniment:
            return "伴奏"
        }
    }

    var subtitle: String {
        switch self {
        case .vocals:
            return "提取出的人声音轨"
        case .accompaniment:
            return "去除人声后的伴奏音轨"
        }
    }
}
