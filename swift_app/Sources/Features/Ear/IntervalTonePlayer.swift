import Foundation
import Core

public protocol IntervalTonePlaying: AnyObject {
    func playAscendingPair(lowMidi: Int, highMidi: Int) async throws
    /// 单音试听（与指板同源 SF2；略短 gate 便于快速多点）。
    func playSinglePreview(midi: Int) async throws
}

public final class IntervalTonePlayer: IntervalTonePlaying {
    private let audio: AudioEngineServing

    /// 与 `FretboardTonePlayer` 一致：钢弦吉他 SF2 单音。
    private static let sampledVelocity: UInt8 = 100
    private static let sampledGateSec = 1.1
    /// 第一音 gate 结束后再留的空档，再触发第二音（原先正弦两音间仅约 90 ms）。
    private static let silenceAfterFirstGateSec = 0.28
    /// 第二音 note-off 后等待的释音尾，再结束 `playAscendingPair`（用于 UI 解锁「播放」）。
    private static let releaseTailAfterSecondGateSec = 0.22
    private static let previewGateSec = 0.52
    private static let previewTailSec = 0.18

    public init(audio: AudioEngineServing = AudioEngineService()) {
        self.audio = audio
    }

    public func playAscendingPair(lowMidi: Int, highMidi: Int) async throws {
        try audio.start()
        if audio.isSampledGuitarAvailable {
            try audio.playSampledGuitarNote(
                midi: lowMidi,
                velocity: Self.sampledVelocity,
                gateDurationSec: Self.sampledGateSec
            )
            try await Task.sleep(
                nanoseconds: UInt64((Self.sampledGateSec + Self.silenceAfterFirstGateSec) * 1_000_000_000)
            )
            try audio.playSampledGuitarNote(
                midi: highMidi,
                velocity: Self.sampledVelocity,
                gateDurationSec: Self.sampledGateSec
            )
            try await Task.sleep(
                nanoseconds: UInt64((Self.sampledGateSec + Self.releaseTailAfterSecondGateSec) * 1_000_000_000)
            )
        } else {
            let hzLow = Self.midiToHz(lowMidi)
            let hzHigh = Self.midiToHz(highMidi)
            let pluckDur = max(0.95, Self.sampledGateSec + 0.65)
            try audio.playPluckedGuitarString(frequencyHz: hzLow, durationSec: pluckDur)
            try await Task.sleep(
                nanoseconds: UInt64((Self.sampledGateSec + Self.silenceAfterFirstGateSec) * 1_000_000_000)
            )
            try audio.playPluckedGuitarString(frequencyHz: hzHigh, durationSec: pluckDur)
            try await Task.sleep(
                nanoseconds: UInt64((pluckDur + Self.releaseTailAfterSecondGateSec) * 1_000_000_000)
            )
        }
    }

    public func playSinglePreview(midi: Int) async throws {
        try audio.start()
        if audio.isSampledGuitarAvailable {
            try audio.playSampledGuitarNote(
                midi: midi,
                velocity: Self.sampledVelocity,
                gateDurationSec: Self.previewGateSec
            )
            try await Task.sleep(
                nanoseconds: UInt64((Self.previewGateSec + Self.previewTailSec) * 1_000_000_000)
            )
        } else {
            let hz = Self.midiToHz(midi)
            let dur = 0.72
            try audio.playPluckedGuitarString(frequencyHz: hz, durationSec: dur)
            try await Task.sleep(
                nanoseconds: UInt64((dur + 0.12) * 1_000_000_000)
            )
        }
    }

    private static func midiToHz(_ midi: Int) -> Double {
        440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }
}
