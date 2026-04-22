import Foundation
import AVFoundation

/// 采样音色资源入口，便于测试与上层复用。
public enum GuitarSoundBank {
    /// 钢弦原声吉他 SF2（FreePats FSS Steel-String Acoustic Guitar，**Best quality** 全量采样版，约 25 MB）。
    public static var steelStringSF2URL: URL? {
        Bundle.module.url(forResource: "SteelStringGuitar", withExtension: "sf2")
    }
}

public protocol AudioEngineServing: AnyObject {
    var quality: AudioQualityBaseline { get }
    func start() throws
    func stop()
    func playSine(frequencyHz: Double, durationSec: Double) throws
    /// 拨弦式衰减（Karplus–Strong），作为采样不可用时的降级实现。
    func playPluckedGuitarString(frequencyHz: Double, durationSec: Double) throws
    /// 采样吉他回放，优先走内置 SF2 + `AVAudioUnitSampler`。
    ///
    /// - Parameters:
    ///   - midi: 标准 MIDI 音高（如 A4 = 69）。
    ///   - velocity: 力度（1..127），影响采样包里 velocity layer 的触发。
    ///   - gateDurationSec: 从按下到松开的时长；松开后由 SF2 本身的 release envelope 提供自然尾音。
    func playSampledGuitarNote(midi: Int, velocity: UInt8, gateDurationSec: Double) throws
    /// 当前是否已成功加载采样音色（用于上层决定是否需要 fallback）。
    var isSampledGuitarAvailable: Bool { get }
    /// 同时或略带扫弦感地播放一组 MIDI（和弦），使用与单音相同的 SF2 采样。
    func playSampledGuitarChord(
        midis: [Int],
        velocity: UInt8,
        gateDurationSec: Double,
        stringStaggerSec: Double
    ) throws
    /// 立刻对指定 MIDI 发送 `noteOff`（同一 `AVAudioUnitSampler` 通道），用于打断练耳「两音间隔」等可取消播放。
    func stopSampledGuitarNotes(midis: [Int])
    /// 立刻停止所有 Karplus–Strong 拨弦节点上的已调度缓冲（与采样轨独立）。
    func stopPluckedGuitarVoices()
}

enum GuitarPlaybackHumanizer {
    static func velocity(base: UInt8, midi: Int, noteIndex: Int? = nil, totalNotes: Int? = nil) -> UInt8 {
        let baseValue = max(1, min(127, Int(base)))
        let pitchBias = if midi <= 47 {
            5
        } else if midi <= 59 {
            2
        } else {
            0
        }
        let edgeBias: Int = if let noteIndex, let totalNotes, totalNotes > 1 {
            noteIndex == 0 ? 3 : (noteIndex == totalNotes - 1 ? 1 : 0)
        } else {
            0
        }
        // 真随机 ±10% velocity 偏移（约 ±12 级），替代原来仅 ±2 的确定性循环偏移，消除机器感。
        let randomOffset = Int.random(in: -13...13)
        return UInt8(max(1, min(127, baseValue + pitchBias + edgeBias + randomOffset)))
    }

    static func gate(base: Double, midi: Int, noteIndex: Int? = nil, totalNotes: Int? = nil) -> Double {
        let baseValue = max(0.08, base)
        let pitchBias = if midi <= 47 {
            0.24
        } else if midi <= 59 {
            0.14
        } else {
            0.07
        }
        let strumBias: Double = if let noteIndex, let totalNotes, totalNotes > 1 {
            Double(max(0, totalNotes - 1 - noteIndex)) * 0.018
        } else {
            0
        }
        let cyclicOffset = Double(((midi * 19) + (noteIndex ?? 0) * 7) % 4) * 0.012
        return min(2.6, baseValue + pitchBias + strumBias + cyclicOffset)
    }

    static func microDelay(noteIndex: Int, totalNotes: Int) -> Double {
        guard totalNotes > 1 else { return 0 }
        // 在基础扫弦间隔（stagger）之上叠加 0~2ms 的随机抖动，避免完全等间距的机械感。
        return Double.random(in: 0...0.002)
    }
}

public final class AudioEngineService: AudioEngineServing {
    /// Shared output engine for sampled guitar playback.
    ///
    /// Multiple feature modules historically defaulted to `AudioEngineService()` independently.
    /// That can create several `AVAudioEngine` graphs + independent `AVAudioUnitSampler` instances,
    /// which is heavier and can make "ghost" / delayed playback harder to reason about during navigation.
    public static let shared = AudioEngineService()

    public let quality: AudioQualityBaseline
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// 多路拨弦节点：轮询调度，避免单节点 `.interrupts` 把尚未自然衰减的上一个音粗暴截断。
    private let pluckVoices: [AVAudioPlayerNode]
    private var nextPluckVoice = 0
    private let sampler = AVAudioUnitSampler()
    private let guitarMixer = AVAudioMixerNode()
    private let guitarEQ = AVAudioUnitEQ(numberOfBands: 4)
    private let guitarReverb = AVAudioUnitReverb()
    private var sampledGuitarLoaded = false
    private let samplerQueue = DispatchQueue(label: "guitar-ai-coach.audio.sampler-gate", qos: .userInitiated)
    private var started = false
    /// Round-robin 计数器：每次触发单音或扫弦时递增，结合 masterTuning 微音高偏移模拟不同演奏角度的细微差异。
    private var rrCounter: Int = 0
    /// 三档微音高偏移（单位：cent），轮换顺序固定，覆盖 0 / -1.8 / +1.8 cent。
    /// `internal` 可见度供单元测试验证数组内容，不对外暴露为 public API。
    static let rrTuningOffsets: [Float] = [0, -1.8, 1.8]

    public init(quality: AudioQualityBaseline = AudioQualityBaseline()) {
        self.quality = quality
        self.pluckVoices = (0..<4).map { _ in AVAudioPlayerNode() }
        engine.attach(player)
        for voice in pluckVoices {
            engine.attach(voice)
        }
        engine.attach(sampler)
        engine.attach(guitarMixer)
        engine.attach(guitarEQ)
        engine.attach(guitarReverb)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        for voice in pluckVoices {
            engine.connect(voice, to: guitarMixer, format: nil)
        }
        engine.connect(sampler, to: guitarMixer, format: nil)
        engine.connect(guitarMixer, to: guitarEQ, format: nil)
        engine.connect(guitarEQ, to: guitarReverb, format: nil)
        engine.connect(guitarReverb, to: engine.mainMixerNode, format: nil)
        configureGuitarToneChain()
    }

    public func start() throws {
        guard !started else { return }
        try configureSession()
        try engine.start()
        started = true
        quality.markStart()
        loadSampledGuitarIfNeeded()
    }

    public func stop() {
        guard started else { return }
        player.stop()
        for voice in pluckVoices {
            voice.stop()
        }
        engine.stop()
        started = false
        invalidateGraphDependentPlaybackState()
        quality.markStop()
    }

    /// After `AVAudioEngine.stop()`, any state that assumes the graph is running must be cleared so the next `start()`
    /// rebuilds it. Add new flags here if they describe sampler / node readiness tied to a running engine.
    private func invalidateGraphDependentPlaybackState() {
        sampledGuitarLoaded = false
    }

    public func stopSampledGuitarNotes(midis: [Int]) {
        guard started else { return }
        samplerQueue.sync { [weak self] in
            guard let self else { return }
            for raw in midis {
                let clamped = UInt8(max(0, min(127, raw)))
                self.sampler.stopNote(clamped, onChannel: 0)
            }
        }
    }

    public func stopPluckedGuitarVoices() {
        guard started else { return }
        for voice in pluckVoices {
            voice.stop()
        }
    }

    public var isSampledGuitarAvailable: Bool { sampledGuitarLoaded }

    private func configureGuitarToneChain() {
        // sampler.volume 已回到 1.0（线性安全），在此把 mixer 增益补回至 1.0 维持原有主观响度。
        guitarMixer.outputVolume = 1.0

        // 高通：截掉 85 Hz 以下的低频噪底与基音低频成分，改善整体通透感。
        let highPass = guitarEQ.bands[0]
        highPass.filterType = .highPass
        highPass.frequency = 85
        highPass.bypass = false

        let lowMidCut = guitarEQ.bands[1]
        lowMidCut.filterType = .parametric
        lowMidCut.frequency = 240
        lowMidCut.bandwidth = 0.8
        lowMidCut.gain = -3.0
        lowMidCut.bypass = false

        let presenceBoost = guitarEQ.bands[2]
        presenceBoost.filterType = .parametric
        presenceBoost.frequency = 3_200
        presenceBoost.bandwidth = 0.7
        presenceBoost.gain = 2.2
        presenceBoost.bypass = false

        let airShelf = guitarEQ.bands[3]
        airShelf.filterType = .highShelf
        airShelf.frequency = 7_200
        airShelf.bandwidth = 0.6
        airShelf.gain = 1.6
        airShelf.bypass = false

        // plate 预设比 mediumRoom 更通透，更贴合原声木吉他录音感；wetDryMix 20 提供自然空间感。
        guitarReverb.loadFactoryPreset(.plate)
        guitarReverb.wetDryMix = 20
    }

    private func loadSampledGuitarIfNeeded() {
        guard !sampledGuitarLoaded else { return }
        guard let url = GuitarSoundBank.steelStringSF2URL else {
            sampledGuitarLoaded = false
            return
        }
        // SF2 非 GM 包常用 melodic bank MSB = 0x79, LSB = 0, program = 0。
        let melodicBankMSB: UInt8 = 0x79
        let bankLSB: UInt8 = 0x00
        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: 0,
                bankMSB: melodicBankMSB,
                bankLSB: bankLSB
            )
            // 保持线性增益在 1.0 以内，避免超过混音器满量程产生数字过载失真。
            sampler.volume = 1.0
            sampledGuitarLoaded = true
        } catch {
            sampledGuitarLoaded = false
        }
    }

    public func playSampledGuitarNote(
        midi: Int,
        velocity: UInt8 = 100,
        gateDurationSec: Double = 1.2
    ) throws {
        if !started {
            try start()
        }
        guard sampledGuitarLoaded else {
            // 降级到算法拨弦，保证始终有声。
            let frequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
            try playPluckedGuitarString(frequencyHz: frequency, durationSec: max(0.9, gateDurationSec + 0.6))
            return
        }
        let clampedMidi = UInt8(max(0, min(127, midi)))
        let shapedVelocity = GuitarPlaybackHumanizer.velocity(base: velocity, midi: midi)
        let gate = GuitarPlaybackHumanizer.gate(base: gateDurationSec, midi: midi)
        let tuningOffset = AudioEngineService.rrTuningOffsets[rrCounter % AudioEngineService.rrTuningOffsets.count]
        rrCounter += 1
        let start = DispatchTime.now().uptimeNanoseconds
        samplerQueue.sync { [weak self] in
            guard let self else { return }
            // Round-robin 微音高：每次单音触发轮换 0 / -1.8 / +1.8 cent，模拟不同拨弦力度与角度带来的音色微差。
            self.sampler.masterTuning = Double(tuningOffset)
            self.sampler.stopNote(clampedMidi, onChannel: 0)
            self.sampler.startNote(clampedMidi, withVelocity: shapedVelocity, onChannel: 0)
        }
        samplerQueue.asyncAfter(deadline: .now() + gate) { [weak self] in
            self?.sampler.stopNote(clampedMidi, onChannel: 0)
        }
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        quality.markCallback(renderCostMs: elapsedMs)
    }

    public func playSampledGuitarChord(
        midis: [Int],
        velocity: UInt8 = 88,
        gateDurationSec: Double = 1.35,
        stringStaggerSec: Double = 0.020
    ) throws {
        if !started {
            try start()
        }
        let notes = midis.filter { $0 >= 0 && $0 <= 127 }
        guard !notes.isEmpty else { return }
        let start = DispatchTime.now().uptimeNanoseconds
        let stagger = max(0, stringStaggerSec)

        guard sampledGuitarLoaded else {
            for midi in notes {
                let frequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
                let shapedGate = GuitarPlaybackHumanizer.gate(base: gateDurationSec, midi: midi)
                try? playPluckedGuitarString(frequencyHz: frequency, durationSec: max(0.95, shapedGate + 0.35))
            }
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            quality.markCallback(renderCostMs: elapsedMs)
            return
        }

        for (i, midi) in notes.enumerated() {
            let delay = Double(i) * stagger + GuitarPlaybackHumanizer.microDelay(noteIndex: i, totalNotes: notes.count)
            let note = UInt8(midi)
            let shapedVelocity = GuitarPlaybackHumanizer.velocity(base: velocity, midi: midi, noteIndex: i, totalNotes: notes.count)
            let shapedGate = GuitarPlaybackHumanizer.gate(base: gateDurationSec, midi: midi, noteIndex: i, totalNotes: notes.count)
            // 每根弦独立取 round-robin 微音高，和弦内各音有微小音高差异，模拟真实演奏中的弦间色差。
            let tuningOffset = AudioEngineService.rrTuningOffsets[(rrCounter + i) % AudioEngineService.rrTuningOffsets.count]
            samplerQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.sampler.masterTuning = Double(tuningOffset)
                self.sampler.stopNote(note, onChannel: 0)
                self.sampler.startNote(note, withVelocity: shapedVelocity, onChannel: 0)
            }
            samplerQueue.asyncAfter(deadline: .now() + delay + shapedGate) { [weak self] in
                self?.sampler.stopNote(note, onChannel: 0)
            }
        }
        rrCounter += notes.count
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        quality.markCallback(renderCostMs: elapsedMs)
    }

    public func playSine(frequencyHz: Double, durationSec: Double = 0.25) throws {
        if !started {
            try start()
        }
        // 必须与 `AVAudioPlayerNode` 连到 `mainMixerNode` 后的实际 PCM 格式一致，
        // 否则 `scheduleBuffer` 在常见硬件采样率（如 48kHz）下可能直接崩溃。
        let format = player.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            quality.markUnderrun()
            return
        }
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(max(1, Int(sampleRate * durationSec)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            quality.markUnderrun()
            return
        }
        buffer.frameLength = frameCount
        let start = DispatchTime.now().uptimeNanoseconds
        let theta = 2.0 * Double.pi * frequencyHz / sampleRate
        let outputChannels = Int(format.channelCount)
        if let channels = buffer.floatChannelData {
            for channelIndex in 0..<outputChannels {
                let channel = channels[channelIndex]
                for i in 0..<Int(frameCount) {
                    channel[i] = Float(sin(Double(i) * theta) * 0.20)
                }
            }
        }
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        quality.markCallback(renderCostMs: elapsedMs)

        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying {
            player.play()
        }
    }

    public func playPluckedGuitarString(frequencyHz: Double, durationSec: Double = 1.75) throws {
        if !started {
            try start()
        }
        let voice = pluckVoices[nextPluckVoice % pluckVoices.count]
        nextPluckVoice += 1
        let format = voice.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            quality.markUnderrun()
            return
        }
        let sampleRate = format.sampleRate
        let hz = min(4_200, max(60, frequencyHz))
        let delayLen = max(8, Int(sampleRate / hz + 0.5))
        var ring = [Float](repeating: 0, count: delayLen)
        var prevNoise: Float = 0
        for i in 0..<delayLen {
            let r = Float.random(in: -0.32...0.32)
            let smoothed = 0.62 * r + 0.38 * prevNoise
            prevNoise = r
            ring[i] = smoothed
        }
        let totalFrames = AVAudioFrameCount(max(1, Int(sampleRate * max(0.35, durationSec))))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            quality.markUnderrun()
            return
        }
        buffer.frameLength = totalFrames
        // 低音弦衰减更慢、高音略收紧，整体更接近钢弦吉他体感。
        let spanHz = max(1.0, 420.0 - 65.0)
        let normT = Float((min(420.0, max(65.0, hz)) - 65.0) / spanHz)
        let decay = 0.99812 - normT * 0.00168
        let attackFrames = max(1, Int(sampleRate * 0.0052))
        let fadeOutFrames = min(Int(totalFrames) - 1, Int(sampleRate * 0.42))
        let fadeOutStart = max(0, Int(totalFrames) - fadeOutFrames)
        let outputChannels = Int(format.channelCount)
        let start = DispatchTime.now().uptimeNanoseconds
        if let channels = buffer.floatChannelData {
            var pos = 0
            for frame in 0..<Int(totalFrames) {
                let i0 = pos
                let i1 = (pos + 1) % delayLen
                let out = ring[i0]
                ring[i0] = 0.5 * (out + ring[i1]) * decay
                pos = (pos + 1) % delayLen
                let attack: Float = if frame < attackFrames {
                    Float(0.5 * (1.0 - cos(Double.pi * Double(frame) / Double(attackFrames))))
                } else {
                    1.0
                }
                var sample = out * 0.17 * attack
                if frame >= fadeOutStart, fadeOutFrames > 1 {
                    let t = Float(frame - fadeOutStart) / Float(fadeOutFrames - 1)
                    let tail = Float(0.5 * (1.0 + cos(Double.pi * Double(t))))
                    sample *= tail
                }
                for channelIndex in 0..<outputChannels {
                    channels[channelIndex][frame] = sample
                }
            }
        }
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        quality.markCallback(renderCostMs: elapsedMs)
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !voice.isPlaying {
            voice.play()
        }
    }

    private func configureSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(44_100)
        try session.setPreferredIOBufferDuration(0.0058)
        try session.setActive(true)
        #endif
    }
}

