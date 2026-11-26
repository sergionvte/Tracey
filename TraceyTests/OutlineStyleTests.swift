import Foundation
import Testing
import UIKit
@testable import Tracey

struct OutlineStyleTests {

    @Test func outlineMiddleKeepsTodaysLook() {
        let style = OutlineStyle()
        #expect(style.detail == 0.5)
        #expect(style.color == .blue)
        #expect(abs(style.lineThreshold - 0.2) < 0.0001)
        #expect(abs(style.blurRadius - 1.5) < 0.0001)
    }

    @Test func moreDetailLowersThresholdAndBlur() {
        let details: [Double] = [0, 0.25, 0.5, 0.75, 1]
        let styles = details.map { OutlineStyle(detail: $0, color: .blue) }
        for (less, more) in zip(styles, styles.dropFirst()) {
            #expect(more.lineThreshold < less.lineThreshold)
            #expect(more.blurRadius < less.blurRadius)
        }
        #expect(abs(styles[0].lineThreshold - 0.45) < 0.0001)
        #expect(abs(styles[4].lineThreshold - 0.05) < 0.0001)
        #expect(abs(styles[0].blurRadius - 3.0) < 0.0001)
        #expect(abs(styles[4].blurRadius - 0.5) < 0.0001)
    }

    @Test func detailOutsideRangeIsClamped() {
        #expect(OutlineStyle(detail: -1, color: .blue).lineThreshold == OutlineStyle(detail: 0, color: .blue).lineThreshold)
        #expect(OutlineStyle(detail: 3, color: .blue).lineThreshold == OutlineStyle(detail: 1, color: .blue).lineThreshold)
    }

    @Test func presetsStartWithTheDefaultBlue() {
        #expect(OutlineColor.presets.first == .blue)
        #expect(OutlineColor.presets.count == 6)
        #expect(abs(OutlineColor.blue.red - 0x1E / 255.0) < 0.0001)
    }

    @Test func colorRoundTripsThroughUIColor() {
        let color = OutlineColor(red: 0.2, green: 0.4, blue: 0.6)
        let back = OutlineColor(color.uiColor)
        #expect(abs(back.red - 0.2) < 0.01 && abs(back.green - 0.4) < 0.01 && abs(back.blue - 0.6) < 0.01)
    }

    @Test func outlineRendersInChosenColor() throws {
        // White square with a black square in the middle: its edges become lines
        let size = CGSize(width: 200, height: 200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            context.fill(CGRect(x: 60, y: 60, width: 80, height: 80))
        }
        let style = OutlineStyle(detail: 0.5, color: .red)
        let rendered = try #require(ReferenceFilterRenderer.shared.render(image, filter: .outline, outline: style, maxLongSide: 200))
        let pixels = try #require(TestPixels(rendered))
        let opaque = pixels.all.filter { $0.a > 0.5 }
        #expect(!opaque.isEmpty)
        // Every visible line pixel is the chosen red (#E53935), not the default blue
        #expect(opaque.allSatisfy { $0.r > 0.8 && $0.g < 0.35 && $0.b < 0.35 })
    }

    @Test func oldSavesLoadDefaultOutline() throws {
        let json = """
        {"id":"9A0B6B32-3C3F-4C7E-9B7B-2D6A4B2F1E11","imageName":"a.jpg","opacity":0.6,"scale":1,
         "rotation":0,"offsetX":0,"offsetY":0,"isFlipped":false,"dateCreated":0,"cameraZoom":1}
        """
        let config = try JSONDecoder().decode(SavedImageConfiguration.self, from: Data(json.utf8))
        #expect(config.outlineStyle == OutlineStyle())
    }

    @Test func outlineStyleSurvivesSaving() throws {
        let style = OutlineStyle(detail: 0.8, color: .purple)
        let saved = SavedImageConfiguration(imageName: "a.jpg", opacity: 0.5, scale: 1, rotation: 0, outlineStyle: style)
        let loaded = try JSONDecoder().decode(SavedImageConfiguration.self, from: JSONEncoder().encode(saved))
        #expect(loaded.outlineStyle == style)
    }
}

/// Straight (unpremultiplied) sRGB pixels of an image, 0–1.
struct TestPixels {
    struct Pixel { var r, g, b, a: Double }
    let width: Int
    let height: Int
    let all: [Pixel]

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        width = cgImage.width
        height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        all = stride(from: 0, to: bytes.count, by: 4).map { i in
            let a = Double(bytes[i + 3]) / 255
            let un = a > 0 ? 1 / a : 0
            return Pixel(r: Double(bytes[i]) / 255 * un, g: Double(bytes[i + 1]) / 255 * un,
                         b: Double(bytes[i + 2]) / 255 * un, a: a)
        }
    }

    /// Row 0 is the top of the image
    func pixel(x: Int, y: Int) -> Pixel { all[y * width + x] }
}
