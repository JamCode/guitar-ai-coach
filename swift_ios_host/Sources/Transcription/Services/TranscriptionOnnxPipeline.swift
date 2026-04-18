import Accelerate
import Foundation

enum TranscriptionCQTFeatureExtractorError: LocalizedError {
    case fftUnavailable

    var errorDescription: String? {
        switch self {
        case .fftUnavailable:
            return "当前设备无法初始化音频频谱分析器"
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
    private let binSamplePoints: [FrequencySamplePoint]

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
        self.binSamplePoints = Self.makeBinSamplePoints(
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

            for (binIndex, point) in binSamplePoints.enumerated() {
                let lower = sqrt(max(0, magnitudes[point.lowerIndex]))
                let upper = sqrt(max(0, magnitudes[point.upperIndex]))
                let blended = lower * (1 - point.upperWeight) + upper * point.upperWeight
                values[binIndex * frameCount + frameIndex] = log1p(blended)
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
        let peak = samples.reduce(Float.zero) { max($0, abs($1)) }
        guard peak > 0 else { return samples }
        return samples.map { $0 / peak }
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

    private static func makeBinSamplePoints(
        sampleRate: Double,
        fftSize: Int,
        binsPerOctave: Int,
        numOctaves: Int
    ) -> [FrequencySamplePoint] {
        let nyquistIndex = fftSize / 2 - 1
        let resolution = sampleRate / Double(fftSize)
        let startFrequency = 32.70319566257483 // C1
        return (0..<(binsPerOctave * numOctaves)).map { bin in
            let frequency = startFrequency * pow(2.0, Double(bin) / Double(binsPerOctave))
            let exactIndex = max(1.0, min(Double(nyquistIndex), frequency / resolution))
            let lowerIndex = Int(exactIndex.rounded(.down))
            let upperIndex = min(nyquistIndex, lowerIndex + 1)
            return FrequencySamplePoint(
                lowerIndex: lowerIndex,
                upperIndex: upperIndex,
                upperWeight: Float(exactIndex - Double(lowerIndex))
            )
        }
    }
}

private struct FrequencySamplePoint {
    let lowerIndex: Int
    let upperIndex: Int
    let upperWeight: Float
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
            merged.filter { $0.chord != "N" },
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

    private static func removeShortFrames(_ frames: [RawChordFrame], minDurationMs: Int) -> [RawChordFrame] {
        guard !frames.isEmpty else { return [] }
        var filtered: [RawChordFrame] = []

        for frame in frames {
            let duration = frame.endMs - frame.startMs
            if duration < minDurationMs {
                if let last = filtered.last {
                    filtered[filtered.count - 1] = RawChordFrame(
                        startMs: last.startMs,
                        endMs: frame.endMs,
                        chord: last.chord
                    )
                }
            } else {
                filtered.append(frame)
            }
        }

        return filtered
    }
}
