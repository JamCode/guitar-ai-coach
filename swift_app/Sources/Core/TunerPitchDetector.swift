import AVFoundation
import Foundation

public struct PitchDetectorConfig: Sendable {
    public var sampleRate: Double
    public var minRms: Double
    public var minFrequency: Double
    public var maxFrequency: Double
    public var minPeakCorrelation: Double
    public var minPeakToMedianRatio: Double

    public init(
        sampleRate: Double = 44_100,
        minRms: Double = 0.018,
        minFrequency: Double = 70,
        maxFrequency: Double = 420,
        minPeakCorrelation: Double = 0.34,
        minPeakToMedianRatio: Double = 1.35
    ) {
        self.sampleRate = sampleRate
        self.minRms = minRms
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
        self.minPeakCorrelation = minPeakCorrelation
        self.minPeakToMedianRatio = minPeakToMedianRatio
    }
}

public enum PitchFrameResult: Sendable {
    case pitch(frequencyHz: Double, peakCorrelation: Double, rms: Double)
    case silent(reason: String)
    case rejected(reason: String)
}

public protocol PitchDetecting: AnyObject {
    func start(callback: @escaping (PitchFrameResult) -> Void) throws
    func stop()
}

public final class TunerPitchDetector: PitchDetecting {
    private let engine = AVAudioEngine()
    private var accumulator: [Float] = []
    private let windowSamples = 8192
    private let hopSamples = 4096
    private let config: PitchDetectorConfig
    /// 实际输入采样率（与 `config.sampleRate` 可能不一致）；基频换算必须用此值。
    private var analysisSampleRate: Double = 44_100
    private let queue = DispatchQueue(label: "tuner.pitch.detector")
    private var callback: ((PitchFrameResult) -> Void)?
    private var isRunning = false

    public init(config: PitchDetectorConfig = PitchDetectorConfig()) {
        self.config = config
        self.analysisSampleRate = config.sampleRate
    }

    public func start(callback: @escaping (PitchFrameResult) -> Void) throws {
        guard !isRunning else { return }
        self.callback = callback
        try configureAudioSession()

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        analysisSampleRate = max(8_000, format.sampleRate)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        accumulator.removeAll(keepingCapacity: true)
        callback = nil
        isRunning = false
        analysisSampleRate = config.sampleRate
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        queue.async { [weak self] in
            guard let self else { return }
            self.accumulator.append(contentsOf: UnsafeBufferPointer(start: channel, count: frameLength))
            while self.accumulator.count >= self.windowSamples {
                let window = Array(self.accumulator.prefix(self.windowSamples))
                self.accumulator.removeFirst(self.hopSamples)
                let result = self.estimatePitch(samples: window)
                self.callback?(result)
            }
        }
    }

    private func estimatePitch(samples: [Float]) -> PitchFrameResult {
        var x = samples.map(Double.init)
        let length = x.count
        guard length >= 1024 else { return .silent(reason: AppL10n.t("tuner_pd_buffer_short")) }

        let mean = x.reduce(0, +) / Double(length)
        var energy = 0.0
        for i in 0..<length {
            x[i] -= mean
            energy += x[i] * x[i]
        }
        if energy <= 1e-18 { return .silent(reason: AppL10n.t("tuner_pd_no_energy")) }

        let rms = sqrt(energy / Double(length))
        if rms < config.minRms { return .silent(reason: AppL10n.t("tuner_pd_quiet")) }

        let sr = analysisSampleRate
        let minLag = max(2, Int(sr / config.maxFrequency))
        let maxLag = min(length / 2 - 1, Int(ceil(sr / config.minFrequency)))
        if minLag >= maxLag { return .rejected(reason: AppL10n.t("tuner_pd_lag_invalid")) }

        var bestCorr = -Double.greatestFiniteMagnitude
        var bestLag = minLag
        var correlations: [Double] = []
        correlations.reserveCapacity(maxLag - minLag + 1)
        for lag in minLag...maxLag {
            let c = correlationAtLag(x: x, energy: energy, lag: lag)
            correlations.append(c)
            if c > bestCorr {
                bestCorr = c
                bestLag = lag
            }
        }

        let sorted = correlations.sorted()
        let median = sorted[sorted.count / 2]
        if bestCorr < config.minPeakCorrelation { return .rejected(reason: AppL10n.t("tuner_pd_periodic_weak")) }
        if median > 1e-6 && bestCorr < median * config.minPeakToMedianRatio {
            return .rejected(reason: AppL10n.t("tuner_pd_peak_weak"))
        }

        let refinedLag = parabolicRefineLag(x: x, energy: energy, peakLag: bestLag, minLag: minLag, maxLag: maxLag)
        let hz = sr / refinedLag
        if hz < config.minFrequency || hz > config.maxFrequency { return .rejected(reason: AppL10n.t("tuner_pd_freq_out")) }
        return .pitch(frequencyHz: hz, peakCorrelation: bestCorr, rms: rms)
    }

    private func correlationAtLag(x: [Double], energy: Double, lag: Int) -> Double {
        if lag < 1 || lag >= x.count { return 0 }
        var c = 0.0
        for i in 0..<(x.count - lag) {
            c += x[i] * x[i + lag]
        }
        return c / energy
    }

    private func parabolicRefineLag(x: [Double], energy: Double, peakLag: Int, minLag: Int, maxLag: Int) -> Double {
        let y0 = peakLag > minLag ? correlationAtLag(x: x, energy: energy, lag: peakLag - 1) : 0
        let y1 = correlationAtLag(x: x, energy: energy, lag: peakLag)
        let y2 = peakLag < maxLag ? correlationAtLag(x: x, energy: energy, lag: peakLag + 1) : 0
        let a = (y0 + y2) / 2 - y1
        let b = (y2 - y0) / 2
        if abs(a) < 1e-8 { return Double(peakLag) }
        let delta = max(-0.5, min(0.5, -b / (2 * a)))
        return Double(peakLag) + delta
    }

    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(config.sampleRate)
        try session.setPreferredIOBufferDuration(0.0058)
        try session.setActive(true)
        #endif
    }
}

public extension PitchDetectorConfig {
    /// 人声视唱：默认 `maxFrequency` 420Hz 无法覆盖 B4 以上；略降 RMS/相关峰门槛以适应手机麦。
    static let sightSinging = PitchDetectorConfig(
        sampleRate: 44_100,
        minRms: 0.007,
        minFrequency: 60,
        maxFrequency: 1_300,
        minPeakCorrelation: 0.26,
        minPeakToMedianRatio: 1.18
    )
}

