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

    // MARK: - Round 1: soft-thirds for {0,7} power-chord fallback

    /// 工具：构造一帧 chord_probabilities，按 root-relative interval -> prob 设置。
    private func chordProbs(rootIndex: Int, _ rel: [Int: Double]) -> [Double] {
        var probs = [Double](repeating: 0, count: 12)
        for (r, p) in rel {
            probs[(rootIndex + r) % 12] = p
        }
        return probs
    }

    func testLabelDecoder_softCompletesMinorThirdWhenOnlyRootAndFifth() {
        // Em: E(=0) 与 B(=7) 过 0.5，三度 G(rel=3) 只到 0.2，G#(rel=4) ~ 0.0
        // 旧行为：intervals={0,7} -> "E5"
        // 新行为：b3=0.20 vs maj3=0.02，winner>=0.15 且 winner/loser>2 -> 补 3 -> "Em"
        let rootE = 4 // E
        let probs = chordProbs(rootIndex: rootE, [0: 0.8, 7: 0.6, 3: 0.20, 4: 0.02])
        let label = OnnxChordLabelDecoder.decodeLabel(
            rootIndex: rootE, bassIndex: rootE,
            chordProbabilities: probs, threshold: 0.5
        )
        XCTAssertEqual(label, "Em")
    }

    func testLabelDecoder_softCompletesMajorThirdWhenOnlyRootAndFifth() {
        // E major 的镜像：maj3=G#(rel=4) 弱信号，b3=G(rel=3) 基本为 0
        let rootE = 4
        let probs = chordProbs(rootIndex: rootE, [0: 0.8, 7: 0.6, 4: 0.24, 3: 0.002])
        let label = OnnxChordLabelDecoder.decodeLabel(
            rootIndex: rootE, bassIndex: rootE,
            chordProbabilities: probs, threshold: 0.5
        )
        XCTAssertEqual(label, "E")
    }

    func testLabelDecoder_keepsPowerChordWhenBothThirdsWeak() {
        // 真正的 power chord：两个三度概率都极低 -> 保留 "5"
        let rootA = 9
        let probs = chordProbs(rootIndex: rootA, [0: 0.8, 7: 0.7, 3: 0.05, 4: 0.06])
        let label = OnnxChordLabelDecoder.decodeLabel(
            rootIndex: rootA, bassIndex: rootA,
            chordProbabilities: probs, threshold: 0.5
        )
        XCTAssertEqual(label, "A5")
    }

    func testLabelDecoder_keepsPowerChordWhenThirdsAreAmbiguous() {
        // 两个三度概率接近但都没过 0.5，比例不够（winner/loser < 2）-> 保留 "5"
        let rootA = 9
        let probs = chordProbs(rootIndex: rootA, [0: 0.8, 7: 0.7, 3: 0.28, 4: 0.20])
        let label = OnnxChordLabelDecoder.decodeLabel(
            rootIndex: rootA, bassIndex: rootA,
            chordProbabilities: probs, threshold: 0.5
        )
        XCTAssertEqual(label, "A5")
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

    // MARK: - CQT peak / bin helpers (triangular filterbank tests)

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
