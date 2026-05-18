import CoreGraphics
import Foundation

struct SheetOCRRect: Equatable, Hashable, Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let unit = SheetOCRRect(x: 0, y: 0, width: 1, height: 1)

    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x.clamped(to: 0...1)
        self.y = y.clamped(to: 0...1)
        self.width = width.clamped(to: 0...1)
        self.height = height.clamped(to: 0...1)
        if self.x + self.width > 1 {
            self.width = max(0, 1 - self.x)
        }
        if self.y + self.height > 1 {
            self.height = max(0, 1 - self.y)
        }
    }

    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    func expanded(dx: Double, dy: Double) -> SheetOCRRect {
        SheetOCRRect(
            x: x - dx,
            y: y - dy,
            width: width + dx * 2,
            height: height + dy * 2
        )
    }

    func contains(midpointOf other: SheetOCRRect) -> Bool {
        other.midX >= minX && other.midX <= maxX && other.midY >= minY && other.midY <= maxY
    }

    func union(_ other: SheetOCRRect) -> SheetOCRRect {
        let left = min(minX, other.minX)
        let top = min(minY, other.minY)
        let right = max(maxX, other.maxX)
        let bottom = max(maxY, other.maxY)
        return SheetOCRRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    func overlaps(_ other: SheetOCRRect, xTolerance: Double = 0, yTolerance: Double = 0) -> Bool {
        minX - xTolerance <= other.maxX
            && maxX + xTolerance >= other.minX
            && minY - yTolerance <= other.maxY
            && maxY + yTolerance >= other.minY
    }
}

struct SheetOCRTextCandidate: Equatable, Codable {
    var text: String
    var confidence: Float
}

struct SheetOCRTextObservation: Equatable, Codable {
    var text: String
    var confidence: Float
    var rect: SheetOCRRect
    var candidates: [SheetOCRTextCandidate]
    var source: SheetOCRObservationSource

    init(
        text: String,
        confidence: Float,
        rect: SheetOCRRect,
        candidates: [SheetOCRTextCandidate] = [],
        source: SheetOCRObservationSource = .fullPage
    ) {
        self.text = text
        self.confidence = confidence
        self.rect = rect
        self.candidates = candidates.isEmpty ? [SheetOCRTextCandidate(text: text, confidence: confidence)] : candidates
        self.source = source
    }
}

enum SheetOCRObservationSource: String, Equatable, Codable {
    case fullPage
    case chordZone
    case chordLabelZone
    case jianpuZone
    case lyricZone
    case lyricTextZone
}

enum SheetOCRTokenKind: String, Equatable, Codable {
    case chord
    case lyric
    case melody
    case key
    case title
    case meta
}

struct SheetOCRToken: Identifiable, Equatable, Codable {
    var id: String
    var kind: SheetOCRTokenKind
    var text: String
    var confidence: Float
    var rect: SheetOCRRect
    var originalText: String
    var edited: Bool

    init(
        id: String = UUID().uuidString,
        kind: SheetOCRTokenKind,
        text: String,
        confidence: Float,
        rect: SheetOCRRect,
        originalText: String? = nil,
        edited: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.confidence = confidence
        self.rect = rect
        self.originalText = originalText ?? text
        self.edited = edited
    }
}

struct SheetOCRSystemDraft: Identifiable, Equatable, Codable {
    var id: String
    var pageIndex: Int
    var systemIndex: Int
    var bounds: SheetOCRRect
    var staffBounds: SheetOCRRect?
    var chordZone: SheetOCRRect
    var lyricZone: SheetOCRRect
    var chords: [SheetOCRToken]
    var lyrics: [SheetOCRToken]
    var melody: [SheetOCRToken]
    var rawObservations: [SheetOCRTextObservation]

    init(
        id: String = UUID().uuidString,
        pageIndex: Int,
        systemIndex: Int,
        bounds: SheetOCRRect,
        staffBounds: SheetOCRRect?,
        chordZone: SheetOCRRect,
        lyricZone: SheetOCRRect,
        chords: [SheetOCRToken],
        lyrics: [SheetOCRToken],
        melody: [SheetOCRToken],
        rawObservations: [SheetOCRTextObservation]
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.systemIndex = systemIndex
        self.bounds = bounds
        self.staffBounds = staffBounds
        self.chordZone = chordZone
        self.lyricZone = lyricZone
        self.chords = chords
        self.lyrics = lyrics
        self.melody = melody
        self.rawObservations = rawObservations
    }
}

struct SheetOCRPageDraft: Identifiable, Equatable, Codable {
    var id: String
    var pageIndex: Int
    var originalPixelSize: CGSize
    var processedPixelSize: CGSize
    var cropRectInOriginalPixels: CGRect?
    var systems: [SheetOCRSystemDraft]
    var rawObservations: [SheetOCRTextObservation]
    var diagnostics: [String]

    init(
        id: String = UUID().uuidString,
        pageIndex: Int,
        originalPixelSize: CGSize,
        processedPixelSize: CGSize,
        cropRectInOriginalPixels: CGRect?,
        systems: [SheetOCRSystemDraft],
        rawObservations: [SheetOCRTextObservation],
        diagnostics: [String] = []
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.originalPixelSize = originalPixelSize
        self.processedPixelSize = processedPixelSize
        self.cropRectInOriginalPixels = cropRectInOriginalPixels
        self.systems = systems
        self.rawObservations = rawObservations
        self.diagnostics = diagnostics
    }
}

struct SheetOCRDraft: Equatable, Codable {
    var id: String
    var title: SheetOCRToken?
    var originalKey: SheetOCRToken?
    var pages: [SheetOCRPageDraft]
    var createdAtMs: Int
    var diagnostics: [String]

    var allSystems: [SheetOCRSystemDraft] {
        pages.flatMap(\.systems)
    }

    var rawObservations: [SheetOCRTextObservation] {
        pages.flatMap(\.rawObservations)
    }
}

struct SheetOCRStaffSystem: Equatable {
    var bounds: SheetOCRRect
    var staffBounds: SheetOCRRect
    var chordZone: SheetOCRRect
    var chordLabelZone: SheetOCRRect
    var jianpuZone: SheetOCRRect
    var lyricZone: SheetOCRRect
    var lyricTextZone: SheetOCRRect

    init(
        bounds: SheetOCRRect,
        staffBounds: SheetOCRRect,
        chordZone: SheetOCRRect,
        lyricZone: SheetOCRRect,
        chordLabelZone: SheetOCRRect? = nil,
        jianpuZone: SheetOCRRect? = nil,
        lyricTextZone: SheetOCRRect? = nil
    ) {
        self.bounds = bounds
        self.staffBounds = staffBounds
        self.chordZone = chordZone
        self.lyricZone = lyricZone

        let labelHeight = max(0.01, chordZone.height * 0.58)
        self.chordLabelZone = chordLabelZone ?? SheetOCRRect(
            x: chordZone.x,
            y: max(chordZone.y, chordZone.maxY - labelHeight),
            width: chordZone.width,
            height: labelHeight
        )

        let lyricSplitY = lyricZone.y + lyricZone.height * 0.48
        let lyricTextY = lyricZone.y + lyricZone.height * 0.20
        self.jianpuZone = jianpuZone ?? SheetOCRRect(
            x: lyricZone.x,
            y: lyricZone.y,
            width: lyricZone.width,
            height: max(0.01, lyricSplitY - lyricZone.y)
        )
        self.lyricTextZone = lyricTextZone ?? SheetOCRRect(
            x: lyricZone.x,
            y: lyricTextY,
            width: lyricZone.width,
            height: max(0.01, lyricZone.maxY - lyricTextY)
        )
    }
}

struct SheetOCRProcessedImage {
    var image: CGImage
    var originalPixelSize: CGSize
    var processedPixelSize: CGSize
    var cropRectInOriginalPixels: CGRect?
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
