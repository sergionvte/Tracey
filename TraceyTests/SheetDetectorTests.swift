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
