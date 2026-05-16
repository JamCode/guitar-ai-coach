import CoreGraphics
import Foundation

struct SheetStaffSystemDetector {
    var darkLumaThreshold: UInt8 = 150
    var minDarkPixelRatioForLine: Double = 0.14
    var minLineSpacingPx: Double = 3

    func detectSystems(in image: CGImage) -> [SheetOCRStaffSystem] {
        guard let pixels = image.rgba8Pixels() else { return [] }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }

        let candidateRows = darkCandidateRows(pixels: pixels, width: width, height: height)
        let lineCenters = rowGroups(from: candidateRows).map { group in
            Double(group.reduce(0, +)) / Double(group.count)
        }
        let staffBounds = findSixLineStaffBounds(lineCenters: lineCenters, imageHeight: height)
        return buildSystems(from: staffBounds, imageWidth: width, imageHeight: height)
    }

    private func darkCandidateRows(pixels: [UInt8], width: Int, height: Int) -> [Int] {
        var rows: [Int] = []
        let minDark = max(12, Int(Double(width) * minDarkPixelRatioForLine))
        for y in 0..<height {
            var dark = 0
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let r = pixels[idx]
                let g = pixels[idx + 1]
                let b = pixels[idx + 2]
                let luma = UInt8((UInt16(r) * 30 + UInt16(g) * 59 + UInt16(b) * 11) / 100)
                if luma < darkLumaThreshold {
                    dark += 1
                }
            }
            if dark >= minDark {
                rows.append(y)
            }
        }
        return rows
    }

    private func rowGroups(from rows: [Int]) -> [[Int]] {
        guard let first = rows.first else { return [] }
        var groups: [[Int]] = [[first]]
        for row in rows.dropFirst() {
            if let last = groups.last?.last, row <= last + 2 {
                groups[groups.count - 1].append(row)
            } else {
                groups.append([row])
            }
        }
        return groups
    }

    private func findSixLineStaffBounds(lineCenters: [Double], imageHeight: Int) -> [ClosedRange<Double>] {
        guard lineCenters.count >= 6 else { return [] }
        var ranges: [ClosedRange<Double>] = []
        var idx = 0
        while idx <= lineCenters.count - 6 {
            let window = Array(lineCenters[idx..<(idx + 6)])
            let spacings = zip(window, window.dropFirst()).map { $1 - $0 }
            let median = spacings.sorted()[spacings.count / 2]
            let tolerance = max(3, median * 0.45)
            let consistent = median >= minLineSpacingPx
                && median <= Double(imageHeight) * 0.035
                && spacings.allSatisfy { abs($0 - median) <= tolerance }
            if consistent {
                let start = max(0, window[0] - median * 0.55)
                let end = min(Double(imageHeight - 1), window[5] + median * 0.55)
                if ranges.last?.overlaps(start...end) == true {
                    let last = ranges.removeLast()
                    ranges.append(min(last.lowerBound, start)...max(last.upperBound, end))
                } else {
                    ranges.append(start...end)
                }
                idx += 6
            } else {
                idx += 1
            }
        }
        return ranges
    }

    private func buildSystems(
        from staffRanges: [ClosedRange<Double>],
        imageWidth: Int,
        imageHeight: Int
    ) -> [SheetOCRStaffSystem] {
        guard !staffRanges.isEmpty else { return [] }
        return staffRanges.enumerated().map { idx, staffRange in
            let staffTop = staffRange.lowerBound / Double(imageHeight)
            let staffBottom = staffRange.upperBound / Double(imageHeight)
            let staffHeight = max(0.01, staffBottom - staffTop)
            let prevBottom = idx > 0 ? staffRanges[idx - 1].upperBound / Double(imageHeight) : 0
            let nextTop = idx + 1 < staffRanges.count ? staffRanges[idx + 1].lowerBound / Double(imageHeight) : 1

            let chordTop = max(prevBottom, staffTop - staffHeight * 3.1)
            let chordBottom = max(chordTop + 0.01, staffTop - staffHeight * 0.08)
            let lyricTop = min(1, staffBottom + staffHeight * 0.18)
            let lyricBottom = min(nextTop, staffBottom + staffHeight * 2.35)
            let lyricSplit = lyricTop + max(0.01, lyricBottom - lyricTop) * 0.48
            let boundsTop = min(chordTop, staffTop)
            let boundsBottom = max(lyricBottom, staffBottom)

            let staff = SheetOCRRect(x: 0, y: staffTop, width: 1, height: staffBottom - staffTop)
            let chordZone = SheetOCRRect(x: 0, y: chordTop, width: 1, height: chordBottom - chordTop)
            let lyricZone = SheetOCRRect(x: 0, y: lyricTop, width: 1, height: max(0.01, lyricBottom - lyricTop))
            return SheetOCRStaffSystem(
                bounds: SheetOCRRect(x: 0, y: boundsTop, width: 1, height: boundsBottom - boundsTop),
                staffBounds: staff,
                chordZone: chordZone,
                lyricZone: lyricZone,
                chordLabelZone: SheetOCRRect(x: 0, y: chordTop, width: 1, height: max(0.01, chordZone.height * 0.58)),
                jianpuZone: SheetOCRRect(x: 0, y: lyricTop, width: 1, height: max(0.01, lyricSplit - lyricTop)),
                lyricTextZone: SheetOCRRect(x: 0, y: lyricSplit, width: 1, height: max(0.01, lyricBottom - lyricSplit))
            )
        }
    }
}
