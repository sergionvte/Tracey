//
//  SheetGeometry.swift
//  Tracey
//
//  Geometry for "Fit to Sheet": from the four corners of the paper seen by the camera to the
//  overlay's offset, scale and rotation (the same model the gestures use).
//

import CoreGraphics
import Foundation

enum SheetGeometry {
    /// Four corners, in order around the sheet. Any coordinate space (y down).
    struct Quad: Equatable {
        var topLeft: CGPoint
        var topRight: CGPoint
        var bottomRight: CGPoint
        var bottomLeft: CGPoint

        var points: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

        func map(_ transform: (CGPoint) -> CGPoint) -> Quad {
            Quad(topLeft: transform(topLeft), topRight: transform(topRight),
                 bottomRight: transform(bottomRight), bottomLeft: transform(bottomLeft))
        }
    }

    /// A point normalized in a camera buffer delivered with `rotationAngle` (degrees clockwise,
    /// 0/90/180/270), back in the sensor's own normalized space ("device" coordinates, origin
    /// top-left), which the preview layer knows how to convert.
    static func devicePoint(fromBuffer p: CGPoint, rotationAngle: CGFloat) -> CGPoint {
        switch Int((rotationAngle.truncatingRemainder(dividingBy: 360) + 360).rounded()) % 360 {
        case 90: return CGPoint(x: p.y, y: 1 - p.x)
        case 180: return CGPoint(x: 1 - p.x, y: 1 - p.y)
        case 270: return CGPoint(x: 1 - p.y, y: p.x)
        default: return p
        }
    }

    /// A convex quadrilateral covering at least 8% of `size`: anything smaller or twisted is
    /// noise, not the paper.
    static func isPlausible(_ quad: Quad, in size: CGSize) -> Bool {
        let points = quad.points
        var sign: CGFloat = 0
        for i in 0..<4 {
            let a = points[i], b = points[(i + 1) % 4], c = points[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            guard abs(cross) > 1e-9 else { return false }
            if sign == 0 { sign = cross } else if (cross > 0) != (sign > 0) { return false }
        }
        // Shoelace area
        var area: CGFloat = 0
        for i in 0..<4 {
            let a = points[i], b = points[(i + 1) % 4]
            area += a.x * b.y - b.x * a.y
        }
        return abs(area) / 2 >= 0.08 * size.width * size.height
    }

    /// The rectangle that best matches the quad: its center, side lengths (averages of opposite
    /// sides) and the angle of its top/bottom sides in degrees (clockwise, y down).
    static func sheetRect(_ quad: Quad) -> (center: CGPoint, size: CGSize, angle: Double) {
        let p = quad.points
        let center = CGPoint(x: p.map(\.x).reduce(0, +) / 4, y: p.map(\.y).reduce(0, +) / 4)
        func length(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
        let width = (length(quad.topLeft, quad.topRight) + length(quad.bottomLeft, quad.bottomRight)) / 2
        let height = (length(quad.topLeft, quad.bottomLeft) + length(quad.topRight, quad.bottomRight)) / 2
        // Sum the two side vectors so angles near ±180° average correctly
        let dx = (quad.topRight.x - quad.topLeft.x) + (quad.bottomRight.x - quad.bottomLeft.x)
        let dy = (quad.topRight.y - quad.topLeft.y) + (quad.bottomRight.y - quad.bottomLeft.y)
        let angle = atan2(Double(dy), Double(dx)) * 180 / .pi
        return (center, CGSize(width: width, height: height), angle)
    }

    /// Offset, scale and rotation that put an image of `imageSize` on the sheet: centered on it,
    /// turned like it, as large as fits inside with `margin` on each side. Of the four quarter
    /// turns it uses the one where the image is largest (a landscape image on a portrait sheet
    /// turns 90°), and among equal ones the closest to `currentRotation`, so it never flips
    /// upside down. `layoutRect` is the rect the overlay aspect-fits into before its scale.
    /// The rotation is in 0..<360.
    static func placement(sheet: Quad, imageSize: CGSize, layoutRect: CGRect, currentRotation: Double,
                          margin: CGFloat = 0.03) -> (offset: CGSize, scale: CGFloat, rotation: Double) {
        let rect = sheetRect(sheet)
        let offset = CGSize(width: rect.center.x - layoutRect.midX, height: rect.center.y - layoutRect.midY)
        guard imageSize.width > 0, imageSize.height > 0, layoutRect.width > 0, layoutRect.height > 0 else {
            return (offset, 1, normalized(rect.angle))
        }
        let baseFit = min(layoutRect.width / imageSize.width, layoutRect.height / imageSize.height)
        let availableWidth = rect.size.width * (1 - 2 * margin)
        let availableHeight = rect.size.height * (1 - 2 * margin)

        var best: (fit: CGFloat, rotation: Double, distance: Double)?
        for quarter in 0..<4 {
            let turned = quarter % 2 == 1
            let w = turned ? imageSize.height : imageSize.width
            let h = turned ? imageSize.width : imageSize.height
            let fit = min(availableWidth / w, availableHeight / h)
            let rotation = normalized(rect.angle + Double(quarter) * 90)
            let distance = angularDistance(rotation, currentRotation)
            if let current = best {
                let tolerance = current.fit * 1e-6
                if fit > current.fit + tolerance || (abs(fit - current.fit) <= tolerance && distance < current.distance) {
                    best = (fit, rotation, distance)
                }
            } else {
                best = (fit, rotation, distance)
            }
        }
        let chosen = best!
        return (offset, chosen.fit / baseFit, chosen.rotation)
    }

    private static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private static func angularDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(normalized(a) - normalized(b))
        return min(d, 360 - d)
    }
}
