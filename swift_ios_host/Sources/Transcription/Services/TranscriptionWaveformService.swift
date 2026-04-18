import Foundation

enum TranscriptionWaveformService {
    static func buildSummary(samples: [Float], binCount: Int) -> [Double] {
        guard !samples.isEmpty, binCount > 0 else {
            return []
        }

        let stride = max(1, samples.count / binCount)
        var bins: [Double] = []
        bins.reserveCapacity(binCount)

        for index in 0..<binCount {
            let start = index * stride
            let end = min(samples.count, start + stride)
            guard start < end else {
                bins.append(0)
                continue
            }

            let peak = samples[start..<end].reduce(0.0) { partial, sample in
                max(partial, abs(Double(sample)))
            }
            bins.append(peak)
        }
        return bins
    }
}
