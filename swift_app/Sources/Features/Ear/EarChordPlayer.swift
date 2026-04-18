import Foundation
import Core

public protocol EarChordPlaying: AnyObject {
    func playChordMidis(_ midis: [Int]) async throws
    func playChordSequence(_ sequence: [[Int]]) async throws
    /// 与指板同源 SF2 单音试听（音区条用）。
    func playSinglePreview(midi: Int) async throws
}

public final class EarChordPlayer: EarChordPlaying {
    private let audio: AudioEngineServing
    private static let sampledVelocity: UInt8 = 100
    private static let previewGateSec = 0.52
    private static let previewTailSec = 0.18

    public init(audio: AudioEngineServing = AudioEngineService()) {
        self.audio = audio
    }

    public func playChordMidis(_ midis: [Int]) async throws {
        for midi in midis {
            try audio.playSine(frequencyHz: Self.midiToHz(midi), durationSec: 0.20)
            try await Task.sleep(nanoseconds: 80_000_000)
        }
    }

    public func playChordSequence(_ sequence: [[Int]]) async throws {
        for chord in sequence {
            try await playChordMidis(chord)
            try await Task.sleep(nanoseconds: 150_000_000)
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
            try audio.playSine(frequencyHz: Self.midiToHz(midi), durationSec: 0.35)
            try await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    private static func midiToHz(_ midi: Int) -> Double {
        440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }
}
