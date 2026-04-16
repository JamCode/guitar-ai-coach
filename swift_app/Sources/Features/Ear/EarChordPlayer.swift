import Foundation
import Core

public protocol EarChordPlaying: AnyObject {
    func playChordMidis(_ midis: [Int]) async throws
    func playChordSequence(_ sequence: [[Int]]) async throws
}

public final class EarChordPlayer: EarChordPlaying {
    private let audio: AudioEngineServing

    public init(audio: AudioEngineServing = AudioEngineService()) {
        self.audio = audio
    }

    public func playChordMidis(_ midis: [Int]) async throws {
        for midi in midis {
            try audio.playSine(frequencyHz: midiToHz(midi), durationSec: 0.20)
            try await Task.sleep(nanoseconds: 80_000_000)
        }
    }

    public func playChordSequence(_ sequence: [[Int]]) async throws {
        for chord in sequence {
            try await playChordMidis(chord)
            try await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func midiToHz(_ midi: Int) -> Double {
        440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }
}
