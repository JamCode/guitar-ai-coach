import Accelerate
import Foundation

struct StemSeparationSpectrogramProcessor {
    private let fftSize = 4096
    private let hopSize = 1024
    private let modelFrameCount = 512
    private let modelFrequencyBins = 1024
    private let fullFrequencyBins = 2049
    private let outputScale: Float = 2.0 / 3.0
    private let window: [Float]
    private let fftSetup: FFTSetup

    init?() {
        guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Double(fftSize))), FFTRadix(kFFTRadix2)) else {
            return nil
        }
        self.fftSetup = fftSetup
        self.window = vDSP.window(
            ofType: Float.self,
            usingSequence: .hanningDenormalized,
            count: fftSize,
            isHalfWindow: false
        )
    }

    func makeModelInputs(samples: [Float]) -> SpectrogramInput {
        let padded = samples + [Float](repeating: 0, count: fftSize)
        let channels = [padded, padded]
        var channelSTFT: [[ComplexSpectrumFrame]] = []
        channelSTFT.reserveCapacity(2)
        for channel in channels {
            channelSTFT.append(stft(channel))
        }

        let originalFrameCount = channelSTFT.first?.count ?? 0
        let splitCount = max(1, Int(ceil(Double(originalFrameCount) / Double(modelFrameCount))))
        let paddedFrameCount = splitCount * modelFrameCount
        for channelIndex in channelSTFT.indices {
            if channelSTFT[channelIndex].count < paddedFrameCount {
                channelSTFT[channelIndex].append(
                    contentsOf: Array(
                        repeating: ComplexSpectrumFrame.zero(binCount: fullFrequencyBins),
                        count: paddedFrameCount - channelSTFT[channelIndex].count
                    )
                )
            }
        }

        return SpectrogramInput(
            stft: channelSTFT,
            originalFrameCount: originalFrameCount,
            splitCount: splitCount,
            originalSampleCount: samples.count
        )
    }

    func makeMagnitudeInput(_ input: SpectrogramInput, splitIndex: Int) -> [Float] {
        var output = [Float](repeating: 0, count: 2 * modelFrameCount * modelFrequencyBins)
        let frameOffset = splitIndex * modelFrameCount
        for channel in 0..<2 {
            for frame in 0..<modelFrameCount {
                let spectrum = input.stft[channel][frameOffset + frame]
                for bin in 0..<modelFrequencyBins {
                    let re = spectrum.real[bin]
                    let im = spectrum.imag[bin]
                    output[((channel * modelFrameCount + frame) * modelFrequencyBins) + bin] = sqrt(re * re + im * im)
                }
            }
        }
        return output
    }

    func synthesize(input: SpectrogramInput, masksByStem: [StemKind: [[Float]]]) throws -> [StemKind: [Float]] {
        var result: [StemKind: [Float]] = [:]
        for (stem, splitMasks) in masksByStem {
            guard splitMasks.count == input.splitCount else {
                throw StemSeparationError.modelOutputInvalid
            }
            var channelOutputs: [[Float]] = []
            channelOutputs.reserveCapacity(2)
            for channel in 0..<2 {
                var maskedFrames: [ComplexSpectrumFrame] = []
                maskedFrames.reserveCapacity(input.originalFrameCount)
                for frameIndex in 0..<input.originalFrameCount {
                    let splitIndex = frameIndex / modelFrameCount
                    let localFrame = frameIndex % modelFrameCount
                    let mask = splitMasks[splitIndex]
                    var frame = input.stft[channel][frameIndex]
                    for bin in 0..<modelFrequencyBins {
                        let maskIndex = (((channel * modelFrameCount) + localFrame) * modelFrequencyBins) + bin
                        let value = mask[maskIndex]
                        frame.real[bin] *= value
                        frame.imag[bin] *= value
                    }
                    for bin in modelFrequencyBins..<fullFrequencyBins {
                        frame.real[bin] = 0
                        frame.imag[bin] = 0
                    }
                    maskedFrames.append(frame)
                }
                var wave = istft(maskedFrames, outputCount: input.originalSampleCount + fftSize)
                if wave.count > input.originalSampleCount {
                    wave.removeLast(wave.count - input.originalSampleCount)
                }
                channelOutputs.append(wave.map { $0 * outputScale })
            }

            let count = min(channelOutputs[0].count, channelOutputs[1].count)
            var mono = [Float](repeating: 0, count: count)
            for i in 0..<count {
                mono[i] = (channelOutputs[0][i] + channelOutputs[1][i]) * 0.5
            }
            result[stem] = mono
        }
        return result
    }

    func fftRoundTripForTesting(_ samples: [Float]) -> [Float] {
        let frames = stft(samples + [Float](repeating: 0, count: fftSize))
        var output = istft(frames, outputCount: samples.count + fftSize)
        if output.count > samples.count {
            output.removeLast(output.count - samples.count)
        }
        return output
    }

    private func stft(_ samples: [Float]) -> [ComplexSpectrumFrame] {
        guard samples.count >= fftSize else { return [] }
        let frameCount = ((samples.count - fftSize) / hopSize) + 1
        var frames: [ComplexSpectrumFrame] = []
        frames.reserveCapacity(frameCount)
        for frameIndex in 0..<frameCount {
            let start = frameIndex * hopSize
            var frame = Array(samples[start..<(start + fftSize)])
            vDSP.multiply(frame, window, result: &frame)
            frames.append(forwardFFT(frame))
        }
        return frames
    }

    private func istft(_ frames: [ComplexSpectrumFrame], outputCount: Int) -> [Float] {
        guard !frames.isEmpty else { return [] }
        var output = [Float](repeating: 0, count: outputCount)
        var weights = [Float](repeating: 0, count: outputCount)
        for (frameIndex, spectrum) in frames.enumerated() {
            var frame = inverseFFT(spectrum)
            vDSP.multiply(frame, window, result: &frame)
            let start = frameIndex * hopSize
            for i in 0..<fftSize where start + i < outputCount {
                output[start + i] += frame[i]
                weights[start + i] += window[i] * window[i]
            }
        }
        for i in output.indices where weights[i] > 1e-8 {
            output[i] /= weights[i]
        }
        return output
    }

    private func forwardFFT(_ frame: [Float]) -> ComplexSpectrumFrame {
        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var packed = [DSPComplex](repeating: DSPComplex(real: 0, imag: 0), count: fftSize / 2)
        for i in 0..<(fftSize / 2) {
            packed[i] = DSPComplex(real: frame[i * 2], imag: frame[i * 2 + 1])
        }
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                packed.withUnsafeBufferPointer { source in
                    vDSP_ctoz(source.baseAddress!, 2, &split, 1, vDSP_Length(fftSize / 2))
                }
                vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(log2(Double(fftSize))), FFTDirection(FFT_FORWARD))
            }
        }

        var spectrum = ComplexSpectrumFrame.zero(binCount: fullFrequencyBins)
        spectrum.real[0] = real[0]
        spectrum.imag[0] = 0
        spectrum.real[fftSize / 2] = imag[0]
        spectrum.imag[fftSize / 2] = 0
        if fftSize / 2 > 1 {
            for bin in 1..<(fftSize / 2) {
                spectrum.real[bin] = real[bin]
                spectrum.imag[bin] = imag[bin]
            }
        }
        return spectrum
    }

    private func inverseFFT(_ spectrum: ComplexSpectrumFrame) -> [Float] {
        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        real[0] = spectrum.real[0]
        imag[0] = spectrum.real[fftSize / 2]
        if fftSize / 2 > 1 {
            for bin in 1..<(fftSize / 2) {
                real[bin] = spectrum.real[bin]
                imag[bin] = spectrum.imag[bin]
            }
        }

        var packed = [DSPComplex](repeating: DSPComplex(real: 0, imag: 0), count: fftSize / 2)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(log2(Double(fftSize))), FFTDirection(FFT_INVERSE))
                packed.withUnsafeMutableBufferPointer { target in
                    vDSP_ztoc(&split, 1, target.baseAddress!, 2, vDSP_Length(fftSize / 2))
                }
            }
        }

        var output = [Float](repeating: 0, count: fftSize)
        let scale = Float(1.0 / Double(fftSize * 2))
        for i in 0..<(fftSize / 2) {
            output[i * 2] = packed[i].real * scale
            output[i * 2 + 1] = packed[i].imag * scale
        }
        return output
    }
}

struct SpectrogramInput {
    let stft: [[ComplexSpectrumFrame]]
    let originalFrameCount: Int
    let splitCount: Int
    let originalSampleCount: Int
}

struct ComplexSpectrumFrame {
    var real: [Float]
    var imag: [Float]

    static func zero(binCount: Int) -> ComplexSpectrumFrame {
        ComplexSpectrumFrame(
            real: [Float](repeating: 0, count: binCount),
            imag: [Float](repeating: 0, count: binCount)
        )
    }
}
