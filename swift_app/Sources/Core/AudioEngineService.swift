import Foundation
import AVFoundation

public protocol AudioEngineServing: AnyObject {
    var quality: AudioQualityBaseline { get }
    func start() throws
    func stop()
    func playSine(frequencyHz: Double, durationSec: Double) throws
    /// 拨弦式衰减（Karplus–Strong），用于指板等吉他语境试听。
    func playPluckedGuitarString(frequencyHz: Double, durationSec: Double) throws
}

public final class AudioEngineService: AudioEngineServing {
    public let quality: AudioQualityBaseline
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var started = false

    public init(quality: AudioQualityBaseline = AudioQualityBaseline()) {
        self.quality = quality
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
    }

    public func start() throws {
        guard !started else { return }
        try configureSession()
        try engine.start()
        started = true
        quality.markStart()
    }

    public func stop() {
        guard started else { return }
        player.stop()
        engine.stop()
        started = false
        quality.markStop()
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

    public func playPluckedGuitarString(frequencyHz: Double, durationSec: Double = 0.48) throws {
        if !started {
            try start()
        }
        let format = player.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            quality.markUnderrun()
            return
        }
        let sampleRate = format.sampleRate
        let hz = min(4_200, max(60, frequencyHz))
        let delayLen = max(8, Int(sampleRate / hz))
        var ring = [Float](repeating: 0, count: delayLen)
        for i in 0..<delayLen {
            ring[i] = Float.random(in: -0.45...0.45)
        }
        let totalFrames = AVAudioFrameCount(max(1, Int(sampleRate * durationSec)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            quality.markUnderrun()
            return
        }
        buffer.frameLength = totalFrames
        let decay: Float = 0.9965
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
                let env = Float(frame) / Float(max(1, Int(sampleRate * 0.002)))
                let attack = min(1, env)
                let sample = out * 0.22 * attack
                for channelIndex in 0..<outputChannels {
                    channels[channelIndex][frame] = sample
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

