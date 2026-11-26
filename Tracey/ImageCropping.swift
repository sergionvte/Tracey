//
//  ImageCropping.swift
//  Tracey
//
//  Recoverable crops: the full photo is kept and a normalized crop rectangle says which part is
//  shown. These helpers cut that part out and keep it in place on screen when the crop changes.
//

import UIKit

enum ImageCropping {
    /// The whole image
    static let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Smallest crop side, as a fraction of the image (keeps a crop from collapsing)
    static let minimumSide: CGFloat = 0.05

    /// `image` redrawn so its pixels are upright (`.up`). Crop rectangles are expressed in this
    /// space, so a photo taken sideways crops the part that was seen.
    static func normalizedUp(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up, image.cgImage != nil { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// A crop rectangle that is inside the image and not degenerate (unit rect otherwise)
    static func sanitized(_ rect: CGRect?) -> CGRect {
        guard let rect, rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite
        else { return unitRect }
        let clamped = rect.standardized.intersection(unitRect)
        guard !clamped.isNull, clamped.width >= minimumSide * 0.99, clamped.height >= minimumSide * 0.99 else { return unitRect }
        return clamped
    }

    /// The part of `image` inside `rect` (normalized, origin top-left, in upright space).
    /// Returns the upright image itself for the full rect, nil if Core Graphics fails.
    static func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        let upright = normalizedUp(image)
        let rect = sanitized(rect)
        if rect == unitRect { return upright }
        guard let cgImage = upright.cgImage else { return nil }
        let width = CGFloat(cgImage.width), height = CGFloat(cgImage.height)
        let pixels = CGRect(x: rect.minX * width, y: rect.minY * height,
                            width: rect.width * width, height: rect.height * height)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard pixels.width >= 1, pixels.height >= 1, let cropped = cgImage.cropping(to: pixels) else { return nil }
        return UIImage(cgImage: cropped, scale: upright.scale, orientation: .up)
    }

    /// New scale and offset after changing the crop from `oldCrop` to `newCrop`, so the part of
    /// the photo that stays doesn't move or change size on screen. The overlay aspect-fits its
    /// image inside the layout rect and then applies mirror → scale → rotation about its center
    /// (see `CameraUIView.layoutOverlay`).
    static func placementAfterCrop(sourceSize: CGSize, oldCrop: CGRect, newCrop: CGRect, layoutSize: CGSize,
                                   scale: CGFloat, offset: CGSize, rotation: Double,
                                   isFlipped: Bool, isFlippedVertically: Bool) -> (scale: CGFloat, offset: CGSize) {
        func fit(_ crop: CGRect) -> CGFloat {
            let w = sourceSize.width * crop.width, h = sourceSize.height * crop.height
            guard w > 0, h > 0, layoutSize.width > 0, layoutSize.height > 0 else { return 1 }
            return min(layoutSize.width / w, layoutSize.height / h)
        }
        // Points per source pixel stay the same
        let pointsPerPixel = fit(oldCrop) * scale
        let newScale = pointsPerPixel / fit(newCrop)

        // The new crop's center relative to the old one, in on-screen points before rotation
        var dx = (newCrop.midX - oldCrop.midX) * sourceSize.width * pointsPerPixel
        var dy = (newCrop.midY - oldCrop.midY) * sourceSize.height * pointsPerPixel
        if isFlipped { dx = -dx }
        if isFlippedVertically { dy = -dy }
        let angle = rotation * .pi / 180
        let rx = dx * cos(angle) - dy * sin(angle)
        let ry = dx * sin(angle) + dy * cos(angle)
        return (newScale, CGSize(width: offset.width + rx, height: offset.height + ry))
    }
}

/// Crop frame proportions offered in the crop screen.
enum CropAspect: String, CaseIterable, Identifiable {
    case free, original, letter, a4, square

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: String(localized: "Free")
        case .original: String(localized: "Original")
        case .letter: String(localized: "Letter")
        case .a4: "A4"
        case .square: String(localized: "Square")
        }
    }

    /// Paper sizes can be turned to landscape
    var canTurn: Bool { self == .letter || self == .a4 }

    /// Width / height of the crop in pixels, or nil when free
    func ratio(sourceSize: CGSize, landscape: Bool) -> CGFloat? {
        let portrait: CGFloat
        switch self {
        case .free: return nil
        case .original:
            guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
            return sourceSize.width / sourceSize.height
        case .square: return 1
        case .letter: portrait = 8.5 / 11
        case .a4: portrait = 210 / 297
        }
        return landscape ? 1 / portrait : portrait
    }
}
