import Foundation
import Vision
import UIKit

actor SheetOCRService {
    func recognizeSheetSegments(pageURLs: [URL]) async -> [SheetSegment] {
        var candidates: [OcrLineCandidate] = []
        for url in pageURLs {
            guard let image = UIImage(contentsOfFile: url.path),
                  let cgImage = image.cgImage else { continue }
            let lines = await recognizeLines(cgImage: cgImage)
            candidates.append(contentsOf: lines)
        }
        return SheetOcrParser.parseCandidates(candidates)
    }

    private func recognizeLines(cgImage: CGImage) async -> [OcrLineCandidate] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let out: [OcrLineCandidate] = observations.compactMap { obs in
                    guard let text = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                          !text.isEmpty else { return nil }
                    let y = Double(obs.boundingBox.midY)
                    return OcrLineCandidate(text: text, centerY: y)
                }
                continuation.resume(returning: out)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
}
