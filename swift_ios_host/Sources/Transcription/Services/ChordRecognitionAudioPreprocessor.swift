import Foundation

enum VocalPresenceDecision: Equatable {
    case instrumental(confidence: Double)
    case vocalMixed(confidence: Double)
    case uncertain(confidence: Double)

    var shouldUseSeparatedAccompaniment: Bool {
        if case .vocalMixed = self { return true }
        return false
    }
}

struct ChordRecognitionPreprocessingResult: Equatable {
    let media: DecodedTranscriptionMedia
    let vocalPresence: VocalPresenceDecision
}

struct ChordRecognitionAudioPreprocessor {
    private let configuration: StemSeparationConfiguration
    private let runnerFactory: () throws -> StemSeparationModelRunning

    init(
        configuration: StemSeparationConfiguration = .twoStemDefault,
        runnerFactory: @escaping () throws -> StemSeparationModelRunning = { try CoreMLStemSeparationRunner() }
    ) {
        self.configuration = configuration
        self.runnerFactory = runnerFactory
    }

    func prepare(
        media: DecodedTranscriptionMedia,
        onProgress: @escaping @Sendable (TranscriptionProgressState) async -> Void
    ) async throws -> ChordRecognitionPreprocessingResult {
        let runner = try runnerFactory()
        let detector = VocalPresenceDetector(configuration: configuration, runner: runner)
        let decision = try await detector.detect(media: media)

        guard decision.shouldUseSeparatedAccompaniment else {
            #if DEBUG
            print("[ChordPreprocess] vocalPresence=\(decision) usingOriginalAudio=true")
            #endif
            return ChordRecognitionPreprocessingResult(media: media, vocalPresence: decision)
        }

        #if DEBUG
        print("[ChordPreprocess] vocalPresence=\(decision) extractingAccompaniment=true")
        #endif
        let engine = StemSeparationEngine(configuration: configuration, modelRunner: runner)
        let separated = try await engine.separateStems(media: media) { progress in
            Task {
                switch progress.stage {
                case .preparing:
                    await onProgress(.preparing(0.09))
                case .separating:
                    await onProgress(.extractingAccompanimentForChord(progress.fraction))
                case .writing:
                    await onProgress(.extractingAccompanimentForChord(0.98))
                case .completed:
                    await onProgress(.extractingAccompanimentForChord(1))
                }
            }
        }
        guard let accompaniment = separated.stems[.accompaniment], !accompaniment.isEmpty else {
            throw StemSeparationError.missingStem(.accompaniment)
        }
        return ChordRecognitionPreprocessingResult(
            media: DecodedTranscriptionMedia(
                fileName: media.fileName,
                durationMs: media.durationMs,
                pcmSamples: accompaniment,
                sampleRate: separated.sampleRate
            ),
            vocalPresence: decision
        )
    }
}

struct VocalPresenceDetector {
    private let configuration: StemSeparationConfiguration
    private let runner: StemSeparationModelRunning

    init(configuration: StemSeparationConfiguration = .twoStemDefault, runner: StemSeparationModelRunning) {
        self.configuration = configuration
        self.runner = runner
    }

    func detect(media: DecodedTranscriptionMedia) async throws -> VocalPresenceDecision {
        let analysisMedia = makeAnalysisMedia(from: media)
        let engine = StemSeparationEngine(configuration: configuration, modelRunner: runner)
        let separated = try await engine.separateStems(media: analysisMedia)
        guard
            let vocals = separated.stems[.vocals],
            let accompaniment = separated.stems[.accompaniment],
            !vocals.isEmpty,
            !accompaniment.isEmpty
        else {
            return .uncertain(confidence: 0)
        }
        return Self.classify(vocals: vocals, accompaniment: accompaniment)
    }

    private func makeAnalysisMedia(from media: DecodedTranscriptionMedia) -> DecodedTranscriptionMedia {
        let samples = StemSeparationDSP.linearResample(
            samples: media.pcmSamples,
            sourceSampleRate: media.sampleRate,
            targetSampleRate: configuration.targetSampleRate
        )
        guard !samples.isEmpty else { return media }
        let sampleRate = configuration.targetSampleRate
        let excerptSampleCount = max(1, Int((sampleRate * 12.0).rounded()))
        let maxAnalysisSamples = excerptSampleCount * 3
        let selected: [Float]
        if samples.count <= maxAnalysisSamples {
            selected = samples
        } else {
            let anchors = [0.12, 0.45, 0.75]
            var merged: [Float] = []
            merged.reserveCapacity(maxAnalysisSamples)
            for anchor in anchors {
                let center = Int((Double(samples.count) * anchor).rounded())
                let start = min(max(0, center - excerptSampleCount / 2), max(0, samples.count - excerptSampleCount))
                let end = min(samples.count, start + excerptSampleCount)
                merged.append(contentsOf: samples[start..<end])
            }
            selected = merged
        }
        return DecodedTranscriptionMedia(
            fileName: media.fileName,
            durationMs: Int((Double(selected.count) / sampleRate * 1000.0).rounded()),
            pcmSamples: selected,
            sampleRate: sampleRate
        )
    }

    static func classify(vocals: [Float], accompaniment: [Float]) -> VocalPresenceDecision {
        let vocalRMS = rms(vocals)
        let accompanimentRMS = rms(accompaniment)
        guard accompanimentRMS > 0.0001 || vocalRMS > 0.0001 else {
            return .instrumental(confidence: 0.70)
        }

        let ratio = vocalRMS / max(accompanimentRMS, 0.0001)
        let activeRatio = vocalActiveFrameRatio(vocals: vocals, accompaniment: accompaniment)
        if vocalRMS >= 0.008, ratio >= 0.20, activeRatio >= 0.12 {
            let confidence = min(0.98, max(0.55, Double(ratio * 0.55 + activeRatio * 0.45)))
            return .vocalMixed(confidence: confidence)
        }
        if vocalRMS < 0.006 || ratio < 0.12 || activeRatio < 0.06 {
            let confidence = min(0.98, max(0.60, Double((0.20 - min(ratio, 0.20)) * 2.5 + (0.12 - min(activeRatio, 0.12)) * 2.0)))
            return .instrumental(confidence: confidence)
        }
        return .uncertain(confidence: 0.45)
    }

    private static func rms(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        var sum: Float = 0
        for value in values {
            sum += value * value
        }
        return sqrt(sum / Float(values.count))
    }

    private static func vocalActiveFrameRatio(vocals: [Float], accompaniment: [Float]) -> Float {
        let frameSize = 2_048
        let frameCount = max(1, min(vocals.count, accompaniment.count) / frameSize)
        var active = 0
        for frame in 0..<frameCount {
            let start = frame * frameSize
            let end = min(start + frameSize, vocals.count, accompaniment.count)
            guard end > start else { continue }
            let vocal = rms(Array(vocals[start..<end]))
            let accomp = rms(Array(accompaniment[start..<end]))
            if vocal >= max(0.006, accomp * 0.22) {
                active += 1
            }
        }
        return Float(active) / Float(frameCount)
    }
}
