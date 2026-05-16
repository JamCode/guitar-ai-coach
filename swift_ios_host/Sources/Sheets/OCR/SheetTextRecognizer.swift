import CoreGraphics
import Foundation
import Vision

protocol SheetTextRecognizing {
    func recognize(
        image: CGImage,
        region: SheetOCRRect?,
        configuration: SheetTextRecognitionConfiguration
    ) async throws -> [SheetOCRTextObservation]
}

struct SheetTextRecognitionConfiguration: Equatable {
    var recognitionLanguages: [String]
    var customWords: [String]
    var minimumTextHeight: Float
    var recognitionLevel: VNRequestTextRecognitionLevel
    var usesLanguageCorrection: Bool
    var source: SheetOCRObservationSource

    static let fullPage = SheetTextRecognitionConfiguration(
        recognitionLanguages: ["zh-Hans", "en-US"],
        customWords: SheetChordLexicon.commonChordWords,
        minimumTextHeight: 0.006,
        recognitionLevel: .accurate,
        usesLanguageCorrection: true,
        source: .fullPage
    )

    static let chordZone = SheetTextRecognitionConfiguration(
        recognitionLanguages: ["en-US"],
        customWords: SheetChordLexicon.commonChordWords,
        minimumTextHeight: 0.004,
        recognitionLevel: .accurate,
        usesLanguageCorrection: false,
        source: .chordZone
    )

    static let chordLabelZone = SheetTextRecognitionConfiguration(
        recognitionLanguages: ["en-US"],
        customWords: SheetChordLexicon.commonChordWords,
        minimumTextHeight: 0.003,
        recognitionLevel: .accurate,
        usesLanguageCorrection: false,
        source: .chordLabelZone
    )

    static let jianpuZone = SheetTextRecognitionConfiguration(
        recognitionLanguages: ["en-US"],
        customWords: [],
        minimumTextHeight: 0.004,
        recognitionLevel: .accurate,
        usesLanguageCorrection: false,
        source: .jianpuZone
    )

    static let lyricZone = SheetTextRecognitionConfiguration(
        recognitionLanguages: ["zh-Hans", "en-US"],
        customWords: [],
        minimumTextHeight: 0.006,
        recognitionLevel: .accurate,
        usesLanguageCorrection: true,
        source: .lyricZone
    )
}

struct VisionSheetTextRecognizer: SheetTextRecognizing {
    func recognize(
        image: CGImage,
        region: SheetOCRRect? = nil,
        configuration: SheetTextRecognitionConfiguration = .fullPage
    ) async throws -> [SheetOCRTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { observation -> SheetOCRTextObservation? in
                        let candidates = observation.topCandidates(3)
                        guard let first = candidates.first else { return nil }
                        let text = first.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return nil }
                        let mappedCandidates = candidates.map {
                            SheetOCRTextCandidate(text: $0.string, confidence: $0.confidence)
                        }
                        return SheetOCRTextObservation(
                            text: text,
                            confidence: first.confidence,
                            rect: SheetOCRRect.topLeftNormalized(fromVisionNormalized: observation.boundingBox),
                            candidates: mappedCandidates,
                            source: configuration.source
                        )
                    }
                    .sortedForReading()
                continuation.resume(returning: observations)
            }
            request.recognitionLevel = configuration.recognitionLevel
            request.usesLanguageCorrection = configuration.usesLanguageCorrection
            request.recognitionLanguages = configuration.recognitionLanguages
            request.customWords = configuration.customWords
            request.minimumTextHeight = configuration.minimumTextHeight
            if let region {
                request.regionOfInterest = region.visionNormalizedRect
            }
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum SheetChordLexicon {
    static let roots = ["C", "C#", "Db", "D", "D#", "Eb", "E", "F", "F#", "Gb", "G", "G#", "Ab", "A", "A#", "Bb", "B"]
    static let suffixes = ["", "m", "7", "m7", "maj7", "M7", "sus2", "sus4", "add9", "dim", "aug", "6", "9", "11", "13"]

    static let commonChordWords: [String] = {
        var out: [String] = []
        for root in roots {
            for suffix in suffixes {
                out.append(root + suffix)
            }
        }
        for root in roots {
            for bass in roots {
                if root != bass {
                    out.append("\(root)/\(bass)")
                }
            }
        }
        return out
    }()
}

extension SheetOCRRect {
    static func topLeftNormalized(fromVisionNormalized rect: CGRect) -> SheetOCRRect {
        SheetOCRRect(
            x: rect.origin.x,
            y: 1 - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    var visionNormalizedRect: CGRect {
        CGRect(x: x, y: 1 - y - height, width: width, height: height)
    }
}

extension Array where Element == SheetOCRTextObservation {
    func sortedForReading() -> [SheetOCRTextObservation] {
        sorted {
            if abs($0.rect.midY - $1.rect.midY) > 0.012 {
                return $0.rect.midY < $1.rect.midY
            }
            return $0.rect.midX < $1.rect.midX
        }
    }
}
