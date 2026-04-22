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

    func testFeatureExtractor_spikeDoesNotFlattenOverallEnergy() throws {
        // 合成一段以 0.1 为幅度的谐波吉他音（整段 2 秒，22050Hz），
        // 然后在正中间插入一个 +1.0 的单样本尖峰。
        // 旧 peak 归一化：整段会被除以 ~1.0，有用能量被压到 0.1 以下；
        // 新 p99 归一化：99% 分位 ≈ 0.1，有用能量仍保留在 ~1.0 尺度。
        // 这里不直接访问 private normalize，用 extractChunk 的 feature 最大值
        // 作为"是否被尖峰压扁"的间接信号。
        let sampleRate = 22_050.0
        let durationSec = 2.0
        let sampleCount = Int(sampleRate * durationSec)

        func makeHarmonicTone(withSpike: Bool) -> [Float] {
            var buf = (0..<sampleCount).map { index -> Float in
                let t = Double(index) / sampleRate
                var v = 0.0
                for k in 1...4 {
                    v += (1.0 / Double(k)) * sin(2.0 * Double.pi * 329.63 * Double(k) * t)
                }
                return Float(v * 0.1 / 2.0)
            }
            if withSpike {
                buf[sampleCount / 2] = 1.0
            }
            return buf
        }

        let extractor = TranscriptionCQTFeatureExtractor()
        let cleanTensor = try extractor.extractChunk(samples: makeHarmonicTone(withSpike: false),
                                                    sampleRate: sampleRate)
        let spikeTensor = try extractor.extractChunk(samples: makeHarmonicTone(withSpike: true),
                                                    sampleRate: sampleRate)

        let cleanMax = cleanTensor.values.max() ?? 0
        let spikeMax = spikeTensor.values.max() ?? 0
        XCTAssertGreaterThan(cleanMax, 0.01, "clean feature tensor should have non-trivial energy")
        // 关键断言：加了尖峰后，整段能量不应该被压垮到远小于无尖峰版。
        // 放宽到 0.5x；旧 peak 归一化通常会把比值压到 < 0.2。
        XCTAssertGreaterThan(spikeMax, cleanMax * 0.5,
                             "spike should not flatten the rest of the chunk (old peak norm would)")
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
