import Foundation

protocol StemAudioFileWriting {
    func write(
        stems: [StemKind: [Float]],
        sampleRate: Double,
        outputDirectory: URL,
        baseName: String
    ) throws -> [StemKind: URL]
}

struct WAVStemAudioFileWriter: StemAudioFileWriting {
    func write(
        stems: [StemKind: [Float]],
        sampleRate: Double,
        outputDirectory: URL,
        baseName: String
    ) throws -> [StemKind: URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var urls: [StemKind: URL] = [:]
        for (stem, samples) in stems {
            let url = outputDirectory.appendingPathComponent("\(baseName)-\(stem.rawValue).wav")
            do {
                try TranscriptionMediaDecoder.writeWAV(samples: samples, sampleRate: sampleRate, to: url)
            } catch {
                throw StemSeparationError.outputWriteFailed
            }
            urls[stem] = url
        }
        return urls
    }
}
