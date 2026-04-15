import Foundation

/// 实时音频环形缓冲：按样本累积 PCM，并支持固定窗口读取。
final class LiveChordAudioRingBuffer {
  init(maxSamples: Int) {
    self.maxSamples = maxSamples
  }

  private let maxSamples: Int
  private var samples: [Float] = []

  /// 追加 PCM16 小端数据到缓冲区（归一化到 [-1, 1]）。
  func appendPCM16LE(_ data: Data) {
    guard !data.isEmpty else { return }
    let count = data.count / 2
    samples.reserveCapacity(samples.count + count)
    data.withUnsafeBytes { rawBuf in
      guard let ptr = rawBuf.bindMemory(to: Int16.self).baseAddress else { return }
      for i in 0..<count {
        let s = ptr[i].littleEndian
        samples.append(Float(s) / 32768.0)
      }
    }
    trimIfNeeded()
  }

  /// 最近窗口样本；不足时返回 nil。
  func latestWindow(sampleCount: Int) -> [Float]? {
    guard samples.count >= sampleCount else { return nil }
    return Array(samples[(samples.count - sampleCount)..<samples.count])
  }

  func clear() {
    samples.removeAll(keepingCapacity: true)
  }

  private func trimIfNeeded() {
    guard samples.count > maxSamples else { return }
    samples.removeFirst(samples.count - maxSamples)
  }
}
