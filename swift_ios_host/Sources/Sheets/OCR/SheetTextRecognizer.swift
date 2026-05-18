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

    static let lyricTextZone = SheetTextRecognitionConfiguration(
        recognitionLanguages: ["zh-Hans", "en-US"],
        customWords: [],
        minimumTextHeight: 0.006,
        recognitionLevel: .accurate,
        usesLanguageCorrection: true,
        source: .lyricTextZone
    )
}

struct VisionSheetTextRecognizer: SheetTextRecognizing {
    func recognize(
        image: CGImage,
        region: SheetOCRRect? = nil,
        configuration: SheetTextRecognitionConfiguration = .fullPage
    ) async throws -> [SheetOCRTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let prepared = prepareImage(image, region: region, configuration: configuration)
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
                        let rect = SheetOCRRect.topLeftNormalized(fromVisionNormalized: observation.boundingBox)
                        return SheetOCRTextObservation(
                            text: text,
                            confidence: first.confidence,
                            rect: prepared.region.map { rect.mapped(fromRelativeRectIn: $0) } ?? rect,
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
            do {
                try VNImageRequestHandler(cgImage: prepared.image, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func prepareImage(
        _ image: CGImage,
        region: SheetOCRRect?,
        configuration: SheetTextRecognitionConfiguration
    ) -> (image: CGImage, region: SheetOCRRect?) {
        guard let region else { return (image, nil) }
        let pixelRect = CGRect(
            x: region.x * Double(image.width),
            y: region.y * Double(image.height),
            width: region.width * Double(image.width),
            height: region.height * Double(image.height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard pixelRect.width >= 2, pixelRect.height >= 2, let cropped = image.cropping(to: pixelRect) else {
            return (image, nil)
        }
        let scale: CGFloat = configuration.source == .chordLabelZone ? 3 : 2
        guard let scaled = scaledImage(cropped, scale: scale) else {
            return (cropped, region)
        }
        return (scaled, region)
    }

    private func scaledImage(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
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

    func mapped(fromRelativeRectIn parent: SheetOCRRect) -> SheetOCRRect {
        SheetOCRRect(
            x: parent.x + x * parent.width,
            y: parent.y + y * parent.height,
            width: width * parent.width,
            height: height * parent.height
        )
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
