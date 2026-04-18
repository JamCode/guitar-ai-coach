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
            // 优先走真实采样（钢弦原声吉他 SF2）：通过 MIDI note on/off 让 SF2
            // 自带的 release envelope 给出自然衰减，不会出现突兀截断。
            if self.audio.isSampledGuitarAvailable {
                try? self.audio.playSampledGuitarNote(
                    midi: midi,
                    velocity: 100,
                    gateDurationSec: 1.1
                )
            } else {
                let frequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
                try? self.audio.playPluckedGuitarString(frequencyHz: frequency, durationSec: 1.85)
            }
        }
    }
}
