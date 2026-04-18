import Foundation
import OnnxRuntimeBindings
import Core

enum OnnxChordRecognizerError: LocalizedError {
    case noStableChordDetected
    case invalidModelIO
    case invalidModelOutput(String)

    var errorDescription: String? {
        switch self {
        case .noStableChordDetected:
            return "这次没能稳定识别出和弦，换一个更清晰的文件再试试"
        case .invalidModelIO:
            return "扒歌模型输入输出信息异常"
        case let .invalidModelOutput(name):
            return "扒歌模型输出异常：\(name)"
        }
    }
}

final class OnnxChordRecognizer: ChordRecognizer {
    private let env: ORTEnv?
    private let session: ORTSession?
    private let modelInputName: String?
    private let modelOutputNames: Set<String>
    private let featureExtractor = TranscriptionCQTFeatureExtractor()
    private let extractor = LiveChordNNLSChromaExtractor()
    private let decoder = LiveChordDecoder()
    private let confidenceThreshold = 0.6
    private let windowSec = 2.0
    private let hopSec = 0.5
    private let onnxThreshold = 0.5
    private let minChordDurationMs = 300

    init(modelURL: URL? = Bundle.main.url(forResource: "consonance_ace", withExtension: "onnx")) {
        if let modelURL {
            let env = try? ORTEnv(loggingLevel: ORTLoggingLevel.warning)
            self.env = env
            let session = env.flatMap { try? ORTSession(env: $0, modelPath: modelURL.path, sessionOptions: nil) }
            self.session = session
            if let session {
                self.modelInputName = try? session.inputNames().first
                let outputs = (try? session.outputNames()) ?? []
                self.modelOutputNames = Set(outputs)
            } else {
                self.modelInputName = nil
                self.modelOutputNames = []
            }
        } else {
            env = nil
            session = nil
            modelInputName = nil
            modelOutputNames = []
        }
    }

    func recognize(samples: [Float], sampleRate: Double) async throws -> (frames: [RawChordFrame], originalKey: String) {
        let rawFrames: [RawChordFrame]
        if let onnxFrames = try runOnnxModel(samples: samples, sampleRate: sampleRate), !onnxFrames.isEmpty {
            rawFrames = onnxFrames
        } else {
            rawFrames = try runDSPFallback(samples: samples, sampleRate: sampleRate)
        }
        guard !rawFrames.isEmpty else {
            throw OnnxChordRecognizerError.noStableChordDetected
        }
        return (rawFrames, detectOriginalKey(from: rawFrames))
    }

    private func runOnnxModel(samples: [Float], sampleRate: Double) throws -> [RawChordFrame]? {
        guard
            let session,
            let inputName = modelInputName,
            modelOutputNames.contains("root_logits"),
            modelOutputNames.contains("bass_logits"),
            modelOutputNames.contains("chord_logits")
        else {
            return nil
        }

        let chunkSampleCount = featureExtractor.samplesPerChunk
        let normalizedSamples = resampleForChunking(samples: samples, sourceSampleRate: sampleRate)
        guard !normalizedSamples.isEmpty else { return nil }

        let totalDurationMs = Int((Double(normalizedSamples.count) / 22_050.0 * 1000).rounded())
        let chunkCount = max(1, Int(ceil(Double(normalizedSamples.count) / Double(chunkSampleCount))))
        var allFrames: [RawChordFrame] = []

        for chunkIndex in 0..<chunkCount {
            if Task.isCancelled {
                throw CancellationError()
            }

            let startSample = chunkIndex * chunkSampleCount
            let endSample = min(normalizedSamples.count, startSample + chunkSampleCount)
            let chunkSamples = Array(normalizedSamples[startSample..<endSample])
            let actualDurationMs = min(
                Int((Double(chunkSamples.count) / 22_050.0 * 1000).rounded()),
                max(0, totalDurationMs - Int((Double(startSample) / 22_050.0 * 1000).rounded()))
            )
            guard actualDurationMs > 0 else { continue }

            let featureTensor = try featureExtractor.extractChunk(samples: chunkSamples, sampleRate: 22_050)
            let inputValue = try makeInputValue(featureTensor)
            let outputs = try session.run(
                withInputs: [inputName: inputValue],
                outputNames: modelOutputNames,
                runOptions: nil
            )

            let rootLogits = try readOutput(named: "root_logits", from: outputs)
            let bassLogits = try readOutput(named: "bass_logits", from: outputs)
            let chordLogits = try readOutput(named: "chord_logits", from: outputs)

            let frameCount = min(
                rootLogits.count / 13,
                bassLogits.count / 13,
                chordLogits.count / 12,
                max(1, Int(ceil(Double(actualDurationMs) / Double(featureExtractor.frameDurationMs))))
            )
            guard frameCount > 0 else { continue }

            let decodedFrames = OnnxChordLabelDecoder.decodeFrames(
                rootIndices: argmaxIndices(logits: rootLogits, classCount: 13, frameCount: frameCount),
                bassIndices: argmaxIndices(logits: bassLogits, classCount: 13, frameCount: frameCount),
                chordProbabilities: sigmoidFrames(logits: chordLogits, classCount: 12, frameCount: frameCount),
                frameDurationMs: featureExtractor.frameDurationMs,
                threshold: onnxThreshold,
                minDurationMs: minChordDurationMs
            )

            let chunkStartMs = Int((Double(startSample) / 22_050.0 * 1000).rounded())
            let chunkEndMs = chunkStartMs + actualDurationMs
            for frame in decodedFrames {
                guard frame.startMs < actualDurationMs else { continue }
                allFrames.append(
                    RawChordFrame(
                        startMs: chunkStartMs + frame.startMs,
                        endMs: min(chunkEndMs, chunkStartMs + frame.endMs),
                        chord: frame.chord
                    )
                )
            }
        }

        return allFrames.filter { $0.endMs > $0.startMs }
    }

    private func runDSPFallback(samples: [Float], sampleRate: Double) throws -> [RawChordFrame] {
        let normalizedSampleRate = max(8_000, Int(sampleRate.rounded()))
        let windowSamples = max(4_096, Int(Double(normalizedSampleRate) * windowSec))
        let hopSamples = max(1_024, Int(Double(normalizedSampleRate) * hopSec))
        guard samples.count >= windowSamples else {
            return []
        }

        var frames: [RawChordFrame] = []
        var cursor = windowSamples
        var frameIndex = 0
        var stableCandidate = "Unknown"
        var stableHits = 0

        while cursor <= samples.count {
            if Task.isCancelled {
                throw CancellationError()
            }

            let window = Array(samples[(cursor - windowSamples)..<cursor])
            let rms = sqrt(window.reduce(0.0) { partial, sample in
                partial + Double(sample * sample)
            } / Double(window.count))

            var accepted = "Unknown"
            if rms >= 0.006 {
                let chroma = extractor.extractChroma(from: window, sampleRate: normalizedSampleRate)
                let top = decoder.decode(chroma: chroma, topK: 3)
                let confidence = decoder.confidence(from: top)
                if confidence >= confidenceThreshold {
                    accepted = top.first?.label ?? "Unknown"
                }
            }

            if accepted == stableCandidate {
                stableHits += 1
            } else {
                stableCandidate = accepted
                stableHits = 1
            }

            let resolved = stableHits >= 2 ? stableCandidate : "Unknown"
            if resolved != "Unknown" {
                let startMs = Int((Double(frameIndex * hopSamples) / Double(normalizedSampleRate) * 1000).rounded())
                let nextCursor = min(samples.count, cursor + hopSamples)
                let endMs = max(
                    startMs + 1,
                    Int((Double(nextCursor) / Double(normalizedSampleRate) * 1000).rounded())
                )
                frames.append(RawChordFrame(startMs: startMs, endMs: endMs, chord: resolved))
            }

            frameIndex += 1
            cursor += hopSamples
        }

        return frames
    }

    private func detectOriginalKey(from frames: [RawChordFrame]) -> String {
        var durationByRoot: [String: Int] = [:]
        for frame in frames {
            let root = chordRoot(from: frame.chord)
            durationByRoot[root, default: 0] += max(1, frame.endMs - frame.startMs)
        }
        return durationByRoot.max(by: { $0.value < $1.value })?.key ?? "C"
    }

    private func chordRoot(from chord: String) -> String {
        let orderedRoots = ["C#", "D#", "F#", "G#", "A#", "Db", "Eb", "Gb", "Ab", "Bb", "C", "D", "E", "F", "G", "A", "B"]
        for root in orderedRoots where chord.hasPrefix(root) {
            if root.count == 2, root.hasSuffix("b") {
                switch root {
                case "Db": return "C#"
                case "Eb": return "D#"
                case "Gb": return "F#"
                case "Ab": return "G#"
                case "Bb": return "A#"
                default: return root
                }
            }
            return root
        }
        return "C"
    }

    private func makeInputValue(_ featureTensor: TranscriptionFeatureTensor) throws -> ORTValue {
        let data = featureTensor.values.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        let shape = featureTensor.shape.map { NSNumber(value: $0) }
        return try ORTValue(
            tensorData: NSMutableData(data: data),
            elementType: ORTTensorElementDataType.float,
            shape: shape
        )
    }

    private func readOutput(named name: String, from outputs: [String: ORTValue]) throws -> [Float] {
        guard let value = outputs[name] else {
            throw OnnxChordRecognizerError.invalidModelOutput(name)
        }
        let data = try value.tensorData() as Data
        guard data.count.isMultiple(of: MemoryLayout<Float>.stride) else {
            throw OnnxChordRecognizerError.invalidModelOutput(name)
        }
        return data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
    }

    private func argmaxIndices(logits: [Float], classCount: Int, frameCount: Int) -> [Int] {
        guard classCount > 0 else { return [] }
        return (0..<frameCount).map { frameIndex in
            let offset = frameIndex * classCount
            var bestIndex = 0
            var bestValue = logits[offset]
            if classCount > 1 {
                for classIndex in 1..<classCount {
                    let value = logits[offset + classIndex]
                    if value > bestValue {
                        bestValue = value
                        bestIndex = classIndex
                    }
                }
            }
            return bestIndex
        }
    }

    private func sigmoidFrames(logits: [Float], classCount: Int, frameCount: Int) -> [[Double]] {
        guard classCount > 0 else { return [] }
        return (0..<frameCount).map { frameIndex in
            let offset = frameIndex * classCount
            return (0..<classCount).map { classIndex in
                let value = Double(logits[offset + classIndex])
                return 1.0 / (1.0 + exp(-value))
            }
        }
    }

    private func resampleForChunking(samples: [Float], sourceSampleRate: Double) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard abs(sourceSampleRate - 22_050.0) > 1 else { return samples }
        let targetCount = max(1, Int((Double(samples.count) * 22_050.0 / sourceSampleRate).rounded()))
        let maxIndex = samples.count - 1
        return (0..<targetCount).map { targetIndex in
            let position = Double(targetIndex) * sourceSampleRate / 22_050.0
            let lowerIndex = min(maxIndex, Int(position.rounded(.down)))
            let upperIndex = min(maxIndex, lowerIndex + 1)
            let fraction = Float(position - Double(lowerIndex))
            let lower = samples[lowerIndex]
            let upper = samples[upperIndex]
            return lower + (upper - lower) * fraction
        }
    }
}
