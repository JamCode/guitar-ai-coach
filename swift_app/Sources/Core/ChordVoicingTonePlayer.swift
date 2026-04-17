import Foundation

/// 按 **6→1 弦绝对品格** 播放和弦：钢弦 SF2 采样，**先分解琶音（低音→高音）**，再 **柱式**。
/// 供「常用和弦」「和弦速查」等共用。
public final class ChordVoicingTonePlayer {
    private let audio: AudioEngineServing
    private let queue = DispatchQueue(label: "guitar-ai-coach.chord-voicing-tone", qos: .userInitiated)
    private var didPrepareAudio = false
    /// 用于取消上一次尚未触发的延迟任务，避免快速连点叠音。
    private var playbackSerial = 0

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

    private func scheduleArpeggioThenBlock(midis: [Int], token: Int) {
        let n = midis.count
        // 分解琶音节奏：步进略长于单音 gate，既留气口又有一点自然交叠。
        let arpStep = 0.28
        let arpGate = 0.24
        let pauseAfterArpeggio = 0.22
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
                gateDurationSec: 1.42,
                stringStaggerSec: 0.014
            )
        }
    }
}
