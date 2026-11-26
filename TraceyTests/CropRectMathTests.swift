import Foundation
import Testing
@testable import Tracey

struct CropRectMathTests {
    private let minSize: CGFloat = 0.05

    private func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.0001 && abs(a.minY - b.minY) < 0.0001
            && abs(a.width - b.width) < 0.0001 && abs(a.height - b.height) < 0.0001
    }

    @Test func dragCornerShrinks() {
        let result = CropRectMath.adjust(ImageCropping.unitRect, handle: .bottomRight,
                                         by: CGSize(width: -0.2, height: -0.1), aspect: nil, minSize: minSize)
        #expect(close(result, CGRect(x: 0, y: 0, width: 0.8, height: 0.9)))
    }

    @Test func dragEdgeMovesOnlyThatEdge() {
        let result = CropRectMath.adjust(ImageCropping.unitRect, handle: .left,
                                         by: CGSize(width: 0.3, height: 0.4), aspect: nil, minSize: minSize)
        #expect(close(result, CGRect(x: 0.3, y: 0, width: 0.7, height: 1)))
    }

    @Test func handlesStayInsideImage() {
        let start = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        let corner = CropRectMath.adjust(start, handle: .topLeft, by: CGSize(width: -0.5, height: -0.5),
                                         aspect: nil, minSize: minSize)
        #expect(close(corner, CGRect(x: 0, y: 0, width: 0.6, height: 0.6)))
        let moved = CropRectMath.adjust(start, handle: .move, by: CGSize(width: 0.9, height: -0.9),
                                        aspect: nil, minSize: minSize)
        #expect(close(moved, CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)))
    }

    @Test func aspectIsKept() {
        let start = CGRect(x: 0, y: 0, width: 0.4, height: 0.2)
        let corner = CropRectMath.adjust(start, handle: .bottomRight, by: CGSize(width: 0.3, height: 0),
                                         aspect: 2, minSize: minSize)
        #expect(abs(corner.width / corner.height - 2) < 0.0001)
        #expect(corner.width > 0.4)
        #expect(ImageCropping.unitRect.contains(corner))

        let edge = CropRectMath.adjust(CGRect(x: 0.2, y: 0.4, width: 0.4, height: 0.2), handle: .right,
                                       by: CGSize(width: 0.2, height: 0), aspect: 2, minSize: minSize)
        #expect(abs(edge.width / edge.height - 2) < 0.0001)
        #expect(abs(edge.midY - 0.5) < 0.0001)

        // Growing past the image stops at the border, still in proportion
        let big = CropRectMath.adjust(start, handle: .bottomRight, by: CGSize(width: 5, height: 5),
                                      aspect: 2, minSize: minSize)
        #expect(abs(big.width / big.height - 2) < 0.0001)
        #expect(ImageCropping.unitRect.contains(big))
        #expect(abs(big.width - 1) < 0.0001)
    }

    @Test func minimumSize() {
        let result = CropRectMath.adjust(ImageCropping.unitRect, handle: .bottomRight,
                                         by: CGSize(width: -2, height: -2), aspect: nil, minSize: minSize)
        #expect(abs(result.width - minSize) < 0.0001 && abs(result.height - minSize) < 0.0001)
        #expect(result.minX == 0 && result.minY == 0)
    }

    @Test func fittedIsTheLargestInProportion() {
        #expect(close(CropRectMath.fitted(ImageCropping.unitRect, aspect: 0.5),
                      CGRect(x: 0.25, y: 0, width: 0.5, height: 1)))
        // Centered on the current rect, pushed back inside when needed
        let fitted = CropRectMath.fitted(CGRect(x: 0.8, y: 0, width: 0.2, height: 1), aspect: 1)
        #expect(close(fitted, CGRect(x: 0, y: 0, width: 1, height: 1)))
    }
}
