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
        let separated = try await separateStems(media: media, progress: progress)
        progress?(
            StemSeparationProgress(
                stage: .writing,
                completedSegments: separated.segmentCount,
                totalSegments: separated.segmentCount
            )
        )

        let id = UUID().uuidString
        let urls = try writer.write(
            stems: separated.stems,
            sampleRate: separated.sampleRate,
            outputDirectory: outputDirectory.appendingPathComponent(id, isDirectory: true),
            baseName: sanitizedBaseName(media.fileName)
        )
        progress?(
            StemSeparationProgress(
                stage: .completed,
                completedSegments: separated.segmentCount,
                totalSegments: separated.segmentCount
            )
        )

        // Store paths relative to the stem_separation root directory so they survive app container path changes after restart.
        let rootPath = outputDirectory.path.hasSuffix("/") ? outputDirectory.path : outputDirectory.path + "/"
        let relativeStems = Dictionary(uniqueKeysWithValues: urls.map { (stem, url) in
            let relativePath = url.path.replacingOccurrences(of: rootPath, with: "")
            return (stem, relativePath)
        })
        return StemSeparationResult(
            id: id,
            fileName: media.fileName,
            customName: media.fileName,
            durationMs: media.durationMs,
            sampleRate: separated.sampleRate,
            createdAtMs: Int(Date().timeIntervalSince1970 * 1000),
            stems: relativeStems
        )
    }

    func separateStems(
        media: DecodedTranscriptionMedia,
        progress: ((StemSeparationProgress) -> Void)? = nil
    ) async throws -> StemSeparationOutput {
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
        return StemSeparationOutput(
            stems: stitched,
            sampleRate: configuration.targetSampleRate,
            segmentCount: ranges.count
        )
    }

    private func sanitizedBaseName(_ fileName: String) -> String {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(stem.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return cleaned.isEmpty ? "stem" : cleaned
    }
}

struct StemSeparationOutput: Equatable {
    let stems: [StemKind: [Float]]
    let sampleRate: Double
    let segmentCount: Int
}
