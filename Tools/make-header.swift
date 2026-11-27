// Draws the App Store product page header for Tracey: the icon's wave stretched into a
// panorama on the app's dark warm backdrop. Left of center the line is traced (solid, glowing
// amber); right of center it is still the dashed guide. The hand-off sits in the middle, the
// part every crop of the header keeps. No text: App Store draws the app's name over it.
//
//   swift Tools/make-header.swift [out-dir]   (default AppStore/Header)
//
// Writes both sizes App Store Connect accepts: 5244×2950 and 3840×1646.

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

// Same palette as Tools/make-icons.swift
let top = RGB(0x2A2016), bottom = RGB(0x0E0B08), amber = RGB(0xFFB84D)

func draw(width: Int, height: Int) -> CGImage {
    let W = CGFloat(width), H = CGFloat(height)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Top-left origin, y down
    ctx.translateBy(x: 0, y: H)
    ctx.scaleBy(x: 1, y: -1)

    // Everything scales with the shorter side, so both sizes read the same in the middle
    let unit = min(W, H * 16 / 9) / 16    // one sixteenth of the 16:9 frame's width
    let cx = W / 2, cy = H / 2

    // Backdrop
    let base = CGGradient(colorsSpace: space, colors: [top.cg(), bottom.cg()] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: cx, y: 0), end: CGPoint(x: cx, y: H),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Faint graph paper: the sheet you trace on
    let cell = unit * 0.9
    ctx.setStrokeColor(amber.cg(0.045))
    ctx.setLineWidth(max(2, unit * 0.02))
    var x = cx.truncatingRemainder(dividingBy: cell)
    while x < W { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: H)); x += cell }
    var y = cy.truncatingRemainder(dividingBy: cell)
    while y < H { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: W, y: y)); y += cell }
    ctx.strokePath()

    // The soft glow behind the line, strongest where tracing happens
    let halo = CGGradient(colorsSpace: space, colors: [amber.cg(0.16), amber.cg(0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(halo, startCenter: CGPoint(x: cx - unit * 1.5, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx - unit * 1.5, y: cy), endRadius: unit * 7, options: [])

    // The wave: crest just left of center, trough just right, like the icon
    let amplitude = unit * 1.15, wavelength = unit * 6.4, stroke = unit * 0.42
    func wavePoint(_ x: CGFloat) -> CGPoint {
        CGPoint(x: x, y: cy + amplitude * sin(2 * .pi * (x - cx) / wavelength))
    }
    func wave(from a: CGFloat, to b: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let steps = Int(abs(b - a) / 4)
        path.move(to: wavePoint(a))
        for i in 1...steps { path.addLine(to: wavePoint(a + (b - a) * CGFloat(i) / CGFloat(steps))) }
        return path
    }

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(stroke)

    // Still to trace: round dots evenly spaced along the curve (by arc length), from a gap after
    // the hand-off to past the right edge. Placed by hand: a dashed stroke over a many-segment
    // path doubles some dots at the segment joins.
    let spacing = stroke * 1.5
    ctx.setFillColor(amber.cg(0.6))
    var previous = wavePoint(cx), travelled: CGFloat = 0, nextDot = spacing
    var px = cx
    while px < W + stroke {
        px += 1
        let p = wavePoint(px)
        travelled += hypot(p.x - previous.x, p.y - previous.y)
        previous = p
        if travelled >= nextDot {
            ctx.fillEllipse(in: CGRect(x: p.x - stroke / 2, y: p.y - stroke / 2, width: stroke, height: stroke))
            nextDot += spacing
        }
    }

    // Traced: from past the left edge to the hand-off, glowing
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: unit * 0.55, color: amber.cg(0.6))
    ctx.addPath(wave(from: -stroke * 2, to: cx))
    ctx.setStrokeColor(amber.cg())
    ctx.strokePath()
    ctx.restoreGState()

    // Darken the edges and the bottom, where App Store lays out the name and buttons
    let vignette = CGGradient(colorsSpace: space, colors: [bottom.cg(0), bottom.cg(0.55)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(vignette, startCenter: CGPoint(x: cx, y: cy), startRadius: unit * 4,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: hypot(W, H) / 2 + unit, options: [.drawsAfterEndLocation])
    let floor = CGGradient(colorsSpace: space, colors: [bottom.cg(0), bottom.cg(0.7)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(floor, start: CGPoint(x: cx, y: H * 0.72), end: CGPoint(x: cx, y: H), options: [.drawsAfterEndLocation])

    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "Couldn't write \(url.path)")
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppStore/Header")
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (w, h) in [(5244, 2950), (3840, 1646)] {
    let url = out.appendingPathComponent("Tracey-header-\(w)x\(h).png")
    write(draw(width: w, height: h), to: url)
    print(url.path)
}
