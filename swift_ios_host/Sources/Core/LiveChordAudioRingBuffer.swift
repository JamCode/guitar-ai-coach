import Foundation

public final class LiveChordAudioRingBuffer {
    private let maxSamples: Int
    private var samples: [Float] = []

    public init(maxSamples: Int) {
        self.maxSamples = maxSamples
    }

    public func appendFloatSamples(_ chunk: [Float]) {
        guard !chunk.isEmpty else { return }
        samples.append(contentsOf: chunk)
        trimIfNeeded()
    }

    public func latestWindow(sampleCount: Int) -> [Float]? {
        guard samples.count >= sampleCount else { return nil }
        return Array(samples[(samples.count - sampleCount)..<samples.count])
    }

    public func clear() {
        samples.removeAll(keepingCapacity: true)
    }

    private func trimIfNeeded() {
        guard samples.count > maxSamples else { return }
        samples.removeFirst(samples.count - maxSamples)
    }
}

