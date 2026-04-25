import Core
import Foundation

public protocol IntervalTonePlaying: AnyObject {
    func playAscendingPair(lowMidi: Int, highMidi: Int) async throws
    /// 单音试听（与指板同源 SF2；略短 gate 便于快速多点）。
    func playSinglePreview(midi: Int) async throws
    /// 打断当前由本播放器触发的上行两音 / 单音试听（离开页面或快速重播时调用）。
    func cancelIntervalPlayback()
}

public extension IntervalTonePlaying {
    func cancelIntervalPlayback() {}
}

public final class IntervalTonePlayer: IntervalTonePlaying {
    private let audio: AudioEngineServing
    private let stateLock = NSLock()
    /// 供 `cancelIntervalPlayback()` 精确 `noteOff`，避免共享 `AVAudioUnitSampler` 上「扫掉」其它功能正在用的音。
    private var activeAscendingLow: Int?
    private var activeAscendingHigh: Int?
    private var activePreviewMidi: Int?
    /// 与 `Task.cancel` 并行：视唱页只调用 `cancelIntervalPlayback()` 时也能打断长 `sleep`。
    private var cancelGeneration: Int = 0

    /// 与 `FretboardTonePlayer` 一致：钢弦吉他 SF2 单音。
    private static let sampledVelocity: UInt8 = 100
    private static let sampledGateSec = 1.1
    /// 第一音 gate 结束后再留的空档，再触发第二音（原先正弦两音间仅约 90 ms）。
    private static let silenceAfterFirstGateSec = 0.28
    /// 第二音 note-off 后等待的释音尾，再结束 `playAscendingPair`（用于 UI 解锁「播放」）。
    private static let releaseTailAfterSecondGateSec = 0.22
    private static let previewGateSec = 0.52
    private static let previewTailSec = 0.18

    public init(audio: AudioEngineServing = AudioEngineService.shared) {
        self.audio = audio
    }

    public func cancelIntervalPlayback() {
        stateLock.lock()
        cancelGeneration += 1
        let preview = activePreviewMidi
        let low = activeAscendingLow
        let high = activeAscendingHigh
        activePreviewMidi = nil
        activeAscendingLow = nil
        activeAscendingHigh = nil
        stateLock.unlock()

        if let m = preview {
            audio.stopSampledGuitarNotes(midis: [m])
        }
        if let low, let high {
            audio.stopSampledGuitarNotes(midis: [low, high])
        }
        audio.stopPluckedGuitarVoices()
    }

    public func playAscendingPair(lowMidi: Int, highMidi: Int) async throws {
        #if os(iOS)
        try AppAudioSession.configureSharedForPlaybackAndRecording()
        #endif
        let baseline: Int = {
            stateLock.lock()
            let v = cancelGeneration
            stateLock.unlock()
            return v
        }()
        stateLock.lock()
        activePreviewMidi = nil
        activeAscendingLow = lowMidi
        activeAscendingHigh = highMidi
        stateLock.unlock()
        defer {
            stateLock.lock()
            activeAscendingLow = nil
            activeAscendingHigh = nil
            stateLock.unlock()
        }
        try audio.start()
        try audio.playSampledGuitarNote(
            midi: lowMidi,
            velocity: Self.sampledVelocity,
            gateDurationSec: Self.sampledGateSec
        )
        try await cooperativeSleep(seconds: Self.sampledGateSec + Self.silenceAfterFirstGateSec, baseline: baseline)
        try Task.checkCancellation()
        try audio.playSampledGuitarNote(
            midi: highMidi,
            velocity: Self.sampledVelocity,
            gateDurationSec: Self.sampledGateSec
        )
        try await cooperativeSleep(seconds: Self.sampledGateSec + Self.releaseTailAfterSecondGateSec, baseline: baseline)
    }

    public func playSinglePreview(midi: Int) async throws {
        #if os(iOS)
        try AppAudioSession.configureSharedForPlaybackAndRecording()
        #endif
        let baseline: Int = {
            stateLock.lock()
            let v = cancelGeneration
            stateLock.unlock()
            return v
        }()
        stateLock.lock()
        activeAscendingLow = nil
        activeAscendingHigh = nil
        activePreviewMidi = midi
        stateLock.unlock()
        defer {
            stateLock.lock()
            activePreviewMidi = nil
            stateLock.unlock()
        }
        try audio.start()
        try audio.playSampledGuitarNote(
            midi: midi,
            velocity: Self.sampledVelocity,
            gateDurationSec: Self.previewGateSec
        )
        try await cooperativeSleep(seconds: Self.previewGateSec + Self.previewTailSec, baseline: baseline)
    }

    private func cooperativeSleep(seconds: Double, baseline: Int) async throws {
        guard seconds > 0 else { return }
        let chunkSec = 0.05
        var remaining = seconds
        while remaining > 0 {
            try Task.checkCancellation()
            stateLock.lock()
            let currentGeneration = cancelGeneration
            stateLock.unlock()
            if currentGeneration != baseline {
                throw CancellationError()
            }
            let slice = min(chunkSec, remaining)
            try await Task.sleep(nanoseconds: UInt64(slice * 1_000_000_000))
            remaining -= slice
        }
    }
}
