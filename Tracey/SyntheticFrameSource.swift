//
//  SyntheticFrameSource.swift
//  Tracey
//
//  DEBUG ONLY. The Simulator has no camera, so the time-lapse would never get a frame. When
//  there is no capture device, this feeds the recorder a solid-color frame with a counter at the
//  recorder's capture interval, so the pill / stop / save / share flow can be tested. Compiled out of Release builds.
//

#if DEBUG
import CoreVideo
import CoreMedia
import UIKit

final class SyntheticFrameSource {
    private weak var recorder: TimelapseRecorder?
    private let size: CGSize
    private var timer: DispatchSourceTimer?
    private var count = 0

    /// `size` in pixels (portrait), e.g. 1080 × 1920 for Video mode
    init(recorder: TimelapseRecorder, size: CGSize) {
        self.recorder = recorder
        self.size = size
    }

    func start() {
        guard let recorder, timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: recorder.queue)
        timer.schedule(deadline: .now() + 0.2, repeating: recorder.captureInterval)
        timer.setEventHandler { [weak self] in self?.emitFrame() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Runs on the recorder's queue
    private func emitFrame() {
        guard let recorder, let buffer = makeFrame(number: count) else { return }
        // Exactly one interval apart, so every frame passes the recorder's spacing check
        let time = CMTime(seconds: Double(count) * recorder.captureInterval, preferredTimescale: 600)
        count += 1
        recorder.consume(buffer, at: time)
    }

    private func makeFrame(number: Int) -> CVPixelBuffer? {
        let width = Int(size.width), height = Int(size.height)
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // A different hue every frame so playback visibly moves
        let hue = CGFloat(number % 12) / 12
        context.setFillColor(UIColor(hue: hue, saturation: 0.55, brightness: 0.9, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Frame counter, drawn upright (UIKit coordinates)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        let text = "SIMULATED FRAME\n\(number + 1)" as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = UIFont.monospacedDigitSystemFont(ofSize: CGFloat(width) / 9, weight: .bold)
        text.draw(in: CGRect(x: 0, y: CGFloat(height) * 0.38, width: CGFloat(width), height: CGFloat(height) * 0.3),
                  withAttributes: [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
        UIGraphicsPopContext()
        return buffer
    }

    // MARK: - Still frames (fit to sheet in the Simulator, and tests)

    /// A BGRA buffer of `size` drawn by `draw` in UIKit coordinates (origin top-left).
    static func makeFrame(size: CGSize, draw: (CGContext, CGSize) -> Void) -> CVPixelBuffer? {
        let width = Int(size.width), height = Int(size.height)
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        draw(context, size)
        return buffer
    }

    /// One flat gray frame (nothing to detect)
    static func solidFrame(size: CGSize, gray: CGFloat) -> CVPixelBuffer? {
        makeFrame(size: size) { context, size in
            context.setFillColor(UIColor(white: gray, alpha: 1).cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// A white sheet (60% × 55% of the frame, centered, turned 6°) on a dark desk
    static func sheetFrame(size: CGSize) -> CVPixelBuffer? {
        makeFrame(size: size) { context, size in
            context.setFillColor(UIColor(white: 0.18, alpha: 1).cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            context.saveGState()
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: 6 * .pi / 180)
            let sheet = CGSize(width: size.width * 0.6, height: size.height * 0.55)
            context.setFillColor(UIColor(white: 0.96, alpha: 1).cgColor)
            context.fill(CGRect(x: -sheet.width / 2, y: -sheet.height / 2, width: sheet.width, height: sheet.height))
            context.restoreGState()
        }
    }
}
#endif