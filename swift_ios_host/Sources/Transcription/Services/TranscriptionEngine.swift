import Foundation

struct RawChordFrame: Equatable {
    let startMs: Int
    let endMs: Int
    let chord: String
}

protocol ChordRecognizer {
    func recognize(samples: [Float], sampleRate: Double) async throws -> (frames: [RawChordFrame], originalKey: String)
}

struct TranscriptionResultPayload: Equatable {
    let fileName: String
    let durationMs: Int
    let originalKey: String
    let segments: [TranscriptionSegment]
    let waveform: [Double]
}

enum TranscriptionEngine {
    static func mergeSegments(_ raw: [RawChordFrame]) -> [TranscriptionSegment] {
        guard var current = raw.first else {
            return []
        }

        var merged: [TranscriptionSegment] = []
        for frame in raw.dropFirst() {
            if frame.chord == current.chord, frame.startMs == current.endMs {
                current = RawChordFrame(startMs: current.startMs, endMs: frame.endMs, chord: current.chord)
            } else {
                merged.append(
                    TranscriptionSegment(startMs: current.startMs, endMs: current.endMs, chord: current.chord)
                )
                current = frame
            }
        }

        merged.append(TranscriptionSegment(startMs: current.startMs, endMs: current.endMs, chord: current.chord))
        return merged
    }
}

struct TranscriptionOrchestrator {
    let recognizer: ChordRecognizer

    func recognize(
        fileName: String,
        durationMs: Int,
        samples: [Float],
        sampleRate: Double
    ) async throws -> TranscriptionResultPayload {
        let raw = try await recognizer.recognize(samples: samples, sampleRate: sampleRate)
        return TranscriptionResultPayload(
            fileName: fileName,
            durationMs: durationMs,
            originalKey: raw.originalKey,
            segments: TranscriptionEngine.mergeSegments(raw.frames),
            waveform: TranscriptionWaveformService.buildSummary(samples: samples, binCount: 180)
        )
    }
}
