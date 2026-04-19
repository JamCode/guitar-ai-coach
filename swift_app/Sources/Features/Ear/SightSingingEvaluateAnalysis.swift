import Foundation
import Core

/// 视唱「判定」离线分析：重采样 44.1k、轻高通、端点裁剪、50ms 基频、稳定段、单音/音程与目标比对。
/// 与 `TunerPitchDetector` 同构的自相关估频，便于与实时路径行为接近。
public struct SightSingingPipelineResult: Sendable {
    public let absCentsSamples: [Double]
    public let sampleStepMs: Int
    public let detectedAnswers: [String]
    public let durationMs: Int
}

public enum SightSingingEvaluateAnalysis {
    public static let targetSampleRate: Double = 44_100
    public static let hopMs: Int = 50
    private static let windowSamples: Int = 4_096
    private static let stableWindowMs: Int = 300
    private static let stableSpreadCents: Double = 45
    private static let minStableMs: Int = 200
    private static let pitchConfig = PitchDetectorConfig.sightSinging

    public static func run(monoPCM: [Float], inputSampleRate: Double, targetNotes: [String]) -> SightSingingPipelineResult? {
        let targets = targetNotes.isEmpty ? ["C4"] : targetNotes
        guard monoPCM.count > 4_096 else { return nil }

        var x = resampleIfNeeded(monoPCM, from: inputSampleRate, to: targetSampleRate)
        x = onePoleHighpass(x, sampleRate: targetSampleRate, cutoffHz: 110)
        x = removeDc(x)

        guard let trimmed = trimSilenceEdges(samples: x, sampleRate: targetSampleRate) else { return nil }
        guard trimmed.count > windowSamples + hopSamples(sampleRate: targetSampleRate) else { return nil }

        var f0 = extractF0Curve(samples: trimmed, sampleRate: targetSampleRate, hopMs: hopMs, windowSamples: windowSamples)
        f0 = medianFilterF0(f0, width: 3)
        f0 = rejectGrossPitchJumps(f0, maxSemitoneJump: 10)

        let targetMidis = targets.map { noteNameToMidi($0) }

        if targetMidis.count >= 2 {
            return buildIntervalResult(
                f0: f0,
                targetLowMidi: targetMidis[0],
                targetHighMidi: targetMidis[1],
                targetLowName: targets[0],
                targetHighName: targets[1]
            )
        }
        return buildSingleResult(f0: f0, targetMidi: targetMidis[0])
    }

    // MARK: - Preprocess

    private static func hopSamples(sampleRate: Double) -> Int {
        max(1, Int(sampleRate * Double(hopMs) / 1000.0))
    }

    private static func resampleIfNeeded(_ samples: [Float], from inSR: Double, to outSR: Double) -> [Float] {
        guard abs(inSR - outSR) > 1 else { return samples }
        let ratio = outSR / inSR
        let outCount = max(1, Int(Double(samples.count) * ratio))
        var out = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let srcPos = Double(i) / ratio
            let j0 = Int(floor(srcPos))
            let j1 = min(j0 + 1, samples.count - 1)
            let t = Float(srcPos - Double(j0))
            out[i] = samples[j0] * (1 - t) + samples[j1] * t
        }
        return out
    }

    private static func removeDc(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let mean = samples.reduce(0, +) / Float(samples.count)
        return samples.map { $0 - mean }
    }

    /// 一阶高通，削弱低频隆隆声（非医级降噪，仅轻处理）。
    private static func onePoleHighpass(_ samples: [Float], sampleRate: Double, cutoffHz: Double) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let alpha = Float(exp(-2 * Double.pi * cutoffHz / sampleRate))
        var out = samples
        var prevIn: Float = 0
        var prevOut: Float = 0
        for i in 0..<out.count {
            let xi = out[i]
            let yo = alpha * (prevOut + xi - prevIn)
            prevIn = xi
            prevOut = yo
            out[i] = yo
        }
        return out
    }

    /// 按短时 RMS 相对峰值裁前导/尾随静音。
    private static func trimSilenceEdges(samples: [Float], sampleRate: Double) -> [Float]? {
        let frame = max(256, Int(sampleRate * 0.02))
        guard samples.count > frame * 4 else { return nil }
        var rms: [Float] = []
        var i = 0
        while i + frame <= samples.count {
            var e: Float = 0
            for k in i..<(i + frame) { e += samples[k] * samples[k] }
            rms.append(sqrt(e / Float(frame)))
            i += frame / 2
        }
        guard let peak = rms.max(), peak > 1e-6 else { return nil }
        let startTh = peak * 0.08
        let endTh = peak * 0.06
        guard let firstIdx = rms.firstIndex(where: { $0 >= startTh }),
              let lastIdx = rms.lastIndex(where: { $0 >= endTh }) else { return nil }
        let startSample = max(0, firstIdx * (frame / 2) - frame)
        let endSample = min(samples.count, (lastIdx + 1) * (frame / 2) + frame)
        guard endSample - startSample > frame * 2 else { return nil }
        return Array(samples[startSample..<endSample])
    }

    // MARK: - F0

    private static func extractF0Curve(samples: [Float], sampleRate: Double, hopMs: Int, windowSamples: Int) -> [Double?] {
        let hop = max(1, Int(sampleRate * Double(hopMs) / 1000.0))
        var out: [Double?] = []
        var pos = 0
        while pos + windowSamples <= samples.count {
            let slice = Array(samples[pos..<(pos + windowSamples)]).map(Double.init)
            out.append(estimateHzAutocorr(samples: slice, sampleRate: sampleRate))
            pos += hop
        }
        return out
    }

    /// 与 `TunerPitchDetector.estimatePitch` 等价的自相关基频估计（简化返回 Hz 或 nil）。
    private static func estimateHzAutocorr(samples: [Double], sampleRate: Double) -> Double? {
        var x = samples
        let length = x.count
        guard length >= 1024 else { return nil }
        let mean = x.reduce(0, +) / Double(length)
        var energy = 0.0
        for i in 0..<length {
            x[i] -= mean
            energy += x[i] * x[i]
        }
        if energy <= 1e-18 { return nil }
        let rms = sqrt(energy / Double(length))
        if rms < pitchConfig.minRms { return nil }

        let sr = sampleRate
        let minLag = max(2, Int(sr / pitchConfig.maxFrequency))
        let maxLag = min(length / 2 - 1, Int(ceil(sr / pitchConfig.minFrequency)))
        if minLag >= maxLag { return nil }

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
        if bestCorr < pitchConfig.minPeakCorrelation { return nil }
        if median > 1e-6 && bestCorr < median * pitchConfig.minPeakToMedianRatio { return nil }

        let refinedLag = parabolicRefineLag(x: x, energy: energy, peakLag: bestLag, minLag: minLag, maxLag: maxLag)
        let hz = sr / refinedLag
        if hz < pitchConfig.minFrequency || hz > pitchConfig.maxFrequency { return nil }
        return hz
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

    private static func medianFilterF0(_ series: [Double?], width: Int) -> [Double?] {
        let w = max(1, width / 2)
        var out = series
        for i in 0..<series.count {
            let lo = max(0, i - w)
            let hi = min(series.count - 1, i + w)
            let vals = (lo...hi).compactMap { series[$0] }
            guard !vals.isEmpty else { continue }
            let s = vals.sorted()
            out[i] = s[s.count / 2]
        }
        return out
    }

    private static func rejectGrossPitchJumps(_ series: [Double?], maxSemitoneJump: Double) -> [Double?] {
        var out = series
        for i in 1..<out.count {
            guard let a = out[i], let b = out[i - 1], a > 0, b > 0 else { continue }
            let semis = abs(12 * log2(a / b))
            if semis > maxSemitoneJump { out[i] = nil }
        }
        return out
    }

    // MARK: - Stable segments

    private static func stableMask(for midis: [Double?]) -> [Bool] {
        let n = midis.count
        guard n > 0 else { return [] }
        let w = max(2, stableWindowMs / hopMs)
        var mask = Array(repeating: false, count: n)
        guard w <= n else { return mask }
        for i in 0...(n - w) {
            let slice = (i..<(i + w)).compactMap { midis[$0] }
            guard slice.count >= w - 1 else { continue }
            guard let lo = slice.min(), let hi = slice.max() else { continue }
            let spreadCents = (hi - lo) * 100
            if spreadCents <= stableSpreadCents {
                for j in i..<(i + w) { mask[j] = true }
            }
        }
        return mask
    }

    private static func runs(of mask: [Bool]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var i = 0
        while i < mask.count {
            if !mask[i] { i += 1; continue }
            let start = i
            while i < mask.count, mask[i] { i += 1 }
            ranges.append(start..<i)
        }
        return ranges
    }

    /// `midiPerHop` 元素已是 MIDI（非 Hz）；返回该窗口内有效帧的平均 MIDI。
    private static func meanMidi(in range: Range<Int>, midiPerHop: [Double?]) -> Double? {
        let vals = range.compactMap { midiPerHop[$0] }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    // MARK: - Results

    private static func buildSingleResult(f0: [Double?], targetMidi: Double) -> SightSingingPipelineResult? {
        let midis: [Double?] = f0.map { hz in
            hz.map { 69 + 12 * log2($0 / 440) }
        }
        let mask = stableMask(for: midis)
        let segs = runs(of: mask).filter { ($0.count * hopMs) >= minStableMs }
        let useRange: Range<Int>
        if let best = segs.max(by: { $0.count < $1.count }) {
            useRange = best
        } else {
            useRange = 0..<midis.count
        }
        guard useRange.count > 0 else { return nil }
        guard let meanM = meanMidi(in: useRange, midiPerHop: midis) else { return nil }

        var absSamples: [Double] = []
        absSamples.reserveCapacity(useRange.count)
        for idx in useRange {
            guard let m = midis[idx] else { continue }
            absSamples.append(abs((m - targetMidi) * 100))
        }
        guard !absSamples.isEmpty else { return nil }

        let durMs = f0.count * hopMs
        let detected = midiToSightNote(Int(meanM.rounded()))
        return SightSingingPipelineResult(
            absCentsSamples: absSamples,
            sampleStepMs: hopMs,
            detectedAnswers: [detected],
            durationMs: durMs
        )
    }

    private static func buildIntervalResult(
        f0: [Double?],
        targetLowMidi: Double,
        targetHighMidi: Double,
        targetLowName: String,
        targetHighName: String
    ) -> SightSingingPipelineResult? {
        let midis: [Double?] = f0.map { hz in
            hz.map { 69 + 12 * log2($0 / 440) }
        }
        let mask = stableMask(for: midis)
        let segs = runs(of: mask).filter { ($0.count * hopMs) >= minStableMs }.sorted { $0.lowerBound < $1.lowerBound }
        let (s0, s1): (Range<Int>, Range<Int>)
        if segs.count >= 2 {
            s0 = segs[0]
            s1 = segs[1]
        } else {
            // 仅一段稳定音高时：按时间对半切分，尽量保留音程题的弱降级路径。
            let n = midis.count
            guard n >= 6 else { return nil }
            let mid = max(2, n / 2)
            s0 = 0..<mid
            s1 = mid..<n
        }
        guard let m0 = meanMidi(in: s0, midiPerHop: midis), let m1 = meanMidi(in: s1, midiPerHop: midis) else { return nil }
        let expected = targetHighMidi - targetLowMidi
        let observed = m1 - m0
        let intervalErrCents = abs(observed - expected) * 100

        var absSamples: [Double] = []
        for idx in s0 {
            if let mm = midis[idx] { absSamples.append(abs((mm - targetLowMidi) * 100)) }
        }
        for idx in s1 {
            if let mm = midis[idx] { absSamples.append(abs((mm - targetHighMidi) * 100)) }
        }
        if !absSamples.isEmpty {
            absSamples.append(intervalErrCents)
        } else {
            absSamples = [intervalErrCents]
        }

        let n0 = midiToSightNote(Int(round(m0)))
        let n1 = midiToSightNote(Int(round(m1)))
        let durMs = f0.count * hopMs
        return SightSingingPipelineResult(
            absCentsSamples: absSamples,
            sampleStepMs: hopMs,
            detectedAnswers: [n0, n1],
            durationMs: durMs
        )
    }

    // MARK: - Note helpers（与仓库出题格式一致）

    private static func noteNameToMidi(_ note: String) -> Double {
        let upper = note.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let regex = try? NSRegularExpression(pattern: "^([A-G])(#?)(\\d)$")
        let range = NSRange(location: 0, length: upper.utf16.count)
        guard
            let match = regex?.firstMatch(in: upper, range: range),
            match.numberOfRanges == 4,
            let n1 = Range(match.range(at: 1), in: upper),
            let n2 = Range(match.range(at: 2), in: upper),
            let n3 = Range(match.range(at: 3), in: upper)
        else {
            return 60
        }
        let name = String(upper[n1]) + String(upper[n2])
        let octave = Int(upper[n3]) ?? 4
        let idx = PitchMath.noteNames.firstIndex(of: name) ?? 0
        return Double((octave + 1) * 12 + idx)
    }

    private static func midiToSightNote(_ midi: Int) -> String {
        let note = PitchMath.noteNames[((midi % 12) + 12) % 12]
        let octave = midi / 12 - 1
        return "\(note)\(octave)"
    }
}
