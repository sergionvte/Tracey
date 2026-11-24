// Draws Tracey's app icons: one glowing wave on the app's dark warm background, its first half
// traced in solid ink and the second half still a dashed guide — the part you've traced and
// the part still to trace.
//
//   swift Tools/make-icons.swift            → writes every icon set into the asset catalog
//   swift Tools/make-icons.swift <out-dir>  → writes flat PNG previews there instead
//
// Each variant gets a light (opaque), dark (transparent background) and tinted image, plus a
// small preview image the Settings screen shows.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RGB {
    let r, g, b: CGFloat
    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }
    func cg(_ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

struct Variant {
    let id: String          // asset name suffix ("" for the primary icon)
    let top: RGB, bottom: RGB
    let line: RGB
    var darkLine: RGB? = nil    // the line on iOS's dark backdrop, when `line` doesn't work there
    var gridLines: RGB? = nil   // a light graph-paper background instead of the dark glow
}

let warmTop = RGB(0x2A2016), warmBottom = RGB(0x0E0B08)   // the app's backdrop
let variants: [Variant] = [
    Variant(id: "", top: warmTop, bottom: warmBottom, line: RGB(0xFFB84D)),   // the app's accent
    Variant(id: "Indigo", top: warmTop, bottom: warmBottom, line: RGB(0x8E98FF)),
    Variant(id: "Mint", top: warmTop, bottom: warmBottom, line: RGB(0x5FE0B6)),
    Variant(id: "Rose", top: warmTop, bottom: warmBottom, line: RGB(0xFF8DB0)),
    Variant(id: "Graphite", top: RGB(0x2C2C2F), bottom: RGB(0x0D0D0F), line: RGB(0xE9E9EE)),
    // Special edition: blue ink on a cream page of graph paper
    Variant(id: "Notebook", top: RGB(0xFBF6EA), bottom: RGB(0xF1E8D3), line: RGB(0x1F4FC9),
            darkLine: RGB(0x7FA0FF), gridLines: RGB(0xDDD1B6)),
]

let size = 1024
enum Appearance { case light, dark, tinted }

// MARK: - Geometry (top-left origin, y down)

// A sine-like wave around the canvas center: the crest (left) is traced, the trough (right)
// is still to trace. Nudged right and down a little: the solid, glowing crest is heavier than
// the dashed trough, so a mathematically centered wave looks high and to the left.
let center = CGPoint(x: 512 + 8, y: 512 + 10)
let halfWidth: CGFloat = 300, amplitude: CGFloat = 150
let stroke: CGFloat = 64
// Round dots, a little closer together than they are wide
let dash: CGFloat = stroke, dashGap: CGFloat = 0.5 * stroke   // as seen, round caps included
let guideOpacity: CGFloat = 0.6

let lift = amplitude * 4 / 3    // control points that put the curve's peak at `amplitude`
let crest = [CGPoint(x: -halfWidth, y: 0), CGPoint(x: -halfWidth * 0.7, y: -lift),
             CGPoint(x: -halfWidth * 0.3, y: -lift), CGPoint(x: 0, y: 0)]
let trough = crest.map { CGPoint(x: -$0.x, y: -$0.y) }.reversed() as [CGPoint]

func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

/// The part of the cubic after t (de Casteljau)
func tail(_ p: [CGPoint], from t: CGFloat) -> [CGPoint] {
    let a = lerp(p[0], p[1], t), b = lerp(p[1], p[2], t), c = lerp(p[2], p[3], t)
    let d = lerp(a, b, t), e = lerp(b, c, t)
    return [lerp(d, e, t), e, c, p[3]]
}

func cubicPath(_ p: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    path.move(to: p[0])
    path.addCurve(to: p[3], control1: p[1], control2: p[2])
    return path
}

/// The dashed guide: a gap after the solid line, then evenly spaced dashes, the last one
/// ending where the wave ends
let guide: (path: CGPath, lengths: [CGFloat]) = {
    let n = 400
    let points = (0...n).map { i -> CGPoint in
        let t = CGFloat(i) / CGFloat(n), u = 1 - t
        return CGPoint(x: u * u * u * trough[0].x + 3 * u * u * t * trough[1].x + 3 * u * t * t * trough[2].x + t * t * t * trough[3].x,
                       y: u * u * u * trough[0].y + 3 * u * u * t * trough[1].y + 3 * u * t * t * trough[2].y + t * t * t * trough[3].y)
    }
    var lengths: [CGFloat] = [0]
    for (a, b) in zip(points, points.dropFirst()) { lengths.append(lengths.last! + hypot(b.x - a.x, b.y - a.y)) }
    let start = stroke / 2 + dashGap + stroke / 2               // where the first dash begins
    let startT = CGFloat(lengths.firstIndex { $0 >= start }!) / CGFloat(n)
    let drawn = dash - stroke                                   // round caps add the rest
    let span = lengths.last! - start - drawn
    let count = max(2, Int((span / (dash + dashGap)).rounded()) + 1)
    let period = span / CGFloat(count - 1) - 1   // a hair short, so the last one isn't lost to rounding
    return (cubicPath(tail(trough, from: startT)), [drawn, period - drawn])
}()

// MARK: - Drawing

func draw(_ v: Variant, _ look: Appearance, in ctx: CGContext) {
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)
    let space = CGColorSpace(name: CGColorSpace.sRGB)

    let solid: CGColor, guideColor: CGColor
    var glow: CGColor? = nil
    switch look {
    case .light:
        // Draws past both ends so no corner is left unpainted
        let base = CGGradient(colorsSpace: space, colors: [v.top.cg(), v.bottom.cg()] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(base, start: CGPoint(x: 512, y: 0), end: CGPoint(x: 512, y: 1024),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        if let grid = v.gridLines {
            ctx.setStrokeColor(grid.cg())
            ctx.setLineWidth(6)
            for i in stride(from: 512 % 96, to: size, by: 96) {   // symmetric about the center
                ctx.move(to: CGPoint(x: CGFloat(i), y: 0)); ctx.addLine(to: CGPoint(x: CGFloat(i), y: CGFloat(size)))
                ctx.move(to: CGPoint(x: 0, y: CGFloat(i))); ctx.addLine(to: CGPoint(x: CGFloat(size), y: CGFloat(i)))
            }
            ctx.strokePath()
        } else {
            // The soft glow in the middle of the app's backdrop, in the line's color
            let halo = CGGradient(colorsSpace: space, colors: [v.line.cg(0.2), v.line.cg(0)] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(halo, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                                   endCenter: CGPoint(x: 512, y: 512), endRadius: 560, options: [])
            glow = v.line.cg(0.55)
        }
        solid = v.line.cg(); guideColor = v.line.cg(guideOpacity)
    case .dark:
        // Transparent background: iOS draws its own dark backdrop
        let line = v.darkLine ?? v.line
        solid = line.cg(); guideColor = line.cg(guideOpacity); glow = line.cg(0.55)
    case .tinted:
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(full)
        solid = CGColor(gray: 1, alpha: 1); guideColor = CGColor(gray: 0.5, alpha: 1)
    }

    ctx.translateBy(x: center.x, y: center.y)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(stroke)

    // Still to trace
    ctx.addPath(guide.path)
    ctx.setStrokeColor(guideColor)
    ctx.setLineDash(phase: 0, lengths: guide.lengths)
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])

    // Traced, glowing softly like the app's accent
    if let glow { ctx.setShadow(offset: .zero, blur: 60, color: glow) }
    ctx.addPath(cubicPath(crest))
    ctx.setStrokeColor(solid)
    ctx.strokePath()
}

// MARK: - Output

func render(_ v: Variant, _ look: Appearance, side: Int = size) -> CGImage {
    let opaque = look != .dark
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
    draw(v, look, in: ctx)
    let image = ctx.makeImage()!
    guard side != size else { return image }
    let small = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    small.interpolationQuality = .high
    small.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return small.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "Couldn't write \(url.path)")
}

func json(_ object: Any, to url: URL) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: url)
}

let fm = FileManager.default
let args = CommandLine.arguments.dropFirst()

if let out = args.first {
    let dir = URL(fileURLWithPath: out)
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    // One sheet: a row per variant (light, dark, tinted), rounded like the home screen, then
    // the light icon unmasked to check its corners
    let tile = 220, gap = 24
    let looks: [Appearance] = [.light, .dark, .tinted, .light]
    let w = looks.count * (tile + gap) + gap, h = variants.count * (tile + gap) + gap
    let sheet = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    sheet.setFillColor(CGColor(gray: 0.5, alpha: 1))
    sheet.fill(CGRect(x: 0, y: 0, width: w, height: h))
    sheet.interpolationQuality = .high
    for (row, v) in variants.enumerated() {
        for (col, look) in looks.enumerated() {
            let rect = CGRect(x: gap + col * (tile + gap), y: h - (row + 1) * (tile + gap), width: tile, height: tile)
            sheet.saveGState()
            if col < 3 {
                sheet.addPath(CGPath(roundedRect: rect, cornerWidth: CGFloat(tile) * 0.225, cornerHeight: CGFloat(tile) * 0.225, transform: nil))
                sheet.clip()
            }
            if look == .dark {   // what iOS puts behind a dark icon
                sheet.setFillColor(CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))
                sheet.fill(rect)
            }
            sheet.draw(render(v, look), in: rect)
            sheet.restoreGState()
        }
    }
    write(sheet.makeImage()!, to: dir.appendingPathComponent("sheet.png"))

    // The primary icon at home-screen, Spotlight and Settings sizes, side by side, to check
    // what survives downscaling; plus the full-size light icon
    let sides = [180, 120, 87, 58, 40]
    let stripW = sides.reduce(gap) { $0 + $1 + gap }, stripH = sides[0] + 2 * gap
    let strip = CGContext(data: nil, width: stripW, height: stripH, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    strip.setFillColor(CGColor(gray: 0.5, alpha: 1))
    strip.fill(CGRect(x: 0, y: 0, width: stripW, height: stripH))
    var x = gap
    for side in sides {
        let rect = CGRect(x: x, y: gap, width: side, height: side)
        strip.saveGState()
        strip.addPath(CGPath(roundedRect: rect, cornerWidth: CGFloat(side) * 0.225, cornerHeight: CGFloat(side) * 0.225, transform: nil))
        strip.clip()
        strip.draw(render(variants[0], .light, side: side), in: rect)
        strip.restoreGState()
        x += side + gap
    }
    write(strip.makeImage()!, to: dir.appendingPathComponent("small-sizes.png"))
    write(render(variants[0], .light), to: dir.appendingPathComponent("amber-light.png"))
    print("Previews written to \(dir.path)")
} else {
    let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Tracey/Assets.xcassets")
    for v in variants {
        let setName = v.id.isEmpty ? "AppIcon" : "AppIcon-\(v.id)"
        let set = catalog.appendingPathComponent("\(setName).appiconset")
        try? fm.removeItem(at: set)
        try! fm.createDirectory(at: set, withIntermediateDirectories: true)
        write(render(v, .light), to: set.appendingPathComponent("Icon-light.png"))
        write(render(v, .dark), to: set.appendingPathComponent("Icon-dark.png"))
        write(render(v, .tinted), to: set.appendingPathComponent("Icon-tinted.png"))
        let entry: (String, String?) -> [String: Any] = { file, appearance in
            var e: [String: Any] = ["filename": file, "idiom": "universal", "platform": "ios", "size": "1024x1024"]
            if let appearance { e["appearances"] = [["appearance": "luminosity", "value": appearance]] }
            return e
        }
        json(["images": [entry("Icon-light.png", nil), entry("Icon-dark.png", "dark"), entry("Icon-tinted.png", "tinted")],
              "info": ["author": "xcode", "version": 1]], to: set.appendingPathComponent("Contents.json"))

        // Preview for the Settings screen (app icon sets can't be loaded as images)
        let preview = catalog.appendingPathComponent("IconPreview-\(v.id.isEmpty ? "Amber" : v.id).imageset")
        try? fm.removeItem(at: preview)
        try! fm.createDirectory(at: preview, withIntermediateDirectories: true)
        write(render(v, .light, side: 240), to: preview.appendingPathComponent("preview.png"))
        json(["images": [["filename": "preview.png", "idiom": "universal"]],
              "info": ["author": "xcode", "version": 1]], to: preview.appendingPathComponent("Contents.json"))
    }
    print("Icon sets written to \(catalog.path)")
}
