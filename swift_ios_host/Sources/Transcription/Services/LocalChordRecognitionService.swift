import Accelerate
import CoreML
import Foundation

enum LocalChordRecognitionError: LocalizedError, Equatable {
    case modelNotConfigured
    case modelOutputInvalid
    case noStableChordDetected

    var errorDescription: String? {
        switch self {
        case .modelNotConfigured:
            return "本地和弦识别模型未配置，请检查 App 内置模型"
        case .modelOutputInvalid:
            return "本地和弦识别模型输出异常"
        case .noStableChordDetected:
            return TranscriptionImportError.noStableChordDetected.errorDescription
        }
    }
}

struct LocalChordRecognitionResult: Equatable {
    let durationMs: Int
    let originalKey: String
    let segments: [TranscriptionSegment]
    let displaySegments: [TranscriptionSegment]
    let chordChartSegments: [TranscriptionSegment]
    let timingVariants: TranscriptionTimingVariants
    let timingVariantStats: TranscriptionTimingVariantStats
}

struct LocalChordModelOutput {
    let rootLogits: [Float]
    let bassLogits: [Float]
    let chordLogits: [Float]
    let frameCount: Int
}

protocol ChordRecognitionModelRunning {
    func predict(features: [Float], frameCount: Int) async throws -> LocalChordModelOutput
}

struct CoreMLChordRecognitionRunner: ChordRecognitionModelRunning {
    private let model: MLModel
    private let inputName: String
    private let compiledModelURL: URL?

    init(modelURL: URL? = nil) throws {
        guard let resolvedURL = modelURL ?? Self.defaultModelURL() else {
            throw LocalChordRecognitionError.modelNotConfigured
        }
        let loadURL: URL
        if resolvedURL.pathExtension == "mlpackage" || resolvedURL.pathExtension == "mlmodel" {
            let compiledURL = try MLModel.compileModel(at: resolvedURL)
            compiledModelURL = compiledURL
            loadURL = compiledURL
        } else {
            compiledModelURL = nil
            loadURL = resolvedURL
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try MLModel(contentsOf: loadURL, configuration: configuration)
        guard let firstInputName = model.modelDescription.inputDescriptionsByName.keys.first else {
            throw LocalChordRecognitionError.modelOutputInvalid
        }
        inputName = firstInputName
    }

    func predict(features: [Float], frameCount: Int) async throws -> LocalChordModelOutput {
        let array = try MLMultiArray(
            shape: [1, 1, NSNumber(value: LocalChordFeatureExtractor.nBins), NSNumber(value: LocalChordFeatureExtractor.chunkFrames)],
            dataType: .float32
        )
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: features.count)
        pointer.update(from: features, count: features.count)
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: array)])
        let output = try await Task.detached(priority: .userInitiated) {
            try model.prediction(from: provider)
        }.value
        return try Self.readOutput(output, frameCount: frameCount)
    }

    private static func readOutput(_ provider: MLFeatureProvider, frameCount: Int) throws -> LocalChordModelOutput {
        guard
            let root = provider.featureValue(for: "root_logits")?.multiArrayValue,
            let bass = provider.featureValue(for: "bass_logits")?.multiArrayValue,
            let chord = provider.featureValue(for: "chord_logits")?.multiArrayValue
        else {
            throw LocalChordRecognitionError.modelOutputInvalid
        }
        return LocalChordModelOutput(
            rootLogits: try readFloats(root),
            bassLogits: try readFloats(bass),
            chordLogits: try readFloats(chord),
            frameCount: frameCount
        )
    }

    private static func readFloats(_ array: MLMultiArray) throws -> [Float] {
        var values = [Float](repeating: 0, count: array.count)
        let offsets = logicalOffsets(for: array)
        let storageCount = max(array.count, (offsets.max() ?? 0) + 1)
        switch array.dataType {
        case .float16:
            let pointer = array.dataPointer.bindMemory(to: UInt16.self, capacity: storageCount)
            for i in 0..<array.count {
                values[i] = Float(Float16(bitPattern: pointer[offsets[i]]))
            }
        case .float32:
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: storageCount)
            if offsets.enumerated().allSatisfy({ $0.offset == $0.element }) {
                values.withUnsafeMutableBufferPointer { buffer in
                    buffer.baseAddress?.update(from: pointer, count: array.count)
                }
            } else {
                for i in 0..<array.count {
                    values[i] = pointer[offsets[i]]
                }
            }
        case .double:
            let pointer = array.dataPointer.bindMemory(to: Double.self, capacity: storageCount)
            for i in 0..<array.count {
                values[i] = Float(pointer[offsets[i]])
            }
        default:
            throw LocalChordRecognitionError.modelOutputInvalid
        }
        return values
    }

    private static func logicalOffsets(for array: MLMultiArray) -> [Int] {
        let shape = array.shape.map { max(0, $0.intValue) }
        let strides = array.strides.map { $0.intValue }
        guard !shape.isEmpty, shape.reduce(1, *) == array.count, strides.count == shape.count else {
            return Array(0..<array.count)
        }

        var offsets: [Int] = []
        offsets.reserveCapacity(array.count)
        var indices = [Int](repeating: 0, count: shape.count)
        for _ in 0..<array.count {
            var offset = 0
            for dimension in 0..<shape.count {
                offset += indices[dimension] * strides[dimension]
            }
            offsets.append(offset)

            for dimension in stride(from: shape.count - 1, through: 0, by: -1) {
                indices[dimension] += 1
                if indices[dimension] < shape[dimension] {
                    break
                }
                indices[dimension] = 0
            }
        }
        return offsets
    }

    private static func defaultModelURL() -> URL? {
        if let compiled = Bundle.main.url(forResource: "chordrecognition", withExtension: "mlmodelc") {
            return compiled
        }
        if let package = Bundle.main.url(forResource: "chordrecognition", withExtension: "mlpackage") {
            return package
        }
        return nil
    }
}

struct LocalChordRecognitionService {
    private let runner: ChordRecognitionModelRunning
    private let featureExtractor: LocalChordFeatureExtractor
    private let decoder = LocalChordOutputDecoder()
    private let postprocessor = LocalChordPostprocessor()

    init(
        runner: ChordRecognitionModelRunning,
        featureExtractor: LocalChordFeatureExtractor = LocalChordFeatureExtractor()
    ) {
        self.runner = runner
        self.featureExtractor = featureExtractor
    }

    init(modelURL: URL?) throws {
        runner = try CoreMLChordRecognitionRunner(modelURL: modelURL)
        featureExtractor = LocalChordFeatureExtractor()
    }

    func transcribe(media: DecodedTranscriptionMedia) async throws -> LocalChordRecognitionResult {
        let resampled = TranscriptionMediaDecoder.linearResampleTo22050(
            samples: media.pcmSamples,
            sourceSampleRate: media.sampleRate
        )
        guard !resampled.isEmpty else {
            throw LocalChordRecognitionError.noStableChordDetected
        }

        let durationMs = media.durationMs
        let chunks = featureExtractor.makeChunks(samples: resampled)
        var rawSegments: [TranscriptionSegment] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let output = try await runner.predict(features: chunk.features, frameCount: chunk.validFrameCount)
            let local = decoder.decode(output: output, frameOffsetMs: chunk.startMs)
            rawSegments.append(contentsOf: local)
        }

        let merged = LocalChordPostprocessor.mergeAdjacent(rawSegments)
        let processed = postprocessor.buildResult(rawSegments: merged, durationMs: durationMs)
        guard !processed.displaySegments.isEmpty else {
            throw LocalChordRecognitionError.noStableChordDetected
        }
        return processed
    }
}

struct LocalChordFeatureChunk {
    let startMs: Int
    let validFrameCount: Int
    let features: [Float]
}

final class LocalChordFeatureExtractor {
    static let targetSampleRate = 22_050.0
    static let hopLength = 512
    static let nBins = 144
    static let binsPerOctave = 24
    static let chunkDurationSec = 20.0
    static let chunkSamples = Int(targetSampleRate * chunkDurationSec)
    static let chunkFrames = Int(ceil(Double(chunkSamples) / Double(hopLength)))

    private static let windowSize = 4096
    private static let fMin = 32.70319566257483
    private let window: [Float]
    private let fftSetup: FFTSetup?
    private let fftBinByCQTBin: [Int]

    init() {
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Self.windowSize, isHalfWindow: false)
        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Double(Self.windowSize))), FFTRadix(kFFTRadix2))
        fftBinByCQTBin = (0..<Self.nBins).map { bin in
            let freq = Self.fMin * pow(2.0, Double(bin) / Double(Self.binsPerOctave))
            let fftBin = Int((freq * Double(Self.windowSize) / Self.targetSampleRate).rounded())
            return min(max(1, fftBin), Self.windowSize / 2 - 1)
        }
    }

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func makeChunks(samples: [Float]) -> [LocalChordFeatureChunk] {
        guard !samples.isEmpty else { return [] }
        var chunks: [LocalChordFeatureChunk] = []
        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + Self.chunkSamples)
            let chunk = Array(samples[start..<end])
            let validFrames = max(1, min(Self.chunkFrames, Int(ceil(Double(chunk.count) / Double(Self.hopLength)))))
            chunks.append(
                LocalChordFeatureChunk(
                    startMs: Int((Double(start) / Self.targetSampleRate * 1000.0).rounded()),
                    validFrameCount: validFrames,
                    features: extractFeatures(chunk)
                )
            )
            start += Self.chunkSamples
        }
        return chunks
    }

    func extractFeatures(_ samples: [Float]) -> [Float] {
        if samples.allSatisfy({ abs($0) < 1e-8 }) {
            return [Float](repeating: 0, count: Self.nBins * Self.chunkFrames)
        }
        var padded = samples
        if padded.count < Self.chunkSamples {
            padded.append(contentsOf: repeatElement(0, count: Self.chunkSamples - padded.count))
        } else if padded.count > Self.chunkSamples {
            padded = Array(padded.prefix(Self.chunkSamples))
        }

        guard let fftSetup else {
            return [Float](repeating: 0, count: Self.nBins * Self.chunkFrames)
        }
        var features = [Float](repeating: 0, count: Self.nBins * Self.chunkFrames)
        var frame = [Float](repeating: 0, count: Self.windowSize)
        var real = [Float](repeating: 0, count: Self.windowSize / 2)
        var imag = [Float](repeating: 0, count: Self.windowSize / 2)
        for frameIndex in 0..<Self.chunkFrames {
            let center = frameIndex * Self.hopLength
            let frameStart = center - Self.windowSize / 2
            for i in 0..<Self.windowSize {
                let sampleIndex = frameStart + i
                frame[i] = sampleIndex >= 0 && sampleIndex < padded.count ? padded[sampleIndex] * window[i] : 0
            }
            real.withUnsafeMutableBufferPointer { realBuffer in
                imag.withUnsafeMutableBufferPointer { imagBuffer in
                    guard let realBase = realBuffer.baseAddress, let imagBase = imagBuffer.baseAddress else { return }
                    var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                    frame.withUnsafeBufferPointer { frameBuffer in
                        frameBuffer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.windowSize / 2) { complexPointer in
                            vDSP_ctoz(complexPointer, 2, &split, 1, vDSP_Length(Self.windowSize / 2))
                        }
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(log2(Double(Self.windowSize))), FFTDirection(FFT_FORWARD))
                }
            }
            for bin in 0..<Self.nBins {
                let fftBin = fftBinByCQTBin[bin]
                let magnitude = sqrt(real[fftBin] * real[fftBin] + imag[fftBin] * imag[fftBin]) / Float(Self.windowSize)
                features[bin * Self.chunkFrames + frameIndex] = log1p(magnitude)
            }
        }
        return features
    }
}

struct LocalChordOutputDecoder {
    private let noteNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    private let qualityCandidates: [ChordQualityCandidate] = [
        .init(suffix: "", intervals: [0, 4, 7], penalties: [3], kind: .basic),
        .init(suffix: "m", intervals: [0, 3, 7], penalties: [4], kind: .basic),
        .init(suffix: "7", intervals: [0, 4, 7, 10], penalties: [3, 11], kind: .extended),
        .init(suffix: "m7", intervals: [0, 3, 7, 10], penalties: [4, 11], kind: .extended),
        .init(suffix: "maj7", intervals: [0, 4, 7, 11], penalties: [3, 10], kind: .color),
        .init(suffix: "sus4", intervals: [0, 5, 7], penalties: [3, 4], kind: .color),
        .init(suffix: "sus2", intervals: [0, 2, 7], penalties: [3, 4, 5], kind: .color),
        .init(suffix: "dim", intervals: [0, 3, 6], penalties: [4, 7], kind: .color),
        .init(suffix: "aug", intervals: [0, 4, 8], penalties: [3, 7], kind: .color),
        .init(suffix: "5", intervals: [0, 7], penalties: [3, 4], kind: .basic),
    ]

    func decode(output: LocalChordModelOutput, frameOffsetMs: Int) -> [TranscriptionSegment] {
        let root = reshape(output.rootLogits, classCount: 13)
        let bass = reshape(output.bassLogits, classCount: 13)
        let chroma = reshape(output.chordLogits, classCount: 12)
        let frameCount = min(output.frameCount, root.count, bass.count, chroma.count)
        guard frameCount > 0 else { return [] }

        var labels: [String] = []
        var confidences: [Float] = []
        for i in 0..<frameCount {
            let rootProb = softmax(root[i])
            let bassProb = softmax(bass[i])
            let chromaProb = chroma[i].map(sigmoid)
            let decoded = decodeFrame(rootProb: rootProb, bassProb: bassProb, chromaProb: chromaProb)
            labels.append(decoded.label)
            confidences.append(decoded.confidence)
        }
        let stableLabels = stabilize(labels: labels, confidences: confidences)
        return merge(labels: stableLabels, frameOffsetMs: frameOffsetMs)
    }

    private func decodeFrame(rootProb: [Float], bassProb: [Float], chromaProb: [Float]) -> (label: String, confidence: Float) {
        guard let root = rootProb.indices.max(by: { rootProb[$0] < rootProb[$1] }), root < 12 else {
            return ("N", 0)
        }
        let rootConf = rootProb[root]
        let margin = top1Margin(rootProb)
        if rootConf < 0.33 || margin < 0.025 {
            return ("N", max(0, rootConf))
        }
        let relProb = (0..<12).map { chromaProb[(root + $0) % 12] }
        guard var candidate = selectQualityCandidate(relProb) else {
            return ("N", rootConf)
        }
        var confidence = min(1, max(0, 0.38 * rootConf + 0.22 * min(1, margin / 0.18) + 0.40 * candidate.score))
        let required: Float = candidate.kind == .basic ? 0.50 : 0.64
        if confidence < required || candidate.minMemberProb < 0.42 {
            guard let fallback = fallbackBasicCandidate(relProb) else {
                return ("N", confidence)
            }
            candidate = fallback
            confidence = min(1, max(0, 0.42 * rootConf + 0.18 * min(1, margin / 0.18) + 0.40 * candidate.score))
            if confidence < 0.50 || candidate.minMemberProb < 0.42 {
                return ("N", confidence)
            }
        }

        var label = "\(noteNames[root])\(candidate.suffix)"
        if let bass = bassProb.indices.max(by: { bassProb[$0] < bassProb[$1] }), bass < 12, bass != root {
            let bassRelProb = relProb[(bass - root + 12) % 12]
            if confidence >= 0.70, bassProb[bass] >= 0.40, bassRelProb >= 0.40 {
                label += "/\(noteNames[bass])"
            }
        }
        return (label, confidence)
    }

    private func selectQualityCandidate(_ relProb: [Float]) -> ScoredChordQuality? {
        qualityCandidates
            .map { score(candidate: $0, relProb: relProb) }
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.minMemberProb > rhs.minMemberProb : lhs.score > rhs.score
            }
            .first(where: { $0.score >= 0.44 })
    }

    private func fallbackBasicCandidate(_ relProb: [Float]) -> ScoredChordQuality? {
        qualityCandidates
            .filter { $0.kind == .basic }
            .map { score(candidate: $0, relProb: relProb) }
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.minMemberProb > rhs.minMemberProb : lhs.score > rhs.score
            }
            .first
    }

    private func score(candidate: ChordQualityCandidate, relProb: [Float]) -> ScoredChordQuality {
        let memberProb = candidate.intervals.map { relProb[$0] }
        let memberMean = memberProb.reduce(0, +) / Float(max(1, memberProb.count))
        let memberMin = memberProb.min() ?? 0
        let penaltyMean = candidate.penalties.isEmpty ? 0 : candidate.penalties.map { relProb[$0] }.reduce(0, +) / Float(candidate.penalties.count)
        let outsiderTop = relProb.enumerated()
            .filter { !candidate.intervals.contains($0.offset) }
            .map(\.element)
            .max() ?? 0
        let score = min(1, max(0, 0.62 * memberMean + 0.28 * memberMin - 0.18 * penaltyMean - 0.08 * outsiderTop))
        return ScoredChordQuality(suffix: candidate.suffix, kind: candidate.kind, score: score, minMemberProb: memberMin)
    }

    private func stabilize(labels: [String], confidences: [Float]) -> [String] {
        guard labels.count > 2 else { return labels }
        var out = labels
        for _ in 0..<3 {
            let runs = labelRuns(out)
            var changed = false
            for (idx, run) in runs.enumerated() where run.length <= 4 {
                let currentConf = mean(Array(confidences[run.start..<run.end]))
                guard currentConf <= 0.58 else { continue }
                let prev = idx > 0 ? runs[idx - 1].label : nil
                let next = idx + 1 < runs.count ? runs[idx + 1].label : nil
                let replacement: String?
                if prev == next {
                    replacement = prev
                } else if prev != nil && next == "N" {
                    replacement = prev
                } else if next != nil && prev == "N" {
                    replacement = next
                } else {
                    replacement = nil
                }
                guard let replacement, replacement != run.label else { continue }
                for i in run.start..<run.end { out[i] = replacement }
                changed = true
            }
            if !changed { break }
        }
        return out
    }

    private func merge(labels: [String], frameOffsetMs: Int) -> [TranscriptionSegment] {
        let frameMs = Double(LocalChordFeatureExtractor.hopLength) / LocalChordFeatureExtractor.targetSampleRate * 1000.0
        var segments: [TranscriptionSegment] = []
        for run in labelRuns(labels) where run.label != "N" {
            let start = frameOffsetMs + Int((Double(run.start) * frameMs).rounded())
            let end = frameOffsetMs + Int((Double(run.end) * frameMs).rounded())
            if end > start {
                segments.append(TranscriptionSegment(startMs: start, endMs: end, chord: run.label))
            }
        }
        return segments
    }

    private func reshape(_ values: [Float], classCount: Int) -> [[Float]] {
        guard !values.isEmpty else { return [] }
        let frames = values.count / classCount
        guard frames > 0 else { return [] }
        return (0..<frames).map { frame in
            Array(values[(frame * classCount)..<((frame + 1) * classCount)])
        }
    }

    private func softmax(_ logits: [Float]) -> [Float] {
        guard let maxValue = logits.max() else { return [] }
        let expValues = logits.map { Float(Foundation.exp(Double($0 - maxValue))) }
        let denom = max(expValues.reduce(0, +), 1e-12)
        return expValues.map { $0 / denom }
    }

    private func sigmoid(_ x: Float) -> Float {
        1.0 / (1.0 + Float(Foundation.exp(Double(-x))))
    }

    private func top1Margin(_ values: [Float]) -> Float {
        let sorted = values.sorted(by: >)
        guard sorted.count >= 2 else { return 0 }
        return sorted[0] - sorted[1]
    }

    private func labelRuns(_ labels: [String]) -> [LabelRun] {
        guard !labels.isEmpty else { return [] }
        var runs: [LabelRun] = []
        var start = 0
        var current = labels[0]
        for i in 1..<labels.count {
            if labels[i] != current {
                runs.append(LabelRun(start: start, end: i, label: current))
                start = i
                current = labels[i]
            }
        }
        runs.append(LabelRun(start: start, end: labels.count, label: current))
        return runs
    }

    private func mean(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }
}

struct LocalChordPostprocessor {
    func buildResult(rawSegments: [TranscriptionSegment], durationMs: Int) -> LocalChordRecognitionResult {
        let display = simplifySegments(absorbShortSegments(mergeAdjacent(rawSegments)))
        let noAbsorb = simplifySegments(mergeAdjacent(rawSegments))
        let timing = display
        let timingCompact = compactSegments(display, minDurationMs: 900)
        let playableCompact = compactSegments(timingCompact, minDurationMs: 1_500)
        let key = estimateKey(from: rawSegments)

        let normalBundle = bundle(display)
        let noAbsorbBundle = bundle(noAbsorb)
        let timingBundle = bundle(timing)
        let timingCompactBundle = bundle(timingCompact)
        let playableBundle = bundle(playableCompact)
        let variants = TranscriptionTimingVariants(
            normal: normalBundle,
            noAbsorb: noAbsorbBundle,
            timing: timingBundle,
            timingCompact: timingCompactBundle,
            playableCompact: playableBundle
        )
        let stats = TranscriptionTimingVariantStats(
            normal: TranscriptionTimingVariantStatsRow(displayCount: display.count, simplifiedCount: display.count, chordChartCount: normalBundle.chordChartSegments.count),
            noAbsorb: TranscriptionTimingVariantStatsRow(displayCount: noAbsorb.count, simplifiedCount: noAbsorb.count, chordChartCount: noAbsorbBundle.chordChartSegments.count),
            timing: TranscriptionTimingPriorityStatsRow(displayCount: timing.count, simplifiedCount: timing.count, chordChartCount: timingBundle.chordChartSegments.count, absorbedCount: max(0, noAbsorb.count - display.count), keptShortCount: 0, snappedBoundaryCount: 0),
            timingCompact: TranscriptionTimingCompactStatsRow(displayCount: timingCompact.count, simplifiedCount: timingCompact.count, chordChartCount: timingCompactBundle.chordChartSegments.count, compressedCount: max(0, timing.count - timingCompact.count), preservedTransitionCount: timingCompact.count),
            playableCompact: TranscriptionPlayableCompactStatsRow(displayCount: playableCompact.count, simplifiedCount: playableCompact.count, chordChartCount: playableBundle.chordChartSegments.count, compressedCount: max(0, timingCompact.count - playableCompact.count), simplifiedChordNameCount: countSimplifiedNames(timingCompact, playableCompact), preservedTransitionCount: playableCompact.count, targetDensityAppliedCount: 0)
        )
        return LocalChordRecognitionResult(
            durationMs: durationMs,
            originalKey: key,
            segments: rawSegments,
            displaySegments: display,
            chordChartSegments: normalBundle.chordChartSegments,
            timingVariants: variants,
            timingVariantStats: stats
        )
    }

    static func mergeAdjacent(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        let sorted = segments.sorted { $0.startMs < $1.startMs }
        var out: [TranscriptionSegment] = []
        for seg in sorted where seg.endMs > seg.startMs {
            guard var last = out.last else {
                out.append(seg)
                continue
            }
            if normalize(last.chord) == normalize(seg.chord), seg.startMs <= last.endMs + 80 {
                last = TranscriptionSegment(startMs: last.startMs, endMs: max(last.endMs, seg.endMs), chord: last.chord)
                out[out.count - 1] = last
            } else {
                out.append(seg)
            }
        }
        return out
    }

    private func mergeAdjacent(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        Self.mergeAdjacent(segments)
    }

    private func absorbShortSegments(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        var items = segments
        var idx = 0
        while idx < items.count {
            let dur = items[idx].endMs - items[idx].startMs
            if dur < 500, items.count > 1 {
                if idx > 0, idx + 1 < items.count, normalize(items[idx - 1].chord) == normalize(items[idx + 1].chord) {
                    items[idx - 1] = TranscriptionSegment(startMs: items[idx - 1].startMs, endMs: items[idx + 1].endMs, chord: items[idx - 1].chord)
                    items.remove(at: idx + 1)
                    items.remove(at: idx)
                    idx = max(0, idx - 1)
                    continue
                }
                if idx > 0 {
                    items[idx - 1] = TranscriptionSegment(startMs: items[idx - 1].startMs, endMs: items[idx].endMs, chord: items[idx - 1].chord)
                    items.remove(at: idx)
                    idx = max(0, idx - 1)
                    continue
                }
                if idx + 1 < items.count {
                    items[idx + 1] = TranscriptionSegment(startMs: items[idx].startMs, endMs: items[idx + 1].endMs, chord: items[idx + 1].chord)
                    items.remove(at: idx)
                    continue
                }
            }
            idx += 1
        }
        return mergeAdjacent(items)
    }

    private func compactSegments(_ segments: [TranscriptionSegment], minDurationMs: Int) -> [TranscriptionSegment] {
        var items = segments.map { seg in
            TranscriptionSegment(startMs: seg.startMs, endMs: seg.endMs, chord: playableChordName(seg.chord))
        }
        var idx = 0
        while idx < items.count {
            let dur = items[idx].endMs - items[idx].startMs
            if dur < minDurationMs, items.count > 1 {
                let mergeWithPrevious = idx > 0 && (idx + 1 == items.count || (items[idx - 1].endMs - items[idx - 1].startMs) >= (items[idx + 1].endMs - items[idx + 1].startMs))
                if mergeWithPrevious {
                    items[idx - 1] = TranscriptionSegment(startMs: items[idx - 1].startMs, endMs: items[idx].endMs, chord: items[idx - 1].chord)
                    items.remove(at: idx)
                    idx = max(0, idx - 1)
                    continue
                } else if idx + 1 < items.count {
                    items[idx + 1] = TranscriptionSegment(startMs: items[idx].startMs, endMs: items[idx + 1].endMs, chord: items[idx + 1].chord)
                    items.remove(at: idx)
                    continue
                }
            }
            idx += 1
        }
        return mergeAdjacent(items)
    }

    private func simplifySegments(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        mergeAdjacent(segments.map { TranscriptionSegment(startMs: $0.startMs, endMs: $0.endMs, chord: playableChordName($0.chord, keepSevenths: true)) })
    }

    private func bundle(_ segments: [TranscriptionSegment]) -> TranscriptionTimingVariantBundle {
        let chart = makeChordChartSegments(segments)
        return TranscriptionTimingVariantBundle(
            displaySegments: segments,
            simplifiedDisplaySegments: segments,
            chordChartSegments: chart
        )
    }

    private func makeChordChartSegments(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        compactSegments(segments, minDurationMs: 1_200)
    }

    private func playableChordName(_ chord: String, keepSevenths: Bool = false) -> String {
        let main = chord.split(separator: "/").first.map(String.init) ?? chord
        let parsed = parseRootAndSuffix(main)
        let root = parsed.root
        let suffix = parsed.suffix
        if keepSevenths, ["", "m", "7", "m7", "maj7", "sus2", "sus4", "dim", "aug", "5"].contains(suffix) {
            return main
        }
        if suffix.hasPrefix("m"), !suffix.hasPrefix("maj") { return "\(root)m" }
        if suffix.hasPrefix("sus2") { return "\(root)sus2" }
        if suffix.hasPrefix("sus4") { return "\(root)sus4" }
        if suffix.hasPrefix("dim") { return "\(root)dim" }
        if suffix.hasPrefix("aug") { return "\(root)aug" }
        if suffix == "5" { return "\(root)5" }
        return root.isEmpty ? chord : root
    }

    private func estimateKey(from segments: [TranscriptionSegment]) -> String {
        var durations: [String: Int] = [:]
        for seg in segments {
            let chord = playableChordName(seg.chord)
            let root = parseRootAndSuffix(chord).root
            guard !root.isEmpty else { continue }
            durations[root, default: 0] += max(0, seg.endMs - seg.startMs)
        }
        return durations.max(by: { $0.value < $1.value })?.key ?? "C"
    }

    private func parseRootAndSuffix(_ chord: String) -> (root: String, suffix: String) {
        guard let first = chord.first, first.isLetter else {
            return ("", chord)
        }
        var root = String(first)
        let rest = chord.dropFirst()
        if let accidental = rest.first, accidental == "#" || accidental == "b" {
            root.append(accidental)
        }
        return (root, String(chord.dropFirst(root.count)))
    }

    private func countSimplifiedNames(_ before: [TranscriptionSegment], _ after: [TranscriptionSegment]) -> Int {
        zip(before, after).filter { normalize($0.chord) != normalize($1.chord) }.count
    }

    private static func normalize(_ chord: String) -> String {
        chord.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalize(_ chord: String) -> String {
        Self.normalize(chord)
    }
}

private enum ChordQualityKind {
    case basic
    case extended
    case color
}

private struct ChordQualityCandidate {
    let suffix: String
    let intervals: [Int]
    let penalties: [Int]
    let kind: ChordQualityKind
}

private struct ScoredChordQuality {
    let suffix: String
    let kind: ChordQualityKind
    let score: Float
    let minMemberProb: Float
}

private struct LabelRun {
    let start: Int
    let end: Int
    let label: String

    var length: Int { end - start }
}
