//
//  TimelapseRecorder.swift
//  Tracey
//
//  Writes a time-lapse of the raw camera feed (paper and drawing, no reference overlay): one
//  frame every 2 s of active recording, played back at 30 fps (60× speed).
//

import AVFoundation
import VideoToolbox

final class TimelapseRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Seconds of drawing between kept frames
    static let captureInterval: Double = 2.0
    static let playbackFPS: Int32 = 30
    /// 3 hours of recording → a 3:00 clip
    static let maxFrames = 5_400
    /// Fewer frames than this (under 20 s of drawing) isn't worth saving
    static let minFrames = 10
    /// Long side of the output, at most
    static let maxLongSide = 1920
    static let filePrefix = "timelapse-"

    enum Outcome {
        case finished(URL)
        case tooShort
        case failed(URL?)
    }

    /// Frames are delivered and written on this serial queue
    let queue = DispatchQueue(label: "tracey.timelapse.writer", qos: .utility)
    let url: URL

    /// Called on the main queue when the 3-hour limit is reached
    var onFrameLimitReached: (() -> Void)?

    private let lock = NSLock()
    private var _framesWritten = 0
    private var _isPaused = false

    // Queue-only state
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var transferSession: VTPixelTransferSession?
    private var outputWidth = 0
    private var outputHeight = 0
    private var lastKeptTime: CMTime?
    private var frameIndex: Int64 = 0
    private var isStopped = false
    private var didFail = false

    /// Temporary clips live here (cleared on launch)
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Timelapses", isDirectory: true)
    }

    private let startDate = Date()

    override init() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        url = Self.directory.appendingPathComponent("\(Self.filePrefix)\(UUID().uuidString).mov")
        super.init()
    }

    /// "Tracey time-lapse 2026-11-22 17.15.mov": the name people see when sharing
    private func friendlyURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let base = "Tracey time-lapse \(formatter.string(from: startDate))"
        var candidate = Self.directory.appendingPathComponent("\(base).mov")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = Self.directory.appendingPathComponent("\(base) (\(index)).mov")
            index += 1
        }
        return candidate
    }

    /// Frames written so far (any thread)
    var framesWritten: Int {
        lock.lock(); defer { lock.unlock() }
        return _framesWritten
    }

    /// While paused, incoming frames are dropped (any thread)
    var isPaused: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isPaused }
        set { lock.lock(); _isPaused = newValue; lock.unlock() }
    }

    // MARK: - Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        consume(pixelBuffer, at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    /// Must be called on `queue`. Keeps a frame only when it is at least 2 s after the last kept
    /// one and recording isn't paused; each kept frame is the next 1/30 s of the clip, so pauses
    /// leave no gap.
    func consume(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard !isStopped, !didFail, !isPaused else { return }
        if let last = lastKeptTime, CMTimeGetSeconds(CMTimeSubtract(time, last)) < Self.captureInterval {
            return
        }
        if writer == nil, !startWriter(sizedFrom: pixelBuffer) {
            didFail = true
            return
        }
        guard let input, let adaptor, input.isReadyForMoreMediaData,
              let frame = outputBuffer(from: pixelBuffer) else { return }

        if adaptor.append(frame, withPresentationTime: CMTime(value: frameIndex, timescale: Self.playbackFPS)) {
            lastKeptTime = time
            frameIndex += 1
            lock.lock(); _framesWritten = Int(frameIndex); lock.unlock()
            if frameIndex >= Self.maxFrames {
                isStopped = true
                DispatchQueue.main.async { [weak self] in self?.onFrameLimitReached?() }
            }
        } else {
            print("Time-lapse append failed: \(String(describing: writer?.error))")
            didFail = true
        }
    }

    /// Output size comes from the first buffer: its long side is capped at 1920 px.
    private func startWriter(sizedFrom pixelBuffer: CVPixelBuffer) -> Bool {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return false }
        let scale = min(1, Double(Self.maxLongSide) / Double(max(width, height)))
        // Encoders want even dimensions
        outputWidth = Int((Double(width) * scale / 2).rounded()) * 2
        outputHeight = Int((Double(height) * scale / 2).rounded()) * 2

        do {
            try? FileManager.default.removeItem(at: url)
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            var settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: outputWidth,
                AVVideoHeightKey: outputHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000,
                    AVVideoExpectedSourceFrameRateKey: Int(Self.playbackFPS)
                ]
            ]
            // Every supported device encodes HEVC; fall back to H.264 just in case
            if !writer.canApply(outputSettings: settings, forMediaType: .video) {
                settings[AVVideoCodecKey] = AVVideoCodecType.h264
            }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                    kCVPixelBufferWidthKey as String: outputWidth,
                    kCVPixelBufferHeightKey as String: outputHeight,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
                ]
            )
            guard writer.canAdd(input) else { return false }
            writer.add(input)
            guard writer.startWriting() else {
                print("Time-lapse writer failed to start: \(String(describing: writer.error))")
                return false
            }
            writer.startSession(atSourceTime: .zero)
            self.writer = writer
            self.input = input
            self.adaptor = adaptor
            return true
        } catch {
            print("Time-lapse writer error: \(error)")
            return false
        }
    }

    /// The camera buffer as-is when it already matches, otherwise scaled/converted into a buffer
    /// from the writer's pool.
    private func outputBuffer(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let isYUV = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        if isYUV, CVPixelBufferGetWidth(pixelBuffer) == outputWidth, CVPixelBufferGetHeight(pixelBuffer) == outputHeight {
            return pixelBuffer
        }
        guard let pool = adaptor?.pixelBufferPool else { return nil }
        var destination: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination) == kCVReturnSuccess,
              let destination else { return nil }
        if transferSession == nil {
            var session: VTPixelTransferSession?
            VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &session)
            transferSession = session
        }
        guard let transferSession,
              VTPixelTransferSessionTransferImage(transferSession, from: pixelBuffer, to: destination) == noErr else {
            return nil
        }
        return destination
    }

    // MARK: - Finishing

    /// Stops taking frames and finishes the file. `completion` runs on the main queue.
    func finish(completion: @escaping (Outcome) -> Void) {
        queue.async { [self] in
            isStopped = true
            let frames = Int(frameIndex)
            let failed = didFail
            let fileURL = url
            guard let writer, let input else {
                DispatchQueue.main.async { completion(failed ? .failed(nil) : .tooShort) }
                return
            }
            if frames < Self.minFrames {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: fileURL)
                DispatchQueue.main.async { completion(.tooShort) }
                return
            }
            input.markAsFinished()
            let transferSession = transferSession
            let namedURL = friendlyURL()
            writer.finishWriting {
                let ok = writer.status == .completed
                if !ok { print("Time-lapse finish failed: \(String(describing: writer.error))") }
                if let transferSession { VTPixelTransferSessionInvalidate(transferSession) }
                // Give the file a readable name for the share sheet
                var finalURL = fileURL
                if (try? FileManager.default.moveItem(at: fileURL, to: namedURL)) != nil { finalURL = namedURL }
                let keptURL = FileManager.default.fileExists(atPath: finalURL.path) ? finalURL : nil
                DispatchQueue.main.async {
                    completion(ok ? .finished(finalURL) : .failed(keptURL))
                }
            }
        }
    }

    /// Removes leftovers from earlier runs (killed while recording, a clip never shared).
    static func removeStaleFiles() {
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: directory)
            // Older builds wrote straight into tmp
            let tmp = FileManager.default.temporaryDirectory
            let files = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent.hasPrefix(filePrefix) && file.pathExtension == "mov" {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
