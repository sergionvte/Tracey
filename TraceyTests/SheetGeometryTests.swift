import Foundation
import Testing
@testable import Tracey

struct SheetGeometryTests {
    private typealias Quad = SheetGeometry.Quad

    private func close(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 0.0001) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
    }

    /// Axis-aligned `size` sheet centered at `center`, then turned `degrees` clockwise
    private func sheet(center: CGPoint, size: CGSize, degrees: Double = 0) -> Quad {
        let angle = degrees * .pi / 180
        func point(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: center.x + dx * cos(angle) - dy * sin(angle), y: center.y + dx * sin(angle) + dy * cos(angle))
        }
        let w = size.width / 2, h = size.height / 2
        return Quad(topLeft: point(-w, -h), topRight: point(w, -h), bottomRight: point(w, h), bottomLeft: point(-w, h))
    }

    private let layout = CGRect(x: 0, y: 0, width: 400, height: 800)

    @Test func deviceMappingUndoesTheBufferRotation() {
        let p = CGPoint(x: 0.2, y: 0.3)
        #expect(close(SheetGeometry.devicePoint(fromBuffer: p, rotationAngle: 0), p))
        #expect(close(SheetGeometry.devicePoint(fromBuffer: p, rotationAngle: 90), CGPoint(x: 0.3, y: 0.8)))
        #expect(close(SheetGeometry.devicePoint(fromBuffer: p, rotationAngle: 180), CGPoint(x: 0.8, y: 0.7)))
        #expect(close(SheetGeometry.devicePoint(fromBuffer: p, rotationAngle: 270), CGPoint(x: 0.7, y: 0.2)))
    }

    @Test func tinyQuadIsNotASheet() {
        let size = CGSize(width: 400, height: 800)
        #expect(!SheetGeometry.isPlausible(sheet(center: CGPoint(x: 200, y: 400), size: CGSize(width: 20, height: 20)), in: size))
        #expect(SheetGeometry.isPlausible(sheet(center: CGPoint(x: 200, y: 400), size: CGSize(width: 300, height: 400)), in: size))
        // Crossed corners (a bow tie) aren't a sheet
        let crossed = Quad(topLeft: CGPoint(x: 50, y: 200), topRight: CGPoint(x: 350, y: 600),
                           bottomRight: CGPoint(x: 350, y: 200), bottomLeft: CGPoint(x: 50, y: 600))
        #expect(!SheetGeometry.isPlausible(crossed, in: size))
    }

    @Test func sheetRectOfATurnedSheet() {
        let rect = SheetGeometry.sheetRect(sheet(center: CGPoint(x: 210, y: 390), size: CGSize(width: 300, height: 400), degrees: 10))
        #expect(close(rect.center, CGPoint(x: 210, y: 390), 0.01))
        #expect(abs(rect.size.width - 300) < 0.01 && abs(rect.size.height - 400) < 0.01)
        #expect(abs(rect.angle - 10) < 0.01)
    }

    @Test func axisAlignedSheetCentersAndFits() {
        // A 3:4 image on a 300×400 sheet: 3% margin per side → 376 pt tall, centered, upright
        let image = CGSize(width: 300, height: 400)
        let result = SheetGeometry.placement(sheet: sheet(center: CGPoint(x: 200, y: 400), size: CGSize(width: 300, height: 400)),
                                             imageSize: image, layoutRect: layout, currentRotation: 0)
        let baseFit = min(layout.width / image.width, layout.height / image.height)
        #expect(abs(image.height * baseFit * result.scale - 376) < 0.01)
        #expect(abs(result.offset.width) < 0.01 && abs(result.offset.height) < 0.01)
        #expect(abs(result.rotation) < 0.01)
    }

    @Test func landscapeImageTurnsOnPortraitSheet() {
        let result = SheetGeometry.placement(sheet: sheet(center: CGPoint(x: 200, y: 400), size: CGSize(width: 300, height: 400)),
                                             imageSize: CGSize(width: 400, height: 300), layoutRect: layout, currentRotation: 0)
        #expect(abs(result.rotation - 90) < 0.01 || abs(result.rotation - 270) < 0.01)
    }

    @Test func upsideDownSheetStaysUpright() {
        let result = SheetGeometry.placement(sheet: sheet(center: CGPoint(x: 200, y: 400), size: CGSize(width: 300, height: 400), degrees: 178),
                                             imageSize: CGSize(width: 300, height: 400), layoutRect: layout, currentRotation: 0)
        #expect(abs(result.rotation - 358) < 0.01)
    }

    @Test func offsetFollowsSheetCenter() {
        let result = SheetGeometry.placement(sheet: sheet(center: CGPoint(x: 250, y: 450), size: CGSize(width: 200, height: 300)),
                                             imageSize: CGSize(width: 300, height: 400), layoutRect: layout, currentRotation: 0)
        #expect(abs(result.offset.width - 50) < 0.01 && abs(result.offset.height - 50) < 0.01)
    }
}
