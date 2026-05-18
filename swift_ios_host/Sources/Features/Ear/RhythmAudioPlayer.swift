import AVFoundation
import Foundation

/// 播放节奏 click 序列（独立 AVAudioEngine，不干扰其他音频服务）
public final class RhythmAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let queue = DispatchQueue(label: "guitar-ai-coach.rhythm-audio", qos: .userInitiated)

    /// 是否正在播放
    public private(set) var isPlaying = false
    private var generation: UInt64 = 0

    public init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
    }

    /// 播完回调（只在正常完成、未被中途取消时触发）
    public var onPlaybackFinished: (() -> Void)?

    /// 播放一个节奏型
    /// - Parameters:
    ///   - pattern: 节奏型
    ///   - bpm: 速度，默认 90
    public func play(pattern: RhythmPattern, bpm: Int = 90) {
        stop()
        isPlaying = true
        generation &+= 1
        let gen = generation

        let eighthInterval = 60.0 / Double(bpm) / 2.0  // 每个八分位秒数
        let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0 else {
            isPlaying = false
            return
        }
        let format = engine.mainMixerNode.outputFormat(forBus: 0)

        do {
            try ensureSession()
            try engine.start()
        } catch {
            isPlaying = false
            return
        }

        // 为每个击发的八分位调度一个 click buffer
        for (i, hit) in pattern.hits.enumerated() where hit {
            let isAccent = (i == 0 || i == 4)  // 第 1、3 拍为强拍
            let buffer = Self.makeClickBuffer(format: format, accent: isAccent)
            let sampleTime = AVAudioFramePosition(Double(i) * eighthInterval * sampleRate)
            let time = AVAudioTime(sampleTime: sampleTime, atRate: sampleRate)
            player.scheduleBuffer(buffer, at: time, options: [])
        }

        player.play()

        // 计算总时长并在结束时异步回调
        let totalDuration = 8.0 * eighthInterval
        queue.asyncAfter(deadline: .now() + totalDuration + 0.05) { [weak self] in
            guard let self, self.generation == gen else { return }
            DispatchQueue.main.async {
                self.isPlaying = false
                self.onPlaybackFinished?()
            }
        }
    }

    /// 停止播放
    public func stop() {
        generation &+= 1
        player.stop()
        if engine.isRunning {
            engine.stop()
        }
        isPlaying = false
    }

    // MARK: - Private

    private func ensureSession() throws {
        #if os(iOS)
        try AppAudioSession.configureSharedForPlaybackAndRecording()
        #endif
    }

    /// 合成一个 click buffer（与 MetronomeEngine 的 click 合成逻辑一致）
    private static func makeClickBuffer(format: AVAudioFormat, accent: Bool) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let (freq, duration, amplitude): (Double, Double, Double) = accent
            ? (1_200, 0.050, 0.40)
            : (880, 0.035, 0.22)

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
