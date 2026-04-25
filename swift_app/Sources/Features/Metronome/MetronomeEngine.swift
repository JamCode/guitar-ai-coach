import AVFoundation
import Core
import Foundation

/// 节拍音频与定时驱动：独立 `AVAudioEngine`，不占用 `AudioEngineService` 的吉他采样节点，避免互相打断。
public protocol MetronomeEngineing: AnyObject {
    var onBeat: ((Int, Bool) -> Void)? { get set }
    /// `beatIndex` 从 1 开始，每小节循环；`isAccent` 表示强拍。
    func start(bpm: Int, beatsPerMeasure: Int, volume: Double, sound: MetronomeSoundPreset) throws
    func pause()
    func stop()
    var isRunning: Bool { get }
}

public final class MetronomeEngine: MetronomeEngineing {
    public var onBeat: ((Int, Bool) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let mixer = AVAudioMixerNode()

    private var accentBuffer: AVAudioPCMBuffer?
    private var normalBuffer: AVAudioPCMBuffer?

    private let timerQueue = DispatchQueue(label: "guitar-ai-coach.metronome.timer", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private let stateLock = NSLock()
    /// 单调递增代数：用于在 `stop`/`pause` 后丢弃仍排队的一次 tick。
    private var generation: UInt64 = 0
    private var beatCounter: Int = 0
    private var activeGeneration: UInt64 = 0
    private var _isRunning = false

    public var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isRunning
    }

    public init() {
        engine.attach(player)
        engine.attach(mixer)
        engine.connect(player, to: mixer, format: nil)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        mixer.outputVolume = 0.85
    }

    deinit {
        stop()
    }

    public func start(bpm: Int, beatsPerMeasure: Int, volume: Double, sound: MetronomeSoundPreset) throws {
        stop()
        let bpmClamped = MetronomeConfig.clampBPM(bpm)
        let interval = 60.0 / Double(bpmClamped)
        guard beatsPerMeasure >= 1 else { return }

        try ensureSession()
        rebuildBuffersIfNeeded(sound: sound)
        mixer.outputVolume = Float(MetronomeConfig.clampUnit(volume))

        try engine.start()
        player.play()

        stateLock.lock()
        generation &+= 1
        activeGeneration = generation
        _isRunning = true
        beatCounter = 0
        let gen = activeGeneration

        let t = DispatchSource.makeTimerSource(queue: timerQueue)
        t.schedule(deadline: .now(), repeating: interval, leeway: .microseconds(800))
        t.setEventHandler { [weak self] in
            self?.fireBeatIfCurrent(generation: gen, beatsPerMeasure: beatsPerMeasure)
        }
        timer?.cancel()
        timer = t
        stateLock.unlock()

        t.resume()
    }

    public func pause() {
        stateLock.lock()
        generation &+= 1
        timer?.cancel()
        timer = nil
        player.pause()
        _isRunning = false
        stateLock.unlock()
    }

    public func stop() {
        stateLock.lock()
        generation &+= 1
        timer?.cancel()
        timer = nil
        player.stop()
        if engine.isRunning {
            engine.stop()
        }
        _isRunning = false
        beatCounter = 0
        stateLock.unlock()
    }

    private func fireBeatIfCurrent(generation gen: UInt64, beatsPerMeasure: Int) {
        stateLock.lock()
        guard gen == activeGeneration, _isRunning else {
            stateLock.unlock()
            return
        }
        beatCounter += 1
        let indexInBar = ((beatCounter - 1) % beatsPerMeasure) + 1
        let isAccent = indexInBar == 1
        let buffer = isAccent ? accentBuffer : normalBuffer
        stateLock.unlock()

        if let buffer {
            player.scheduleBuffer(buffer, at: nil, options: [])
            if !player.isPlaying {
                player.play()
            }
        }
        DispatchQueue.main.async { [onBeat] in
            onBeat?(indexInBar, isAccent)
        }
    }

    private func ensureSession() throws {
        #if os(iOS)
        try AppAudioSession.configureSharedForPlaybackAndRecording()
        #endif
    }

    private func rebuildBuffersIfNeeded(sound: MetronomeSoundPreset) {
        let format = player.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        accentBuffer = MetronomeClickBuffers.makeBuffer(format: format, kind: sound, accent: true)
        normalBuffer = MetronomeClickBuffers.makeBuffer(format: format, kind: sound, accent: false)
    }
}

// MARK: - Click synthesis

private enum MetronomeClickBuffers {
    /// 生成极短「嘀」声缓冲；强拍略长、略亮，弱拍更轻。
    static func makeBuffer(format: AVAudioFormat, kind: MetronomeSoundPreset, accent: Bool) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let (freq, duration, amplitude): (Double, Double, Double) = switch kind {
        case .click:
            accent ? (1_200, 0.045, 0.42) : (880, 0.032, 0.22)
        case .wood:
            accent ? (520, 0.07, 0.38) : (380, 0.055, 0.2)
        }

        let frameCount = AVAudioFrameCount(max(1, Int(sampleRate * duration)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let theta = 2.0 * Double.pi * freq / sampleRate
        let channels = Int(format.channelCount)
        guard let data = buffer.floatChannelData else { return buffer }
        for frame in 0..<Int(frameCount) {
            let denom = max(1, Int(frameCount) - 1)
            let env = Float(1.0 - Double(frame) / Double(denom))
            let clickEnv = env * env
            let s = Float(sin(Double(frame) * theta) * amplitude * Double(clickEnv))
            for ch in 0..<channels {
                data[ch][frame] = s
            }
        }
        return buffer
    }
}
