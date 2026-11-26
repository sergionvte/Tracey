//
//  SheetDetector.swift
//  Tracey
//
//  Finds the sheet of paper in one camera frame with Vision.
//

import CoreVideo
import Foundation
import Vision

enum SheetDetector {
    private static let queue = DispatchQueue(label: "tracey.sheet-detector", qos: .userInitiated)

    /// The sheet's corners, normalized in the buffer (origin top-left), or nil. `completion` runs
    /// on the main queue.
    static func detect(in buffer: CVPixelBuffer, completion: @escaping (SheetGeometry.Quad?) -> Void) {
        queue.async {
            let quad = detectSync(in: buffer)
            DispatchQueue.main.async { completion(quad) }
        }
    }

    /// Blocking version (off the main thread). Rectangle detection first: it follows the paper's
    /// real edges. Document segmentation (made for paper on busy backgrounds) is the fallback;
    /// it is only trusted with good confidence.
    static func detectSync(in buffer: CVPixelBuffer) -> SheetGeometry.Quad? {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])

        let rectangles = VNDetectRectanglesRequest()
        rectangles.minimumConfidence = 0.6
        rectangles.minimumSize = 0.2
        rectangles.minimumAspectRatio = 0.3
        rectangles.maximumAspectRatio = 1
        rectangles.quadratureTolerance = 30
        rectangles.maximumObservations = 4
        if (try? handler.perform([rectangles])) != nil,
           let quad = best(rectangles.results ?? [], minimumConfidence: 0.6) {
            return quad
        }

        let document = VNDetectDocumentSegmentationRequest()
        guard (try? handler.perform([document])) != nil else { return nil }
        return best(document.results ?? [], minimumConfidence: 0.7)
    }

    /// Largest plausible observation, converted to top-left origin
    private static func best(_ observations: [VNRectangleObservation], minimumConfidence: Float) -> SheetGeometry.Quad? {
        observations
            .filter { $0.confidence >= minimumConfidence }
            .map { observation in
                SheetGeometry.Quad(topLeft: observation.topLeft, topRight: observation.topRight,
                                   bottomRight: observation.bottomRight, bottomLeft: observation.bottomLeft)
                    .map { CGPoint(x: $0.x, y: 1 - $0.y) }
            }
            .filter { SheetGeometry.isPlausible($0, in: CGSize(width: 1, height: 1)) }
            .max { area($0) < area($1) }
    }

    private static func area(_ quad: SheetGeometry.Quad) -> CGFloat {
        let p = quad.points
        var sum: CGFloat = 0
        for i in 0..<4 { sum += p[i].x * p[(i + 1) % 4].y - p[(i + 1) % 4].x * p[i].y }
        return abs(sum) / 2
    }
}
