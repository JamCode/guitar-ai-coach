import Foundation
import Core

public final class FretboardTonePlayer {
    private let audio: AudioEngineServing
    private let queue = DispatchQueue(label: "guitar-ai-coach.fretboard-tone-player", qos: .userInitiated)
    private var didPrepareAudio = false

    public init(audio: AudioEngineServing = AudioEngineService()) {
        self.audio = audio
    }

    public func prepare() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.didPrepareAudio else { return }
            do {
                try self.audio.start()
                self.didPrepareAudio = true
            } catch {
                self.didPrepareAudio = false
            }
        }
    }

    public func playMidi(_ midi: Int) {
        let frequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        queue.async { [weak self] in
            guard let self else { return }
            if !self.didPrepareAudio {
                do {
                    try self.audio.start()
                    self.didPrepareAudio = true
                } catch {
                    self.didPrepareAudio = false
                    return
                }
            }
            try? self.audio.playPluckedGuitarString(frequencyHz: frequency, durationSec: 0.48)
        }
    }
}

