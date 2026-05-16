import Foundation

public protocol EarChordPlaying: AnyObject {
    func playChordMidis(_ midis: [Int]) async throws
    func playChordSequence(_ sequence: [[Int]]) async throws
    /// 与指板同源 SF2 单音试听（音区条用）。
    func playSinglePreview(midi: Int) async throws
    /// 与「常用和弦」一致：先分解琶音再柱式（`ChordVoicingTonePlayer`）。
    func playChordFromFretsSixToOne(_ frets: [Int]) async throws
    /// 和弦进行：按顺序仅柱式播放每个把位（与常用和弦里柱式段同源），和弦间留短空隙。
    func playProgressionFromFretsSixToOne(_ sequence: [[Int]]) async throws
    /// 立刻静音采样吉他轨（含琶音进行中），供切换难度等场景打断试听。
    func cancelChordPlayback()
}

public final class EarChordPlayer: EarChordPlaying {
    private let audio: AudioEngineServing
    private let voicing: ChordVoicingTonePlayer
    private static let sampledVelocity: UInt8 = 100
    private static let previewGateSec = 0.52
    private static let previewTailSec = 0.18
    /// 与 `ChordVoicingTonePlayer` 柱式段相近：钢弦 SF2 和弦 gate + 扫弦 stagger。
    private static let chordGateSec = 1.0
    private static let chordStaggerSec = 0.014
    /// `playSampledGuitarChord` 在调度 note-off 后仍留一点释音尾，避免「播放」过早解锁叠音。
    private static let chordAudibleTailSec = 0.2
    /// Humanizer 单音 gate 上限约 2.6s，留足余量避免截断。
    private static let chordWaitHeadroomSec = 1.2
    /// 和弦进行中逐和弦柱式：释音等待较短，下一和弦更紧凑（仍略长于 gate 以免叠音刺耳）。
    private static let progressionChordReleaseWaitSec = 0.68

    /// 与 `IntervalTonePlayer` 一致的取消代计数器：每次 `cancelChordPlayback` 递增，
    /// `cooperativeSleep` 在 chunk 间隔检查，发现代差立刻早期抛出
    /// `CancellationError`，避免旧任务 catch 块在旧音已停后还去调
    /// `stopAllSampledGuitarNotes` 误杀新播放的音。
    private var cancelGeneration = 0
    private let stateLock = NSLock()

    public init(audio: AudioEngineServing = AudioEngineService.shared) {
        self.audio = audio
        self.voicing = ChordVoicingTonePlayer(audio: audio)
    }

    public func cancelChordPlayback() {
        stateLock.lock()
        cancelGeneration += 1
        stateLock.unlock()
        voicing.cancelAwaitablePlayback()
        audio.stopAllSampledGuitarNotes()
        audio.stopPluckedGuitarVoices()
    }

    public func playChordFromFretsSixToOne(_ frets: [Int]) async throws {
        guard frets.count == 6 else { return }
        try await voicing.playChordFretsAwaitable(frets)
    }

    /// 和弦与和弦之间的额外空隙（进行内与逐和弦序列共用）。
    private static let progressionBetweenChordGapNs: UInt64 = 70_000_000

    public func playProgressionFromFretsSixToOne(_ sequence: [[Int]]) async throws {
        for (i, frets) in sequence.enumerated() {
            guard frets.count == 6 else { continue }
            let midis = GuitarStandardTuning.midisFromChordFretsSixToOne(frets)
            try await playChordBlockSF2(midis: midis, releaseTailSec: Self.progressionChordReleaseWaitSec)
            if i < sequence.count - 1 {
                try await Task.sleep(nanoseconds: Self.progressionBetweenChordGapNs)
            }
        }
    }

    public func playChordMidis(_ midis: [Int]) async throws {
        try await playChordBlockSF2(
            midis: midis,
            releaseTailSec: Self.chordWaitHeadroomSec + Self.chordAudibleTailSec
        )
    }

    /// 播放一帧柱式 SF2；`releaseTailSec` 为扫弦跨度之后的等待（进行内用短尾，单和弦用长尾）。
    /// 使用 `cooperativeSleep` 替代裸 `Task.sleep`，确保快速重播时旧任务早期抛出
    /// `CancellationError`，避免竞态中 `stopAllSampledGuitarNotes` 误杀新音。
    private func playChordBlockSF2(midis: [Int], releaseTailSec: Double) async throws {
        try audio.start()
        let notes = Self.sortedUniqueMidis(midis)
        guard !notes.isEmpty else { return }
        try audio.playSampledGuitarChord(
            midis: notes,
            velocity: Self.sampledVelocity,
            gateDurationSec: Self.chordGateSec,
            stringStaggerSec: Self.chordStaggerSec
        )
        let staggerSpan = Double(max(0, notes.count - 1)) * Self.chordStaggerSec
        let waitSec = staggerSpan + releaseTailSec
        try await cooperativeSleep(seconds: waitSec)
    }

    public func playChordSequence(_ sequence: [[Int]]) async throws {
        for (i, chord) in sequence.enumerated() {
            try await playChordBlockSF2(midis: chord, releaseTailSec: Self.progressionChordReleaseWaitSec)
            if i < sequence.count - 1 {
                try await Task.sleep(nanoseconds: Self.progressionBetweenChordGapNs)
            }
        }
    }

    public func playSinglePreview(midi: Int) async throws {
        try audio.start()
        try audio.playSampledGuitarNote(
            midi: midi,
            velocity: Self.sampledVelocity,
            gateDurationSec: Self.previewGateSec
        )
        try await cooperativeSleep(seconds: Self.previewGateSec + Self.previewTailSec)
    }

    /// 与 `IntervalTonePlayer.cooperativeSleep` 等价的取消感知等待。
    /// 每 50ms 检查一次 `cancelGeneration`；若在被替代后调用，立即早期抛出
    /// `CancellationError`，避免旧任务 catch 块的 `stopAllSampledGuitarNotes` 误杀新音。
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

    /// 低→高排序、去重，便于扫弦与与 `AudioEngineService` 的 stagger 一致。
    private static func sortedUniqueMidis(_ midis: [Int]) -> [Int] {
        Array(Set(midis.filter { $0 >= 0 && $0 <= 127 })).sorted()
    }
}
