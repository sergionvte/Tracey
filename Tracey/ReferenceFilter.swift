//
//  ReferenceFilter.swift
//  Tracey
//
//  Filters that make a reference easier to trace. The original image is never modified: the
//  filtered version is only what gets drawn over the camera.
//

import UIKit
import CoreImage

enum ReferenceFilter: String, CaseIterable, Identifiable, Codable {
    case original
    case blackAndWhite
    case contrast
    case outline

    var id: String { rawValue }

    /// Short label under the tile
    var label: String {
        switch self {
        case .original: return "Original"
        case .blackAndWhite: return "B&W"
        case .contrast: return "Contrast"
        case .outline: return "Outline"
        }
    }

    /// Spoken name (VoiceOver)
    var accessibilityName: String {
        switch self {
        case .original: return "Original"
        case .blackAndWhite: return "Black and white"
        case .contrast: return "High contrast"
        case .outline: return "Outline"
        }
    }
}

/// Renders reference filters with one shared Core Image context. Thread-safe; call it off the
/// main thread.
final class ReferenceFilterRenderer {
    static let shared = ReferenceFilterRenderer()

    private let context = CIContext(options: [.cacheIntermediates: false])

    /// Outline line color: blue #1E6BFF, so reference lines can't be mistaken for graphite.
    /// Core Image works in linear light, so the sRGB components are linearized; the plain
    /// (0.118, 0.420, 1.0) bias would come out as a much lighter blue.
    private let outlineColor = (red: ReferenceFilterRenderer.linear(0x1E),
                                green: ReferenceFilterRenderer.linear(0x6B),
                                blue: ReferenceFilterRenderer.linear(0xFF))

    private static func linear(_ component: Int) -> CGFloat {
        let c = CGFloat(component) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// `image` with `filter` applied, downscaled so its long side is at most `maxLongSide`
    /// pixels. The result keeps the original's point size (same aspect ratio), so fitting,
    /// snapping and hit testing don't change. Returns nil if Core Image fails.
    func render(_ image: UIImage, filter: ReferenceFilter, maxLongSide: CGFloat) -> UIImage? {
        guard var input = Self.orientedCIImage(from: image) else { return nil }

        let extent = input.extent
        let longSide = max(extent.width, extent.height)
        guard longSide > 0 else { return nil }
        if longSide > maxLongSide {
            let scale = maxLongSide / longSide
            input = input.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1.0
            ])
        }
        // Lanczos can leave a fractional extent; filters below work on whole pixels. Clamping
        // keeps edge-detecting filters from drawing a line along the image border.
        let workExtent = input.extent.integral
        input = input.cropped(to: workExtent).clampedToExtent()

        let output: CIImage
        switch filter {
        case .original:
            output = input
        case .blackAndWhite:
            output = input.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0
            ])
        case .contrast:
            output = input.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 1.6
            ])
        case .outline:
            // Black lines on transparent, recolored blue (alpha kept from the lines)
            let lines = input
                .applyingFilter("CILineOverlay")
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: outlineColor.red, y: outlineColor.green,
                                                z: outlineColor.blue, w: 0)
                ])
            output = lines
        }

        guard let cgImage = context.createCGImage(output.cropped(to: workExtent), from: workExtent) else {
            return nil
        }
        // Same point size as the original: only the pixel density differs
        let pointWidth = max(image.size.width, 1)
        let scale = CGFloat(cgImage.width) / pointWidth
        return UIImage(cgImage: cgImage, scale: max(scale, 0.01), orientation: .up)
    }

    /// Core Image doesn't apply UIImage orientation by itself.
    private static func orientedCIImage(from image: UIImage) -> CIImage? {
        if let cgImage = image.cgImage {
            return CIImage(cgImage: cgImage).oriented(CGImagePropertyOrientation(image.imageOrientation))
        }
        if let ciImage = image.ciImage { return ciImage }
        // e.g. a symbol or drawn image: rasterize first
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let rendered = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }
        return rendered.cgImage.map { CIImage(cgImage: $0) }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
