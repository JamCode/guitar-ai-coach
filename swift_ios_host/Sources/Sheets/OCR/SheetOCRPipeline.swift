import Foundation
import UIKit

struct SheetOCRPipeline {
    var preprocessor: SheetImagePreprocessor
    var recognizer: SheetTextRecognizing
    var detector: SheetStaffSystemDetector
    var parser: SheetOCRParser

    init(
        preprocessor: SheetImagePreprocessor = SheetImagePreprocessor(),
        recognizer: SheetTextRecognizing = VisionSheetTextRecognizer(),
        detector: SheetStaffSystemDetector = SheetStaffSystemDetector(),
        parser: SheetOCRParser = SheetOCRParser()
    ) {
        self.preprocessor = preprocessor
        self.recognizer = recognizer
        self.detector = detector
        self.parser = parser
    }

    func recognize(images: [UIImage]) async throws -> SheetOCRDraft {
        var pages: [SheetOCRPageDraft] = []
        var diagnostics: [String] = []
        var title: SheetOCRToken?
        var key: SheetOCRToken?

        for (pageIndex, image) in images.enumerated() {
            let page = try await recognizePage(image: image, pageIndex: pageIndex)
            pages.append(page)
            diagnostics.append(contentsOf: page.diagnostics.map { "page \(pageIndex + 1): \($0)" })

            let meta = parser.parsePageMeta(page.rawObservations)
            if title == nil { title = meta.title }
            if key == nil { key = meta.key }
        }

        return SheetOCRDraft(
            id: UUID().uuidString,
            title: title,
            originalKey: key,
            pages: pages,
            createdAtMs: Int(Date().timeIntervalSince1970 * 1000),
            diagnostics: diagnostics
        )
    }

    func recognizePage(image: UIImage, pageIndex: Int) async throws -> SheetOCRPageDraft {
        let processed = try preprocessor.preprocess(image)
        var diagnostics: [String] = []
        let fullObservations = try await recognizer.recognize(
            image: processed.image,
            region: nil,
            configuration: .fullPage
        )
        let detected = detector.detectSystems(in: processed.image)
        diagnostics.append("fullObservations=\(fullObservations.count)")
        diagnostics.append("detectedSystems=\(detected.count)")

        let systems: [SheetOCRSystemDraft]
        if detected.isEmpty {
            diagnostics.append("fallback=fullPageYGrouping")
            systems = parser.fallbackSystems(pageIndex: pageIndex, observations: fullObservations)
        } else {
            var parsed: [SheetOCRSystemDraft] = []
            for (systemIndex, system) in detected.enumerated() {
                async let chordObservations = recognizer.recognize(
                    image: processed.image,
                    region: system.chordZone,
                    configuration: .chordZone
                )
                async let jianpuObservations = recognizer.recognize(
                    image: processed.image,
                    region: system.jianpuZone,
                    configuration: .jianpuZone
                )
                async let lyricObservations = recognizer.recognize(
                    image: processed.image,
                    region: system.lyricZone,
                    configuration: .lyricZone
                )
                let chordZoneObservations = try await chordObservations
                let jianpuZoneObservations = try await jianpuObservations
                let lyricZoneObservations = try await lyricObservations
                let observations = chordZoneObservations + jianpuZoneObservations + lyricZoneObservations + fullObservations
                parsed.append(
                    parser.parseSystem(
                        pageIndex: pageIndex,
                        systemIndex: systemIndex,
                        system: system,
                        observations: observations
                    )
                )
            }
            systems = removeAdjacentDuplicateLyrics(parsed)
        }

        return SheetOCRPageDraft(
            pageIndex: pageIndex,
            originalPixelSize: processed.originalPixelSize,
            processedPixelSize: processed.processedPixelSize,
            cropRectInOriginalPixels: processed.cropRectInOriginalPixels,
            systems: systems,
            rawObservations: fullObservations,
            diagnostics: diagnostics
        )
    }

    private func removeAdjacentDuplicateLyrics(_ systems: [SheetOCRSystemDraft]) -> [SheetOCRSystemDraft] {
        var output: [SheetOCRSystemDraft] = []
        for system in systems {
            var current = system
            let currentText = current.lyrics.map(\.text).joined()
            if let previous = output.last {
                let previousText = previous.lyrics.map(\.text).joined()
                if !currentText.isEmpty,
                   current.chords.isEmpty,
                   previousText.count >= currentText.count,
                   previousText.contains(currentText) {
                    current.lyrics = []
                }
            }
            output.append(current)
        }
        return output
    }
}
