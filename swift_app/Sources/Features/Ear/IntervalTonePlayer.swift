import Core
import Foundation

public protocol IntervalTonePlaying: AnyObject {
    func playAscendingPair(lowMidi: Int, highMidi: Int) async throws
    /// 单音试听（与指板同源 SF2；略短 gate 便于快速多点）。
    func playSinglePreview(midi: Int) async throws
    /// 快速点按式预览：极短 gate、不阻断前音、不 sleep，适合逐音试听连续点击。
    func playQuickPreview(midi: Int) async throws
    /// 打断当前由本播放器触发的上行两音 / 单音试听（离开页面或快速重播时调用）。
    func cancelIntervalPlayback()
}

public extension IntervalTonePlaying {
    func cancelIntervalPlayback() {}
}

public extension IntervalTonePlaying {
    func playQuickPreview(midi: Int) async throws {}
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
    /// 单音延音时长。原为 1.1→0.7，再调短至 0.45 让单音测试更紧凑快速。
    private static let sampledGateSec = 0.45
    /// 第一音 gate 结束后再留的空档，再触发第二音。用户反馈 0.06 太短，调至 0.20 让两音间隔清晰。
    private static let silenceAfterFirstGateSec = 0.20
    /// 第二音 note-off 后等待的释音尾，再结束 `playAscendingPair`。用户反馈 0.06 结束突兀，调至 0.15。
    private static let releaseTailAfterSecondGateSec = 0.15
    private static let previewGateSec = 0.35
    private static let previewTailSec = 0.12
    /// 快速预览用 gate：比 `previewGateSec` 更短，适合连续点击逐音试听，听感紧凑不粘连。
    private static let quickPreviewGateSec = 0.22

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

    public func playQuickPreview(midi: Int) async throws {
        // 不重新配置 AVAudioSession（快速点按时避免几十 ms 的 setActive 卡顿）
        // 不停止前一个音，让它的 gate 自然到期释放（避免中断感）
        // 不 sleep，直接返回（避免 Task 阻塞主 actor）
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
            gateDurationSec: Self.quickPreviewGateSec
        )
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
