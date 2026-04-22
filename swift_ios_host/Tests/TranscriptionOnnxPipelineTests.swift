import XCTest
@testable import SwiftEarHost

final class TranscriptionOnnxPipelineTests: XCTestCase {
    func testFeatureExtractor_extracts144BinsForTwentySecondChunk() throws {
        let sampleRate = 44_100.0
        let durationSec = 20.0
        let sampleCount = Int(sampleRate * durationSec)
        let samples = (0..<sampleCount).map { index in
            Float(sin(2.0 * Double.pi * 440.0 * Double(index) / sampleRate))
        }

        let tensor = try TranscriptionCQTFeatureExtractor().extractChunk(samples: samples, sampleRate: sampleRate)

        XCTAssertEqual(tensor.shape, [1, 1, 144, 862])
        XCTAssertEqual(tensor.values.count, 144 * 862)
        XCTAssertGreaterThan(tensor.values.max() ?? 0, 0.01)
    }

    func testFeatureExtractor_peakBinMatchesA4() throws {
        // A4 = 440 Hz 理论上对应 bin ≈ 24 * log2(440/32.7) ≈ 90
        let peak = try argmaxBin(forTone: 440.0)
        XCTAssertLessThanOrEqual(abs(peak - 90), 2, "A4 峰值 bin = \(peak)，期望接近 90")
    }

    func testFeatureExtractor_peakBinMatchesC5() throws {
        // C5 = 523.25 Hz → bin = 24 * log2(16) = 96
        let peak = try argmaxBin(forTone: 523.25)
        XCTAssertLessThanOrEqual(abs(peak - 96), 2, "C5 峰值 bin = \(peak)，期望接近 96")
    }

    func testFeatureExtractor_cMajorTriadPeaksCoverCEG() throws {
        // C4=261.63 → bin 72；E4=329.63 → bin 80；G4=392.00 → bin 86
        let binEnergy = try energyPerBin(forTones: [261.63, 329.63, 392.00])
        let top5 = binEnergy.indices.sorted { binEnergy[$0] > binEnergy[$1] }.prefix(5)
        let targets = [72, 80, 86]
        for target in targets {
            let hit = top5.contains { abs($0 - target) <= 2 }
            XCTAssertTrue(hit, "目标 bin \(target) 未出现在 top5=\(Array(top5))")
        }
    }

    // MARK: - helpers

    private func argmaxBin(forTone frequency: Double) throws -> Int {
        let energy = try energyPerBin(forTones: [frequency])
        return energy.indices.max { energy[$0] < energy[$1] } ?? 0
    }

    private func energyPerBin(forTones frequencies: [Double]) throws -> [Float] {
        let sampleRate = 22_050.0
        let durationSec = 2.0
        let sampleCount = Int(sampleRate * durationSec)
        let samples = (0..<sampleCount).map { index -> Float in
            let t = Double(index) / sampleRate
            let summed = frequencies.reduce(0.0) { partial, frequency in
                partial + sin(2.0 * Double.pi * frequency * t)
            }
            return Float(summed / Double(max(1, frequencies.count)))
        }

        let tensor = try TranscriptionCQTFeatureExtractor().extractChunk(
            samples: samples,
            sampleRate: sampleRate
        )

        let binCount = 144
        let frameCount = tensor.values.count / binCount
        var binEnergy = [Float](repeating: 0, count: binCount)
        for bin in 0..<binCount {
            var sum: Float = 0
            for frame in 0..<frameCount {
                sum += tensor.values[bin * frameCount + frame]
            }
            binEnergy[bin] = sum
        }
        return binEnergy
    }

    func testLabelDecoder_mergesCommonChordFrames() {
        let cMajor = [1.0, 0, 0, 0, 1.0, 0, 0, 1.0, 0, 0, 0, 0]
        let gMajor = [0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 1.0]

        let frames = OnnxChordLabelDecoder.decodeFrames(
            rootIndices: [0, 0, 7, 7],
            bassIndices: [0, 0, 7, 7],
            chordProbabilities: [cMajor, cMajor, gMajor, gMajor],
            frameDurationMs: 100,
            threshold: 0.5,
            minDurationMs: 50
        )

        XCTAssertEqual(
            frames,
            [
                RawChordFrame(startMs: 0, endMs: 200, chord: "C"),
                RawChordFrame(startMs: 200, endMs: 400, chord: "G"),
            ]
        )
    }
}
