import Foundation
import Core

public final class FretboardTonePlayer {
    private let audio: AudioEngineServing
    private let queue = DispatchQueue(label: "guitar-ai-coach.fretboard-tone-player", qos: .userInitiated)
    private var didPrepareAudio = false

    public init(audio: AudioEngineServing = AudioEngineService.shared) {
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
            try? self.audio.playSampledGuitarNote(
                midi: midi,
                velocity: 100,
                gateDurationSec: 1.1
            )
        }
    }
}
