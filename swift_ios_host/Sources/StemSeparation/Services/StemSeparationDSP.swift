import Foundation

enum StemSeparationDSP {
    static func makeSegmentRanges(
        sampleCount: Int,
        sampleRate: Double,
        chunkDurationSec: Double,
        overlapRatio: Double
    ) throws -> [StemSegmentRange] {
        guard sampleCount > 0 else { return [] }
        guard sampleRate > 0, chunkDurationSec > 0, overlapRatio >= 0, overlapRatio < 1 else {
            throw StemSeparationError.invalidConfiguration
        }

        let chunkSamples = max(1, Int((sampleRate * chunkDurationSec).rounded()))
        let hopSamples = max(1, Int((Double(chunkSamples) * (1 - overlapRatio)).rounded()))
        var ranges: [StemSegmentRange] = []
        var start = 0
        var index = 0
        while start < sampleCount {
            let end = min(sampleCount, start + chunkSamples)
            ranges.append(StemSegmentRange(index: index, startSample: start, endSample: end))
            if end >= sampleCount { break }
            start += hopSamples
            index += 1
        }
        return ranges
    }

    static func stitch(
        segments: [(range: StemSegmentRange, stems: [StemKind: [Float]])],
        outputSampleCount: Int,
        expectedStems: [StemKind]
    ) throws -> [StemKind: [Float]] {
        guard outputSampleCount > 0 else { throw StemSeparationError.emptyInput }
        var accumulators = Dictionary(
            uniqueKeysWithValues: expectedStems.map { ($0, [Float](repeating: 0, count: outputSampleCount)) }
        )
        var weights = Dictionary(
            uniqueKeysWithValues: expectedStems.map { ($0, [Float](repeating: 0, count: outputSampleCount)) }
        )

        for (segmentIndex, item) in segments.enumerated() {
            let previous = segmentIndex > 0 ? segments[segmentIndex - 1].range : nil
            let next = segmentIndex + 1 < segments.count ? segments[segmentIndex + 1].range : nil
            let leftOverlap = previous.map { max(0, $0.endSample - item.range.startSample) } ?? 0
            let rightOverlap = next.map { max(0, item.range.endSample - $0.startSample) } ?? 0
            let segmentLength = item.range.endSample - item.range.startSample

            for stem in expectedStems {
                guard let values = item.stems[stem] else {
                    throw StemSeparationError.missingStem(stem)
                }
                var acc = accumulators[stem] ?? []
                var weightArray = weights[stem] ?? []
                let limit = min(segmentLength, values.count)
                for localIndex in 0..<limit {
                    let globalIndex = item.range.startSample + localIndex
                    guard globalIndex >= 0, globalIndex < outputSampleCount else { continue }
                    let w = crossfadeWeight(
                        localIndex: localIndex,
                        segmentLength: segmentLength,
                        leftOverlap: leftOverlap,
                        rightOverlap: rightOverlap
                    )
                    acc[globalIndex] += values[localIndex] * w
                    weightArray[globalIndex] += w
                }
                accumulators[stem] = acc
                weights[stem] = weightArray
            }
        }

        var result: [StemKind: [Float]] = [:]
        for stem in expectedStems {
            var values = accumulators[stem] ?? []
            let weightArray = weights[stem] ?? []
            for i in values.indices {
                if i < weightArray.count, weightArray[i] > 0 {
                    values[i] /= weightArray[i]
                }
            }
            result[stem] = values
        }
        return result
    }

    static func linearResample(samples: [Float], sourceSampleRate: Double, targetSampleRate: Double) -> [Float] {
        guard sourceSampleRate > 0, targetSampleRate > 0, !samples.isEmpty else { return samples }
        if abs(sourceSampleRate - targetSampleRate) < 1 { return samples }
        let ratio = targetSampleRate / sourceSampleRate
        let outCount = max(1, Int((Double(samples.count) * ratio).rounded(.down)))
        let last = samples.count - 1
        var output = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let sourcePosition = Double(i) / ratio
            let base = min(Int(sourcePosition), last)
            let frac = Float(sourcePosition - Double(base))
            if base >= last {
                output[i] = samples[last]
            } else {
                output[i] = samples[base] * (1 - frac) + samples[base + 1] * frac
            }
        }
        return output
    }

    private static func crossfadeWeight(
        localIndex: Int,
        segmentLength: Int,
        leftOverlap: Int,
        rightOverlap: Int
    ) -> Float {
        var weight: Float = 1
        if leftOverlap > 0, localIndex < leftOverlap {
            weight = min(weight, Float(localIndex + 1) / Float(leftOverlap + 1))
        }
        if rightOverlap > 0, localIndex >= max(0, segmentLength - rightOverlap) {
            let positionInFade = localIndex - max(0, segmentLength - rightOverlap)
            weight = min(weight, 1 - Float(positionInFade + 1) / Float(rightOverlap + 1))
        }
        return max(0.0001, weight)
    }
}
