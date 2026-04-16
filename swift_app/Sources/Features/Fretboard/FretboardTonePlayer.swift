import Foundation
import Core

public final class FretboardTonePlayer {
    private let audio: AudioEngineServing

    public init(audio: AudioEngineServing = AudioEngineService()) {
        self.audio = audio
    }

    public func playMidi(_ midi: Int) {
        let frequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        try? audio.playSine(frequencyHz: frequency, durationSec: 0.22)
    }
}

