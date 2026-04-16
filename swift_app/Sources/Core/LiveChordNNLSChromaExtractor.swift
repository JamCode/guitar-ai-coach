import Foundation
import Accelerate

public final class LiveChordNNLSChromaExtractor {
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let window: [Float]
    private let fft: vDSP.FFT<DSPSplitComplex>?
    private let dictionary: [[Double]]
    private let dictionaryT: [[Double]]

    public init(fftSize: Int = 4096) {
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
        self.fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)
        let d = Self.buildDictionary()
        self.dictionary = d
        self.dictionaryT = Self.transpose(d)
    }

    public func extractChroma(from samples: [Float], sampleRate: Int) -> [Double] {
        guard let fft, samples.count >= fftSize else { return Array(repeating: 0, count: 12) }
        let frame = Array(samples[(samples.count - fftSize)..<samples.count])
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP.multiply(frame, window, result: &windowed)

        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var interleaved = [DSPComplex](repeating: DSPComplex(real: 0, imag: 0), count: fftSize / 2)
        for i in 0..<(fftSize / 2) {
            interleaved[i] = DSPComplex(real: windowed[i * 2], imag: windowed[i * 2 + 1])
        }
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                interleaved.withUnsafeBufferPointer { src in
                    vDSP_ctoz(src.baseAddress!, 2, &split, 1, vDSP_Length(fftSize / 2))
                }
                fft.forward(input: split, output: &split)
            }
        }

        var mags = [Float](repeating: 0, count: fftSize / 2)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(fftSize / 2))
            }
        }

        var chroma = [Double](repeating: 0, count: 12)
        for i in 1..<mags.count {
            let freq = Double(i * sampleRate) / Double(fftSize)
            guard freq >= 55.0, freq <= 1760.0 else { continue }
            let midi = 69.0 + 12.0 * log2(freq / 440.0)
            let rounded = Int(lround(midi))
            let cls = (rounded % 12 + 12) % 12
            chroma[cls] += log1p(Double(mags[i]))
        }

        return normalize(solveNNLS(chroma))
    }

    private func normalize(_ values: [Double]) -> [Double] {
        let sum = values.reduce(0, +)
        guard sum > 1e-9 else { return values }
        return values.map { $0 / sum }
    }

    private func solveNNLS(_ b: [Double]) -> [Double] {
        var x = b.map { max(0, $0) }
        let alpha = 0.12
        for _ in 0..<20 {
            let ax = mul(dictionary, x)
            let diff = zip(ax, b).map { $0 - $1 }
            let grad = mul(dictionaryT, diff).map { 2.0 * $0 }
            for i in 0..<x.count { x[i] = max(0, x[i] - alpha * grad[i]) }
        }
        return x
    }

    private static func buildDictionary() -> [[Double]] {
        var a = Array(repeating: Array(repeating: 0.0, count: 12), count: 12)
        for i in 0..<12 {
            for j in 0..<12 {
                let d = min((i - j + 12) % 12, (j - i + 12) % 12)
                switch d {
                case 0: a[i][j] = 1.0
                case 1: a[i][j] = 0.24
                case 2: a[i][j] = 0.10
                case 5, 7: a[i][j] = 0.18
                default: a[i][j] = 0.03
                }
            }
        }
        return a
    }

    private static func transpose(_ m: [[Double]]) -> [[Double]] {
        var out = Array(repeating: Array(repeating: 0.0, count: m.count), count: m[0].count)
        for i in 0..<m.count {
            for j in 0..<m[0].count {
                out[j][i] = m[i][j]
            }
        }
        return out
    }

    private func mul(_ m: [[Double]], _ v: [Double]) -> [Double] {
        m.map { row in zip(row, v).reduce(0) { $0 + $1.0 * $1.1 } }
    }
}

