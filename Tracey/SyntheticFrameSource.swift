//
//  SyntheticFrameSource.swift
//  Tracey
//
//  DEBUG ONLY. The Simulator has no camera, so the time-lapse would never get a frame. When
//  there is no capture device, this feeds the recorder a solid-color frame with a counter every
//  2 s, so the pill / stop / save / share flow can be tested. Compiled out of Release builds.
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
        timer.schedule(deadline: .now() + 0.2, repeating: TimelapseRecorder.captureInterval)
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
        // Exactly 2 s apart, so every frame passes the recorder's 2 s spacing check
        let time = CMTime(seconds: Double(count) * TimelapseRecorder.captureInterval, preferredTimescale: 600)
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
}
#endif
