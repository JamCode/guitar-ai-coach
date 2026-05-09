import Foundation

protocol StemSeparationModelRunning {
    var stems: [StemKind] { get }

    func separate(
        samples: [Float],
        sampleRate: Double
    ) async throws -> [StemKind: [Float]]
}

struct StemSeparationEngine {
    private let configuration: StemSeparationConfiguration
    private let modelRunner: StemSeparationModelRunning
    private let writer: StemAudioFileWriting

    init(
        configuration: StemSeparationConfiguration = .twoStemDefault,
        modelRunner: StemSeparationModelRunning,
        writer: StemAudioFileWriting = WAVStemAudioFileWriter()
    ) {
        self.configuration = configuration
        self.modelRunner = modelRunner
        self.writer = writer
    }

    func separate(
        media: DecodedTranscriptionMedia,
        outputDirectory: URL,
        progress: ((StemSeparationProgress) -> Void)? = nil
    ) async throws -> StemSeparationResult {
        guard !media.pcmSamples.isEmpty else { throw StemSeparationError.emptyInput }
        let samples = StemSeparationDSP.linearResample(
            samples: media.pcmSamples,
            sourceSampleRate: media.sampleRate,
            targetSampleRate: configuration.targetSampleRate
        )
        let ranges = try StemSeparationDSP.makeSegmentRanges(
            sampleCount: samples.count,
            sampleRate: configuration.targetSampleRate,
            chunkDurationSec: configuration.chunkDurationSec,
            overlapRatio: configuration.overlapRatio
        )
        guard !ranges.isEmpty else { throw StemSeparationError.emptyInput }

        progress?(
            StemSeparationProgress(stage: .preparing, completedSegments: 0, totalSegments: ranges.count)
        )

        var separatedSegments: [(range: StemSegmentRange, stems: [StemKind: [Float]])] = []
        separatedSegments.reserveCapacity(ranges.count)
        for range in ranges {
            let chunk = Array(samples[range.startSample..<range.endSample])
            let stems = try await modelRunner.separate(
                samples: chunk,
                sampleRate: configuration.targetSampleRate
            )
            separatedSegments.append((range: range, stems: stems))
            progress?(
                StemSeparationProgress(
                    stage: .separating,
                    completedSegments: range.index + 1,
                    totalSegments: ranges.count
                )
            )
        }

        let stitched = try StemSeparationDSP.stitch(
            segments: separatedSegments,
            outputSampleCount: samples.count,
            expectedStems: configuration.stems
        )
        progress?(
            StemSeparationProgress(stage: .writing, completedSegments: ranges.count, totalSegments: ranges.count)
        )

        let id = UUID().uuidString
        let urls = try writer.write(
            stems: stitched,
            sampleRate: configuration.targetSampleRate,
            outputDirectory: outputDirectory.appendingPathComponent(id, isDirectory: true),
            baseName: sanitizedBaseName(media.fileName)
        )
        progress?(
            StemSeparationProgress(stage: .completed, completedSegments: ranges.count, totalSegments: ranges.count)
        )

        return StemSeparationResult(
            id: id,
            fileName: media.fileName,
            customName: media.fileName,
            durationMs: media.durationMs,
            sampleRate: configuration.targetSampleRate,
            createdAtMs: Int(Date().timeIntervalSince1970 * 1000),
            stems: Dictionary(uniqueKeysWithValues: urls.map { ($0.key, $0.value.path) })
        )
    }

    private func sanitizedBaseName(_ fileName: String) -> String {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(stem.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return cleaned.isEmpty ? "stem" : cleaned
    }
}
