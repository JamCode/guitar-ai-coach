import Foundation
import AVFoundation

public protocol AudioEngineServing: AnyObject {
    var quality: AudioQualityBaseline { get }
    func start() throws
    func stop()
    func playSine(frequencyHz: Double, durationSec: Double) throws
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
        let sampleRate = 44_100.0
        let frameCount = AVAudioFrameCount(max(1, Int(sampleRate * durationSec)))
        let outputChannels = max(1, engine.outputNode.outputFormat(forBus: 0).channelCount)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: outputChannels)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            quality.markUnderrun()
            return
        }
        buffer.frameLength = frameCount
        let start = DispatchTime.now().uptimeNanoseconds
        let theta = 2.0 * Double.pi * frequencyHz / sampleRate
        if let channels = buffer.floatChannelData {
            for channelIndex in 0..<Int(outputChannels) {
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

