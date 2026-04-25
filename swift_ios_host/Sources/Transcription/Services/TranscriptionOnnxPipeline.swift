import Accelerate
import Core
import Foundation

enum TranscriptionCQTFeatureExtractorError: LocalizedError {
    case fftUnavailable

    var errorDescription: String? {
        switch self {
        case .fftUnavailable:
            return AppL10n.t("onnx_spectrum_unavailable")
        }
    }
}

struct TranscriptionFeatureTensor: Equatable {
    let values: [Float]
    let shape: [Int]
}

struct TranscriptionCQTFeatureExtractor {
    private let targetSampleRate: Double
    private let hopLength: Int
    private let binsPerOctave: Int
    private let numOctaves: Int
    private let chunkDurationSec: Double
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let window: [Float]
    private let fft: vDSP.FFT<DSPSplitComplex>?
    private let filterBins: [FrequencyFilterBin]

    init(
        targetSampleRate: Double = 22_050,
        hopLength: Int = 512,
        binsPerOctave: Int = 24,
        numOctaves: Int = 6,
        chunkDurationSec: Double = 20,
        fftSize: Int = 4_096
    ) {
        self.targetSampleRate = targetSampleRate
        self.hopLength = hopLength
        self.binsPerOctave = binsPerOctave
        self.numOctaves = numOctaves
        self.chunkDurationSec = chunkDurationSec
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
        self.fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)
        self.filterBins = Self.makeFilterBins(
            sampleRate: targetSampleRate,
            fftSize: fftSize,
            binsPerOctave: binsPerOctave,
            numOctaves: numOctaves
        )
    }

    var frameDurationMs: Int {
        Int((Double(hopLength) / targetSampleRate * 1000).rounded())
    }

    var samplesPerChunk: Int {
        Int((targetSampleRate * chunkDurationSec).rounded())
    }

    func extractChunk(samples: [Float], sampleRate: Double) throws -> TranscriptionFeatureTensor {
        guard let fft else {
            throw TranscriptionCQTFeatureExtractorError.fftUnavailable
        }

        let normalized = normalize(resample(samples: samples, from: sampleRate, to: targetSampleRate))
        let padded = padOrTrim(normalized, to: samplesPerChunk)
        let frameCount = Int(ceil(Double(samplesPerChunk) / Double(hopLength)))
        let binCount = binsPerOctave * numOctaves
        var values = [Float](repeating: 0, count: binCount * frameCount)

        var frame = [Float](repeating: 0, count: fftSize)
        var windowed = [Float](repeating: 0, count: fftSize)
        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var interleaved = [DSPComplex](repeating: DSPComplex(real: 0, imag: 0), count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        var amplitudes = [Float](repeating: 0, count: fftSize / 2)

        for frameIndex in 0..<frameCount {
            frame = Array(repeating: 0, count: fftSize)

            let start = frameIndex * hopLength
            if start < padded.count {
                let available = min(fftSize, padded.count - start)
                frame.replaceSubrange(0..<available, with: padded[start..<(start + available)])
            }

            vDSP.multiply(frame, window, result: &windowed)
            for index in 0..<(fftSize / 2) {
                interleaved[index] = DSPComplex(real: windowed[index * 2], imag: windowed[index * 2 + 1])
            }

            real.withUnsafeMutableBufferPointer { realPtr in
                imag.withUnsafeMutableBufferPointer { imagPtr in
                    var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    interleaved.withUnsafeBufferPointer { src in
                        vDSP_ctoz(src.baseAddress!, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                    fft.forward(input: split, output: &split)
                    vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                }
            }

            for index in 0..<magnitudes.count {
                amplitudes[index] = sqrt(max(0, magnitudes[index]))
            }

            for (binIndex, filter) in filterBins.enumerated() {
                var sum: Float = 0
                let startIndex = filter.startIndex
                for (offset, weight) in filter.weights.enumerated() {
                    sum += weight * amplitudes[startIndex + offset]
                }
                values[binIndex * frameCount + frameIndex] = log1p(sum)
            }
        }

        return TranscriptionFeatureTensor(values: values, shape: [1, 1, binCount, frameCount])
    }

    private func resample(samples: [Float], from sourceRate: Double, to destinationRate: Double) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard abs(sourceRate - destinationRate) > 1 else { return samples }

        let targetCount = max(1, Int((Double(samples.count) * destinationRate / sourceRate).rounded()))
        let maxIndex = samples.count - 1
        return (0..<targetCount).map { targetIndex in
            let position = Double(targetIndex) * sourceRate / destinationRate
            let lowerIndex = min(maxIndex, Int(position.rounded(.down)))
            let upperIndex = min(maxIndex, lowerIndex + 1)
            let fraction = Float(position - Double(lowerIndex))
            let lower = samples[lowerIndex]
            let upper = samples[upperIndex]
            return lower + (upper - lower) * fraction
        }
    }

    private func normalize(_ samples: [Float]) -> [Float] {
        // 以绝对值第 99 百分位作为归一化参考，
        // 避免偶发尖峰（鼓点 / 爆音 / 直流毛刺）把整段能量压扁，
        // 继而导致 ONNX sigmoid 普遍拿不到阈值。
        // 离线 48 例 benchmark 下对 triad root +8.3pp、progression root +4.2pp，
        // 其它类别不回退，见 benchmarks/chord_bench/reports/ab_chunk_norm.md。
        guard !samples.isEmpty else { return samples }
        let scale = Self.absolutePercentile(samples, percentile: 0.99)
        guard scale > 0 else { return samples }
        return samples.map { max(-1.0, min(1.0, $0 / scale)) }
    }

    private static func absolutePercentile(_ samples: [Float], percentile: Double) -> Float {
        // Quickselect（nth_element）求绝对值序列的百分位数。
        // 避免 O(n log n) 全排序：每 20s chunk ≈ 441k 样本，全排序对 CPU 过重。
        precondition(percentile >= 0.0 && percentile <= 1.0)
        var abs_ = samples.map { abs($0) }
        let n = abs_.count
        let k = max(0, min(n - 1, Int((Double(n - 1) * percentile).rounded())))
        return abs_.withUnsafeMutableBufferPointer { buffer in
            nthElement(buffer, k: k)
            return buffer[k]
        }
    }

    private static func nthElement(_ buffer: UnsafeMutableBufferPointer<Float>, k: Int) {
        // 迭代版 quickselect，Lomuto 分区，对存在大量重复值的音频样本也安全。
        var lo = 0
        var hi = buffer.count - 1
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            // three-element median-of-three 作为 pivot，抗对已排序/近排序输入的退化
            let pivot = Self.medianOfThree(buffer[lo], buffer[mid], buffer[hi])
            var i = lo
            var j = hi
            while i <= j {
                while buffer[i] < pivot { i += 1 }
                while buffer[j] > pivot { j -= 1 }
                if i <= j {
                    buffer.swapAt(i, j)
                    i += 1
                    j -= 1
                }
            }
            if k <= j { hi = j }
            else if k >= i { lo = i }
            else { return }
        }
    }

    private static func medianOfThree(_ a: Float, _ b: Float, _ c: Float) -> Float {
        if a < b {
            if b < c { return b }
            return a < c ? c : a
        } else {
            if a < c { return a }
            return b < c ? c : b
        }
    }

    private func padOrTrim(_ samples: [Float], to count: Int) -> [Float] {
        if samples.count == count {
            return samples
        }
        if samples.count > count {
            return Array(samples.prefix(count))
        }
        return samples + Array(repeating: 0, count: count - samples.count)
    }

    private static func makeFilterBins(
        sampleRate: Double,
        fftSize: Int,
        binsPerOctave: Int,
        numOctaves: Int
    ) -> [FrequencyFilterBin] {
        let nyquistIndex = fftSize / 2 - 1
        let resolution = sampleRate / Double(fftSize)
        let startFrequency = 32.70319566257483 // C1
        let totalBins = binsPerOctave * numOctaves
        let binRatio = pow(2.0, 1.0 / Double(binsPerOctave))

        var result: [FrequencyFilterBin] = []
        result.reserveCapacity(totalBins)

        for bin in 0..<totalBins {
            let centerFreq = startFrequency * pow(2.0, Double(bin) / Double(binsPerOctave))
            let centerIdx = centerFreq / resolution
            let leftEdgeIdx = (centerFreq / binRatio) / resolution
            let rightEdgeIdx = (centerFreq * binRatio) / resolution

            // 低频段 f/Q 小于 1 个 FFT bin 时强制兜底到 1 个 bin，
            // 避免退化成 0 权重；受 fftSize 物理上限约束。
            let leftSpan = max(1.0, centerIdx - leftEdgeIdx)
            let rightSpan = max(1.0, rightEdgeIdx - centerIdx)

            var startIndex = Int((centerIdx - leftSpan).rounded(.down))
            var endIndex = Int((centerIdx + rightSpan).rounded(.up))
            startIndex = max(1, min(nyquistIndex, startIndex))
            endIndex = max(startIndex, min(nyquistIndex, endIndex))

            var weights: [Float] = []
            weights.reserveCapacity(endIndex - startIndex + 1)
            var weightSum: Float = 0
            for k in startIndex...endIndex {
                let distance = Double(k) - centerIdx
                let span = distance >= 0 ? rightSpan : leftSpan
                let w = max(0.0, 1.0 - abs(distance) / span)
                let weight = Float(w)
                weights.append(weight)
                weightSum += weight
            }

            result.append(
                FrequencyFilterBin(
                    startIndex: startIndex,
                    weights: weights,
                    weightSum: weightSum
                )
            )
        }

        return result
    }
}

private struct FrequencyFilterBin {
    let startIndex: Int
    let weights: [Float]
    let weightSum: Float
}

enum OnnxChordLabelDecoder {
    private static let intervalSymbols = [
        "1", "b9", "9", "b3", "3", "4", "b5", "5", "b6", "6", "b7", "7",
    ]
    private static let noteNames = [
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
    ]

    static func decodeFrames(
        rootIndices: [Int],
        bassIndices: [Int],
        chordProbabilities: [[Double]],
        frameDurationMs: Int,
        threshold: Double,
        minDurationMs: Int
    ) -> [RawChordFrame] {
        guard
            rootIndices.count == bassIndices.count,
            rootIndices.count == chordProbabilities.count,
            frameDurationMs > 0
        else {
            return []
        }

        var merged: [RawChordFrame] = []
        var pendingStart = 0
        var pendingLabel = decodeLabel(
            rootIndex: rootIndices[0],
            bassIndex: bassIndices[0],
            chordProbabilities: chordProbabilities[0],
            threshold: threshold
        )

        for frameIndex in 1..<rootIndices.count {
            let label = decodeLabel(
                rootIndex: rootIndices[frameIndex],
                bassIndex: bassIndices[frameIndex],
                chordProbabilities: chordProbabilities[frameIndex],
                threshold: threshold
            )
            guard label != pendingLabel else { continue }
            merged.append(
                RawChordFrame(
                    startMs: pendingStart * frameDurationMs,
                    endMs: frameIndex * frameDurationMs,
                    chord: pendingLabel
                )
            )
            pendingStart = frameIndex
            pendingLabel = label
        }

        merged.append(
            RawChordFrame(
                startMs: pendingStart * frameDurationMs,
                endMs: rootIndices.count * frameDurationMs,
                chord: pendingLabel
            )
        )

        return removeShortFrames(
            bridgeSameNameSegments(
                merged.filter { $0.chord != "N" },
                maxGapMs: minDurationMs
            ),
            minDurationMs: minDurationMs
        )
    }

    static func decodeLabel(
        rootIndex: Int,
        bassIndex: Int,
        chordProbabilities: [Double],
        threshold: Double
    ) -> String {
        guard rootIndex >= 0, rootIndex < 13 else { return "N" }
        guard bassIndex >= 0, bassIndex < 13 else { return "N" }
        guard chordProbabilities.count == 12 else { return "N" }
        guard rootIndex != 12 else { return "N" }

        var intervals: Set<Int> = [0]
        for absoluteIndex in 0..<12 where chordProbabilities[absoluteIndex] > threshold {
            let relativeIndex = (absoluteIndex - rootIndex + 12) % 12
            intervals.insert(relativeIndex)
        }

        if (intervals.contains(3) || intervals.contains(4)), !intervals.contains(7) {
            intervals.insert(7)
        }

        // Round 1: 仅当 intervals 只有 {0,7}（power chord）时，软补三度。
        // 动机：模型对 major/minor 的三度音级 sigmoid 有时刚好不过 0.5，
        // 导致 intervals 只剩 {0,7} 被错误判成 "5"（如 Em → E5）。
        // 判据：比较 (root+3) 和 (root+4) 的概率：
        //   - 胜者 >= softMin               （不低到完全没响应）
        //   - 胜者 >= softRatio * 败者      （明显偏向一方，避免真 power chord 误补）
        if intervals == Set<Int>([0, 7]) {
            let b3 = chordProbabilities[(rootIndex + 3) % 12]
            let maj3 = chordProbabilities[(rootIndex + 4) % 12]
            let softMin = 0.15
            let softRatio = 2.0
            let winner = max(b3, maj3)
            let loser = min(b3, maj3)
            if winner >= softMin, winner >= softRatio * max(loser, 1e-6) {
                intervals.insert(maj3 >= b3 ? 4 : 3)
            }
        }

        // Round 3: 仅余根音 {0} 时落在退化串 X:(1)；用与 Round1 相同软三度 + 五度补成三和弦，不再输出 (1)。
        if intervals == Set<Int>([0]) {
            let b3 = chordProbabilities[(rootIndex + 3) % 12]
            let maj3 = chordProbabilities[(rootIndex + 4) % 12]
            let softMin = 0.15
            let softRatio = 2.0
            let winner = max(b3, maj3)
            let loser = min(b3, maj3)
            if winner >= softMin, winner >= softRatio * max(loser, 1e-6) {
                if maj3 >= b3 {
                    intervals.insert(4)
                } else {
                    intervals.insert(3)
                }
                intervals.insert(7)
            }
        }

        // Round 3 保底：仍然只有根、无法判断品质时不输出 "X:(1)" / "X:(1)/Y"。
        // 返回 "N"，由 decodeFrames 里的 N 过滤与 removeShortFrames 合并到相邻段，
        // 不虚构大/小三和弦品质，也避免把 power-chord 外的退化字符串泄漏到 UI。
        if intervals == Set<Int>([0]) {
            return "N"
        }

        let rootName = noteNames[rootIndex]
        let suffix = classifyChordSuffix(intervals: intervals)
        let base: String
        if let suffix {
            base = rootName + suffix
        } else {
            let degrees = intervals
                .sorted()
                .map { intervalSymbols[$0] }
                .joined(separator: ",")
            base = "\(rootName):(\(degrees))"
        }

        guard bassIndex != 12, bassIndex != rootIndex else {
            return base
        }
        // Round 2: 大/小三和弦上误加的 slash（低音实为根上纯五度，如 Am/E、Bm/F#、C/G），
        // 与根位标签对齐，不保留 slash。
        if let s = suffix, (s.isEmpty || s == "m") {
            let perfectFifthIndex = (rootIndex + 7) % 12
            if bassIndex == perfectFifthIndex {
                return base
            }
        }
        return "\(base)/\(noteNames[bassIndex])"
    }

    private static func classifyChordSuffix(intervals: Set<Int>) -> String? {
        if matches(intervals, required: [0, 4, 7, 11], optional: [2]) { return intervals.contains(2) ? "maj9" : "maj7" }
        if matches(intervals, required: [0, 4, 7, 10], optional: [2]) { return intervals.contains(2) ? "9" : "7" }
        if matches(intervals, required: [0, 3, 7, 10], optional: [2]) { return intervals.contains(2) ? "m9" : "m7" }
        if matches(intervals, required: [0, 3, 6, 9]) { return "dim7" }
        if matches(intervals, required: [0, 3, 6]) { return "dim" }
        if matches(intervals, required: [0, 4, 8]) { return "aug" }
        if matches(intervals, required: [0, 4, 7, 9]) { return "6" }
        if matches(intervals, required: [0, 3, 7, 9]) { return "m6" }
        if matches(intervals, required: [0, 5, 7], optional: [10]) { return intervals.contains(10) ? "7sus4" : "sus4" }
        if matches(intervals, required: [0, 2, 7], optional: [10]) { return intervals.contains(10) ? "7sus2" : "sus2" }
        if matches(intervals, required: [0, 4, 7, 2]) { return "add9" }
        if matches(intervals, required: [0, 3, 7, 2]) { return "madd9" }
        if matches(intervals, required: [0, 4, 7]) { return "" }
        if matches(intervals, required: [0, 3, 7]) { return "m" }
        if matches(intervals, required: [0, 7]) { return "5" }
        return nil
    }

    private static func matches(_ intervals: Set<Int>, required: Set<Int>, optional: Set<Int> = []) -> Bool {
        guard required.isSubset(of: intervals) else { return false }
        return intervals.subtracting(required).isSubset(of: optional)
    }

    // Round 5 一部分：跨 N 缝同名段桥接。
    // 动机：Round 3 保底把退化帧变 N 被 filter 丢掉后，稳定和弦会被切成
    // "A - 缝 - A" 三段；removeShortFrames 依赖 startMs==endMs 接续，跨不了缝。
    // 仅当相邻两段 chord 完全相同且缝宽 <= maxGapMs 时合并，缝比 maxGapMs
    // 还长就不认，避免跨越真实换和弦 / 长静音。
    private static func bridgeSameNameSegments(
        _ frames: [RawChordFrame],
        maxGapMs: Int
    ) -> [RawChordFrame] {
        guard !frames.isEmpty else { return [] }
        var result: [RawChordFrame] = []
        for frame in frames {
            if let last = result.last,
               last.chord == frame.chord,
               frame.startMs - last.endMs <= maxGapMs {
                result[result.count - 1] = RawChordFrame(
                    startMs: last.startMs,
                    endMs: frame.endMs,
                    chord: last.chord
                )
            } else {
                result.append(frame)
            }
        }
        return result
    }

    // Round 5 另一部分：短段双向吸附。
    // 原实现仅向前吸附，首段若短会被整段丢弃（triad-E / triad-Em 曾被抹空）。
    // 新规则：
    //   - 前无邻居 → 向后吸附（扩展 next.startMs 到短段 startMs，保留 next.chord）
    //   - 后无邻居 → 向前吸附（扩展 prev.endMs，保留 prev.chord）
    //   - 两侧都有 → 优先并入 chord 名相同的一侧；都相同/都不同时并入时长更长的一侧
    //   - 两侧都无 → 丢弃（只可能是孤立超短段的退化输入）
    private static func removeShortFrames(_ frames: [RawChordFrame], minDurationMs: Int) -> [RawChordFrame] {
        guard !frames.isEmpty else { return [] }
        var pending = frames
        var result: [RawChordFrame] = []
        var index = 0
        while index < pending.count {
            let frame = pending[index]
            let duration = frame.endMs - frame.startMs
            if duration >= minDurationMs {
                result.append(frame)
                index += 1
                continue
            }
            let prev = result.last
            let next: RawChordFrame? = (index + 1 < pending.count) ? pending[index + 1] : nil
            if prev == nil, let nxt = next {
                pending[index + 1] = RawChordFrame(
                    startMs: frame.startMs,
                    endMs: nxt.endMs,
                    chord: nxt.chord
                )
            } else if let pv = prev, next == nil {
                result[result.count - 1] = RawChordFrame(
                    startMs: pv.startMs,
                    endMs: frame.endMs,
                    chord: pv.chord
                )
            } else if let pv = prev, let nxt = next {
                let prevSame = pv.chord == frame.chord
                let nextSame = nxt.chord == frame.chord
                let absorbNext: Bool
                if prevSame && !nextSame {
                    absorbNext = false
                } else if !prevSame && nextSame {
                    absorbNext = true
                } else {
                    absorbNext = (nxt.endMs - nxt.startMs) > (pv.endMs - pv.startMs)
                }
                if absorbNext {
                    pending[index + 1] = RawChordFrame(
                        startMs: frame.startMs,
                        endMs: nxt.endMs,
                        chord: nxt.chord
                    )
                } else {
                    result[result.count - 1] = RawChordFrame(
                        startMs: pv.startMs,
                        endMs: frame.endMs,
                        chord: pv.chord
                    )
                }
            }
            index += 1
        }
        return result
    }
}
