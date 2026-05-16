import Foundation

/// 按 **6→1 弦绝对品格** 播放和弦：钢弦 SF2 采样，**先分解琶音（低音→高音）**，再 **柱式**。
/// 供「常用和弦」「和弦速查」等共用。
public final class ChordVoicingTonePlayer {
    private let audio: AudioEngineServing
    private let queue = DispatchQueue(label: "guitar-ai-coach.chord-voicing-tone", qos: .userInitiated)
    private var didPrepareAudio = false
    /// 用于取消上一次尚未触发的延迟任务，避免快速连点叠音。
    private var playbackSerial = 0

    /// 与练耳一致的取消代计数器，用于 `playChordFretsAwaitable` 中的
    /// `cooperativeSleep` 早期检测静音请求，避免旧任务 `CancellationError`
    /// catch 块误调 `stopAllSampledGuitarNotes` 杀新音。
    private var cancelGeneration = 0
    private let stateLock = NSLock()

    public init(audio: AudioEngineServing = AudioEngineService.shared) {
        self.audio = audio
    }

    public func prepare() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.didPrepareAudio else { return }
            do {
                #if os(iOS)
                try AppAudioSession.configureSharedForPlaybackAndRecording()
                #endif
                try self.audio.start()
                self.didPrepareAudio = true
            } catch {
                self.didPrepareAudio = false
            }
        }
    }

    /// `frets`：6→1 弦，`-1` 为不发声（与 `ChordDiagramView` / 速查数据一致）。
    public func playChordFrets(_ frets: [Int]) {
        let midis = GuitarStandardTuning.midisFromChordFretsSixToOne(frets)
        guard !midis.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.playbackSerial += 1
            let token = self.playbackSerial
            if !self.didPrepareAudio {
                do {
                    #if os(iOS)
                    try AppAudioSession.configureSharedForPlaybackAndRecording()
                    #endif
                    try self.audio.start()
                    self.didPrepareAudio = true
                } catch {
                    self.didPrepareAudio = false
                    return
                }
            }
            self.scheduleArpeggioThenBlock(midis: midis, token: token)
        }
    }

    /// 与 `playChordFrets` 同一琶音→柱式节奏，但顺序 `await` 至柱式释音尾结束，供练耳等需要与 UI 同步的场景。
    /// 使用 `cooperativeSleep` 代替裸 `Task.sleep`，让旧任务在被 `cancelPlayback` 取消时
    /// 能早期抛出 `CancellationError`，避免 catch 块误杀新音。
    public func playChordFretsAwaitable(_ frets: [Int]) async throws {
        let midis = GuitarStandardTuning.midisFromChordFretsSixToOne(frets)
        guard !midis.isEmpty else { return }
        try audio.start()
        let n = midis.count
        let arpStep = Self.arpStepSec
        let arpGate = Self.arpGateSec
        let pauseAfterArpeggio = Self.pauseAfterArpeggioSec
        let velArp = UInt8(max(74, min(98, 94 - n)))
        let velBlock = UInt8(max(78, min(102, 98 - n * 2)))

        if n == 1 {
            try audio.playSampledGuitarNote(midi: midis[0], velocity: velArp, gateDurationSec: 1.15)
            try await cooperativeSleep(seconds: 1.15 + 0.22)
            return
        }

        for (i, midi) in midis.enumerated() {
            if i > 0 {
                try await cooperativeSleep(seconds: arpStep)
            }
            try audio.playSampledGuitarNote(midi: midi, velocity: velArp, gateDurationSec: arpGate)
        }
        try await cooperativeSleep(seconds: arpGate + pauseAfterArpeggio)
        try audio.playSampledGuitarChord(
            midis: midis,
            velocity: velBlock,
            gateDurationSec: Self.blockGateSec,
            stringStaggerSec: Self.blockStaggerSec
        )
        let staggerSpan = Double(max(0, n - 1)) * Self.blockStaggerSec
        let blockTail = staggerSpan + Self.blockWaitHeadroomSec + Self.blockAudibleTailSec
        try await cooperativeSleep(seconds: blockTail)
    }

    /// 打断当前 `playChordFretsAwaitable` 的执行。
    /// `EarChordPlayer.cancelChordPlayback()` 已调 `stopAllSampledGuitarNotes`，
    /// 此处只需递增代计数器让 `cooperativeSleep` 早期抛出。
    public func cancelAwaitablePlayback() {
        stateLock.lock()
        cancelGeneration += 1
        stateLock.unlock()
    }

    private func cooperativeSleep(seconds: Double) async throws {
        guard seconds > 0 else { return }
        let chunkSec = 0.05
        var remaining = seconds
        let baseline: Int = {
            stateLock.lock()
            let v = cancelGeneration
            stateLock.unlock()
            return v
        }()
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

    private static let arpStepSec = 0.28
    private static let arpGateSec = 0.24
    private static let pauseAfterArpeggioSec = 0.22
    private static let blockGateSec = 1.42
    private static let blockStaggerSec = 0.014
    private static let blockWaitHeadroomSec = 2.75
    private static let blockAudibleTailSec = 0.32

    private func scheduleArpeggioThenBlock(midis: [Int], token: Int) {
        let n = midis.count
        // 分解琶音节奏：步进略长于单音 gate，既留气口又有一点自然交叠。
        let arpStep = Self.arpStepSec
        let arpGate = Self.arpGateSec
        let pauseAfterArpeggio = Self.pauseAfterArpeggioSec
        let velArp = UInt8(max(74, min(98, 94 - n)))
        let velBlock = UInt8(max(78, min(102, 98 - n * 2)))

        if n == 1 {
            queue.asyncAfter(deadline: .now()) { [weak self] in
                guard let self, token == self.playbackSerial else { return }
                try? self.audio.playSampledGuitarNote(midi: midis[0], velocity: velArp, gateDurationSec: 1.15)
            }
            return
        }

        for (i, midi) in midis.enumerated() {
            let delay = Double(i) * arpStep
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, token == self.playbackSerial else { return }
                try? self.audio.playSampledGuitarNote(midi: midi, velocity: velArp, gateDurationSec: arpGate)
            }
        }

        let arpeggioEnd = Double(max(0, n - 1)) * arpStep + arpGate + pauseAfterArpeggio
        queue.asyncAfter(deadline: .now() + arpeggioEnd) { [weak self] in
            guard let self, token == self.playbackSerial else { return }
            try? self.audio.playSampledGuitarChord(
                midis: midis,
                velocity: velBlock,
                gateDurationSec: Self.blockGateSec,
                stringStaggerSec: Self.blockStaggerSec
            )
        }
    }
}
