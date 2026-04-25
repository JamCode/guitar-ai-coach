import AVFoundation
import Foundation

/// 基频估计算法：
/// - `.autocorrelation`：归一化自相关 + 峰值/中位数门槛（原实现，继续被 `sightSinging` preset 使用）。
/// - `.nsdf`：McLeod Pitch Method（NSDF + 「首个高于 clarity 阈值的局部极大值」），
///   对吉他常见的"基频较弱 + 2×/3× 泛音较强"场景更稳，能显著抑制八度错。
public enum PitchDetectionAlgorithm: String, Sendable {
    case autocorrelation
    case nsdf
}

public struct PitchDetectorConfig: Sendable {
    public var sampleRate: Double
    public var minRms: Double
    public var minFrequency: Double
    public var maxFrequency: Double
    public var minPeakCorrelation: Double
    public var minPeakToMedianRatio: Double
    /// 「目标优先窗口」的半宽（单位 cent）。非 `nil` 时，若运行期设置了目标基频，
    /// 自相关峰搜索会优先限制在 `target * 2^(±halfWidth/1200)` 对应的 lag 区间，
    /// 仅当窗口内无合格峰再回退全局扫描。用于压低 2×/3× 倍频峰误识的概率。
    public var targetWindowHalfCents: Double?
    /// 算法选择。默认沿用 `.autocorrelation`，避免打扰 `sightSinging` 等已有调用方。
    public var algorithm: PitchDetectionAlgorithm
    /// NSDF clarity 阈值 `k`：从小到大枚举局部极大值，第一个满足 `value ≥ k × globalMax` 的极大值被选中。
    /// 经典 MPM 取 0.9，值越高越倾向锁定第一周期（更抗八度错），越低越灵敏。
    public var nsdfClarityThreshold: Double
    /// NSDF 主峰绝对值下限；低于此值视为周期性不足（环境噪声、弱拨弦残响）。
    public var nsdfMinPeakValue: Double

    public init(
        sampleRate: Double = 44_100,
        minRms: Double = 0.018,
        minFrequency: Double = 70,
        maxFrequency: Double = 420,
        minPeakCorrelation: Double = 0.34,
        minPeakToMedianRatio: Double = 1.35,
        targetWindowHalfCents: Double? = nil,
        algorithm: PitchDetectionAlgorithm = .autocorrelation,
        nsdfClarityThreshold: Double = 0.9,
        nsdfMinPeakValue: Double = 0.4
    ) {
        self.sampleRate = sampleRate
        self.minRms = minRms
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
        self.minPeakCorrelation = minPeakCorrelation
        self.minPeakToMedianRatio = minPeakToMedianRatio
        self.targetWindowHalfCents = targetWindowHalfCents
        self.algorithm = algorithm
        self.nsdfClarityThreshold = nsdfClarityThreshold
        self.nsdfMinPeakValue = nsdfMinPeakValue
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
    /// 设置当前目标基频（Hz）。实现可利用该值在候选 lag 上优先搜索，
    /// 以抑制自相关在 2×/3× 倍频处的虚假峰（典型症状：低音弦被识别成高八度）。
    /// 传 `nil` 表示没有已知目标，此时回退到全局扫描。
    func setTargetHz(_ hz: Double?)
}

public extension PitchDetecting {
    /// 默认实现：不提供目标优先，保留 legacy 调用点不需要修改。
    func setTargetHz(_ hz: Double?) {}
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
    /// 运行期目标基频。调用方（如 `TunerViewModel`）在选弦时通过 `setTargetHz` 注入，
    /// 仅当 `config.targetWindowHalfCents != nil` 时真正影响搜索策略。
    private var targetHz: Double?
    /// 保护 `targetHz` 的读写（来自主线程的 UI 操作 vs. `queue` 上的分析线程）。
    private let targetLock = NSLock()

    public init(config: PitchDetectorConfig = PitchDetectorConfig()) {
        self.config = config
        self.analysisSampleRate = config.sampleRate
    }

    public func setTargetHz(_ hz: Double?) {
        targetLock.lock()
        targetHz = hz
        targetLock.unlock()
    }

    private func currentTargetHz() -> Double? {
        targetLock.lock()
        defer { targetLock.unlock() }
        return targetHz
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
        return TunerPitchEstimator.estimate(
            samples: samples,
            sampleRate: analysisSampleRate,
            config: config,
            targetHz: currentTargetHz()
        )
    }
}

/// 纯函数包装，便于单测离线驱动（无 AVAudioEngine 依赖），也与 `TunerPitchDetector` 共享同一份算法。
public enum TunerPitchEstimator {
    public static func estimate(
        samples: [Float],
        sampleRate: Double,
        config: PitchDetectorConfig,
        targetHz: Double?
    ) -> PitchFrameResult {
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

        switch config.algorithm {
        case .autocorrelation:
            return estimateAutocorrelation(
                x: x,
                energy: energy,
                rms: rms,
                sampleRate: sampleRate,
                config: config,
                targetHz: targetHz
            )
        case .nsdf:
            return estimateNSDF(
                x: x,
                rms: rms,
                sampleRate: sampleRate,
                config: config,
                targetHz: targetHz
            )
        }
    }

    // MARK: - Autocorrelation branch (legacy / sight-singing)

    private static func estimateAutocorrelation(
        x: [Double],
        energy: Double,
        rms: Double,
        sampleRate: Double,
        config: PitchDetectorConfig,
        targetHz: Double?
    ) -> PitchFrameResult {
        let length = x.count
        let sr = sampleRate
        let minLag = max(2, Int(sr / config.maxFrequency))
        let maxLag = min(length / 2 - 1, Int(ceil(sr / config.minFrequency)))
        if minLag >= maxLag { return .rejected(reason: AppL10n.t("tuner_pd_lag_invalid")) }

        var correlations: [Double] = []
        correlations.reserveCapacity(maxLag - minLag + 1)
        var globalBestCorr = -Double.greatestFiniteMagnitude
        var globalBestLag = minLag
        for lag in minLag...maxLag {
            let c = correlationAtLag(x: x, energy: energy, lag: lag)
            correlations.append(c)
            if c > globalBestCorr {
                globalBestCorr = c
                globalBestLag = lag
            }
        }

        let sorted = correlations.sorted()
        let median = sorted[sorted.count / 2]
        let peakThreshold = max(config.minPeakCorrelation, median * config.minPeakToMedianRatio)

        var bestCorr = globalBestCorr
        var bestLag = globalBestLag
        if let target = targetHz,
           let halfCents = config.targetWindowHalfCents,
           halfCents > 0,
           target > 0 {
            // 把目标基频 ±halfCents 换算成 lag 窗口：注意频率 ↔ lag 反比，低频对应大 lag。
            let ratio = pow(2.0, halfCents / 1200.0)
            let targetLagLow = max(minLag, Int(floor(sr / (target * ratio))))
            let targetLagHigh = min(maxLag, Int(ceil(sr / (target / ratio))))
            if targetLagLow <= targetLagHigh {
                var windowBestCorr = -Double.greatestFiniteMagnitude
                var windowBestLag = targetLagLow
                for lag in targetLagLow...targetLagHigh {
                    let c = correlations[lag - minLag]
                    if c > windowBestCorr {
                        windowBestCorr = c
                        windowBestLag = lag
                    }
                }
                // 只要窗口内有「足够突出」的峰（超过同一阈值），就采纳它；否则回退全局峰，
                // 避免目标弦尚未拨响时被环境噪声内的小峰带偏。
                if windowBestCorr >= peakThreshold {
                    bestCorr = windowBestCorr
                    bestLag = windowBestLag
                }
            }
        }

        if bestCorr < config.minPeakCorrelation { return .rejected(reason: AppL10n.t("tuner_pd_periodic_weak")) }
        if median > 1e-6 && bestCorr < median * config.minPeakToMedianRatio {
            return .rejected(reason: AppL10n.t("tuner_pd_peak_weak"))
        }

        let refinedLag = parabolicRefineLag(x: x, energy: energy, peakLag: bestLag, minLag: minLag, maxLag: maxLag)
        let hz = sr / refinedLag
        if hz < config.minFrequency || hz > config.maxFrequency { return .rejected(reason: AppL10n.t("tuner_pd_freq_out")) }
        return .pitch(frequencyHz: hz, peakCorrelation: bestCorr, rms: rms)
    }

    // MARK: - NSDF / McLeod Pitch Method branch

    /// McLeod Pitch Method：
    /// 1. 计算归一化方差差函数 NSDF(τ) = 2·r(τ) / m(τ)，其中 r(τ) 为自相关、m(τ) 为能量累加；
    ///    NSDF 的取值在 [-1, 1]，并且理论基频对应 τ 处 NSDF(τ) ≈ 1。
    /// 2. 枚举所有"正零交叉之后、下次负零交叉之前"的局部极大值。
    /// 3. 选择第一个满足 `value ≥ k × globalMaxValue` 的局部极大值（k ≈ 0.9）；
    ///    这样即便倍频 τ 有更大 NSDF 值，也会优先选短周期 τ，抑制八度错。
    /// 4. 对选中的 τ 抛物插值亚样本精度后换算为频率。
    private static func estimateNSDF(
        x: [Double],
        rms: Double,
        sampleRate: Double,
        config: PitchDetectorConfig,
        targetHz: Double?
    ) -> PitchFrameResult {
        let length = x.count
        let sr = sampleRate
        let minLag = max(2, Int(sr / config.maxFrequency))
        let maxLag = min(length / 2 - 1, Int(ceil(sr / config.minFrequency)))
        if minLag >= maxLag { return .rejected(reason: "滞后范围无效") }

        var nsdf = [Double](repeating: 0, count: maxLag + 1)
        // McLeod 的 m'(τ) = Σ_{i=0}^{N-τ-1} ( x[i]^2 + x[i+τ]^2 )；NSDF(τ) = 2·r(τ) / m'(τ)，r(τ) 为同范围的自相关。
        // m'(0) = 2·Σ x[i]^2（i ∈ [0, N)）；由 m'(τ) 递推到 m'(τ+1) 时，两端各丢一个样本：
        //   m'(τ+1) = m'(τ) - x[τ]^2 - x[N-τ-1]^2。
        var mPrime = 0.0
        for i in 0..<length { mPrime += 2 * x[i] * x[i] }
        nsdf[0] = 1.0
        for tau in 1...maxLag {
            // 先按上一步递推更新 m'(τ)：此处 "τ" 对应公式里 "τ+1"，因此丢掉的两端下标为 τ-1 与 N-τ。
            let lowIndex = tau - 1
            let highIndex = length - tau
            if lowIndex >= 0 && lowIndex < length {
                mPrime -= x[lowIndex] * x[lowIndex]
            }
            if highIndex >= 0 && highIndex < length {
                mPrime -= x[highIndex] * x[highIndex]
            }
            var r = 0.0
            let upper = length - tau
            var i = 0
            while i < upper {
                r += x[i] * x[i + tau]
                i += 1
            }
            if mPrime > 1e-18 {
                nsdf[tau] = 2 * r / mPrime
            } else {
                nsdf[tau] = 0
            }
        }

        // 找出 [minLag, maxLag] 内所有"正值区间内的局部极大值"。
        // 正值区间：从 nsdf[τ] 由负转正开始，到再次由正转负结束。
        var peakLags: [Int] = []
        var peakValues: [Double] = []
        var inPositiveZone = false
        var zoneBestLag = 0
        var zoneBestValue = -Double.greatestFiniteMagnitude
        for tau in minLag...maxLag {
            let v = nsdf[tau]
            if v > 0 {
                if !inPositiveZone {
                    inPositiveZone = true
                    zoneBestLag = tau
                    zoneBestValue = v
                } else if v > zoneBestValue {
                    zoneBestValue = v
                    zoneBestLag = tau
                }
            } else {
                if inPositiveZone {
                    peakLags.append(zoneBestLag)
                    peakValues.append(zoneBestValue)
                    inPositiveZone = false
                    zoneBestValue = -Double.greatestFiniteMagnitude
                }
            }
        }
        if inPositiveZone {
            peakLags.append(zoneBestLag)
            peakValues.append(zoneBestValue)
        }

        if peakLags.isEmpty { return .rejected(reason: "无周期性峰") }

        let globalMax = peakValues.max() ?? 0
        if globalMax < config.nsdfMinPeakValue { return .rejected(reason: "周期性不足") }

        let threshold = config.nsdfClarityThreshold * globalMax
        // 默认选「第一个 ≥ threshold 的局部极大值」。
        var chosenLag = peakLags[0]
        var chosenValue = peakValues[0]
        for idx in 0..<peakLags.count where peakValues[idx] >= threshold {
            chosenLag = peakLags[idx]
            chosenValue = peakValues[idx]
            break
        }

        // 目标优先：若设置了目标基频 + 半宽窗口，在窗口内选择 NSDF 最大的峰（仍要求达到 clarity 阈值），
        // 这是针对吉他低音弦、在 2T/3T 上可能恰好也过阈值的最终兜底。
        if let target = targetHz,
           let halfCents = config.targetWindowHalfCents,
           halfCents > 0,
           target > 0 {
            let ratio = pow(2.0, halfCents / 1200.0)
            let targetLagLow = max(minLag, Int(floor(sr / (target * ratio))))
            let targetLagHigh = min(maxLag, Int(ceil(sr / (target / ratio))))
            var windowBestLag = -1
            var windowBestValue = -Double.greatestFiniteMagnitude
            for idx in 0..<peakLags.count {
                let lag = peakLags[idx]
                if lag >= targetLagLow && lag <= targetLagHigh {
                    if peakValues[idx] > windowBestValue {
                        windowBestValue = peakValues[idx]
                        windowBestLag = lag
                    }
                }
            }
            if windowBestLag > 0 && windowBestValue >= threshold {
                chosenLag = windowBestLag
                chosenValue = windowBestValue
            }
        }

        // 抛物插值得到亚样本精度：用 NSDF 自身在 (chosenLag-1, chosenLag, chosenLag+1) 上拟合。
        let refinedLag = parabolicRefineNSDF(nsdf: nsdf, peakLag: chosenLag, minLag: minLag, maxLag: maxLag)
        let hz = sr / refinedLag
        if hz < config.minFrequency || hz > config.maxFrequency { return .rejected(reason: "频率越界") }
        return .pitch(frequencyHz: hz, peakCorrelation: chosenValue, rms: rms)
    }

    private static func parabolicRefineNSDF(nsdf: [Double], peakLag: Int, minLag: Int, maxLag: Int) -> Double {
        let y1 = nsdf[peakLag]
        let y0 = peakLag > minLag ? nsdf[peakLag - 1] : y1
        let y2 = peakLag < maxLag ? nsdf[peakLag + 1] : y1
        let a = (y0 + y2) / 2 - y1
        let b = (y2 - y0) / 2
        if abs(a) < 1e-8 { return Double(peakLag) }
        let delta = max(-0.5, min(0.5, -b / (2 * a)))
        return Double(peakLag) + delta
    }

    private static func correlationAtLag(x: [Double], energy: Double, lag: Int) -> Double {
        if lag < 1 || lag >= x.count { return 0 }
        var c = 0.0
        for i in 0..<(x.count - lag) {
            c += x[i] * x[i + lag]
        }
        return c / energy
    }

    private static func parabolicRefineLag(x: [Double], energy: Double, peakLag: Int, minLag: Int, maxLag: Int) -> Double {
        let y0 = peakLag > minLag ? correlationAtLag(x: x, energy: energy, lag: peakLag - 1) : 0
        let y1 = correlationAtLag(x: x, energy: energy, lag: peakLag)
        let y2 = peakLag < maxLag ? correlationAtLag(x: x, energy: energy, lag: peakLag + 1) : 0
        let a = (y0 + y2) / 2 - y1
        let b = (y2 - y0) / 2
        if abs(a) < 1e-8 { return Double(peakLag) }
        let delta = max(-0.5, min(0.5, -b / (2 * a)))
        return Double(peakLag) + delta
    }
}

extension TunerPitchDetector {
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

    /// 吉他调音：
    /// - 全局频率范围 60–700 Hz：下界兼容 Drop-C/低把位泛音，上界略高于 E4 (329.63Hz) 但小于其 2× 倍频，
    ///   即便发生 2 倍周期误匹配也会在 670Hz 内被截断。
    /// - `targetWindowHalfCents = 300`：当调用方设置当前目标弦后，搜索优先在 target ±3 半音内进行。
    /// - `algorithm = .nsdf`：改用 McLeod Pitch Method（NSDF + 首个过阈值的局部极大值），
    ///   从算法层面消除低音弦 2×/3× 泛音误识的八度错，而不是只靠「目标窗口」兜底。
    /// - `minPeakCorrelation / minPeakToMedianRatio` 仍由 AC 分支消费，NSDF 分支走 `nsdfClarityThreshold` / `nsdfMinPeakValue`。
    static let tunerGuitar = PitchDetectorConfig(
        sampleRate: 44_100,
        minRms: 0.018,
        minFrequency: 60,
        maxFrequency: 700,
        minPeakCorrelation: 0.34,
        minPeakToMedianRatio: 1.35,
        targetWindowHalfCents: 300,
        algorithm: .nsdf,
        nsdfClarityThreshold: 0.9,
        nsdfMinPeakValue: 0.4
    )
}

