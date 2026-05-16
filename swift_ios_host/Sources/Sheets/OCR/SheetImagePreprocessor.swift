import CoreGraphics
import Foundation
import UIKit

struct SheetImagePreprocessor {
    var blackBorderLumaThreshold: UInt8 = 28
    var minContentCoverage: Double = 0.20

    func preprocess(_ image: UIImage) throws -> SheetOCRProcessedImage {
        guard let normalized = normalizedCGImage(from: image) else {
            throw SheetOCRError.invalidImage
        }
        let originalSize = CGSize(width: normalized.width, height: normalized.height)
        let cropRect = detectNonBlackContentBounds(in: normalized)
        let cropped: CGImage
        let cropRectInOriginalPixels: CGRect?
        if let cropRect,
           cropRect.width * cropRect.height >= originalSize.width * originalSize.height * minContentCoverage,
           cropRect.width < originalSize.width * 0.995 || cropRect.height < originalSize.height * 0.995,
           let image = normalized.cropping(to: cropRect.integral) {
            cropped = image
            cropRectInOriginalPixels = cropRect.integral
        } else {
            cropped = normalized
            cropRectInOriginalPixels = nil
        }
        return SheetOCRProcessedImage(
            image: cropped,
            originalPixelSize: originalSize,
            processedPixelSize: CGSize(width: cropped.width, height: cropped.height),
            cropRectInOriginalPixels: cropRectInOriginalPixels
        )
    }

    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage {
            return cg
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }

    private func detectNonBlackContentBounds(in image: CGImage) -> CGRect? {
        guard let rgba = image.rgba8Pixels() else { return nil }
        let width = image.width
        let height = image.height
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var found = false
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let r = rgba[idx]
                let g = rgba[idx + 1]
                let b = rgba[idx + 2]
                let luma = UInt8((UInt16(r) * 30 + UInt16(g) * 59 + UInt16(b) * 11) / 100)
                if luma > blackBorderLumaThreshold {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                    found = true
                }
            }
        }
        guard found else { return nil }
        let pad = max(2, min(width, height) / 200)
        minX = max(0, minX - pad)
        minY = max(0, minY - pad)
        maxX = min(width - 1, maxX + pad)
        maxY = min(height - 1, maxY + pad)
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX + 1), height: max(1, maxY - minY + 1))
    }
}

enum SheetOCRError: Error, LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无法读取谱图"
        }
    }
}

extension CGImage {
    func rgba8Pixels() -> [UInt8]? {
        let width = width
        let height = height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }
}
