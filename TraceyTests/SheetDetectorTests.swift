import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import Tracey

struct SheetDetectorTests {

    @Test func detectorFindsSyntheticSheet() throws {
        let frame = try #require(SyntheticFrameSource.sheetFrame(size: CGSize(width: 1080, height: 1920)))
        let quad = try #require(SheetDetector.detectSync(in: frame))
        let center = SheetGeometry.sheetRect(quad).center
        // The synthetic sheet is centered in the frame
        #expect(abs(center.x - 0.5) < 0.05 && abs(center.y - 0.5) < 0.05)
        // …and covers roughly 60% × 55% of it
        let size = SheetGeometry.sheetRect(quad).size
        #expect(size.width > 0.45 && size.height > 0.4)
    }

    @Test func detectorFindsNothingOnBlank() throws {
        let frame = try #require(SyntheticFrameSource.solidFrame(size: CGSize(width: 540, height: 960), gray: 0.4))
        #expect(SheetDetector.detectSync(in: frame) == nil)
    }
}

struct RecorderFrameTapTests {

    private func frame() -> CVPixelBuffer {
        SyntheticFrameSource.solidFrame(size: CGSize(width: 64, height: 64), gray: 0.5)!
    }

    @Test func recorderHandsOutOneFrameAndKeepsRecording() {
        let recorder = TimelapseRecorder(speed: .x30)
        let lock = NSLock()
        var handed = 0
        recorder.requestNextFrame { _ in lock.lock(); handed += 1; lock.unlock() }
        for second in 0..<4 {
            recorder.queue.sync {
                recorder.consume(frame(), at: CMTime(seconds: Double(second), preferredTimescale: 600))
            }
        }
        lock.lock(); let count = handed; lock.unlock()
        #expect(count == 1)
        #expect(recorder.framesWritten == 4)
        recorder.finish { _ in }
    }
}

struct SheetAcceptanceTests {
    private typealias Quad = SheetGeometry.Quad

    @Test func fullFrameIsNotASheet() {
        let full = Quad(topLeft: CGPoint(x: 0.005, y: 0.004), topRight: CGPoint(x: 1, y: 0.004),
                        bottomRight: CGPoint(x: 1, y: 0.996), bottomLeft: CGPoint(x: 0.007, y: 0.996))
        #expect(!SheetDetector.isAcceptable(full))
    }

    @Test func aSheetInTheFrameIsAccepted() {
        let sheet = Quad(topLeft: CGPoint(x: 0.2, y: 0.22), topRight: CGPoint(x: 0.8, y: 0.25),
                         bottomRight: CGPoint(x: 0.78, y: 0.78), bottomLeft: CGPoint(x: 0.18, y: 0.75))
        #expect(SheetDetector.isAcceptable(sheet))
    }
}
