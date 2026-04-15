import Foundation
import Core

public protocol IntervalTonePlaying: AnyObject {
    func playAscendingPair(lowMidi: Int, highMidi: Int) async throws
}

public final class IntervalTonePlayer: IntervalTonePlaying {
    private let audio: AudioEngineServing

    public init(audio: AudioEngineServing = AudioEngineService()) {
        self.audio = audio
    }

    public func playAscendingPair(lowMidi: Int, highMidi: Int) async throws {
        try audio.playSine(frequencyHz: midiToHz(lowMidi), durationSec: 0.26)
        try await pauseMs(90)
        try audio.playSine(frequencyHz: midiToHz(highMidi), durationSec: 0.30)
    }

    private func midiToHz(_ midi: Int) -> Double {
        440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }

    private func pauseMs(_ ms: UInt64) async throws {
        try await Task.sleep(nanoseconds: ms * 1_000_000)
    }
}
