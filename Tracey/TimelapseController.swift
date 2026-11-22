//
//  TimelapseController.swift
//  Tracey
//
//  Recording state for the time-lapse: start/stop, pause while the app is in the background or
//  the camera is interrupted, automatic stops, and saving the clip to Photos. Main thread only.
//

import Foundation
import Photos
import UIKit

final class TimelapseController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case saving
    }

    enum StopReason {
        case user
        case timeLimit
        case lowStorage
        case thermal
    }

    enum Outcome {
        /// In Photos; the temporary file is kept for Share until the caller deletes it
        case saved(URL)
        case tooShort
        /// Writer or Photos error; the file (if any) can still be shared
        case failed(URL?)
    }

    @Published private(set) var phase: Phase = .idle
    /// Background or camera interruption: frames are dropped and the clock stops
    @Published private(set) var isPaused = false

    /// Recording stopped by itself (3 h limit, low storage, too warm); the owner stops and saves
    var onAutoStop: ((StopReason) -> Void)?
    /// Recording resumed after a pause
    var onResumed: (() -> Void)?

    private var recorder: TimelapseRecorder?
    private weak var cameraView: CameraUIView?
    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private var isBackgrounded = false
    private var isInterrupted = false
    private var storageTimer: Timer?
    private var thermalObserver: NSObjectProtocol?

    static let minimumFreeSpaceToStart: Int64 = 1_000_000_000
    static let minimumFreeSpaceWhileRecording: Int64 = 300_000_000

    init() {
        TimelapseRecorder.removeStaleFiles()
    }

    var isActive: Bool { phase != .idle }

    /// Accumulated active recording time
    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (segmentStart.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// Length of the clip so far, in seconds of playback
    var clipSeconds: Int {
        (recorder?.framesWritten ?? 0) / Int(TimelapseRecorder.playbackFPS)
    }

    static func availableSpace() -> Int64? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    // MARK: - Start / stop

    func start(cameraView: CameraUIView, interfaceOrientation: UIInterfaceOrientation) {
        guard phase == .idle else { return }
        let recorder = TimelapseRecorder()
        recorder.onFrameLimitReached = { [weak self] in self?.autoStop(.timeLimit) }
        recorder.isPaused = isBackgrounded || isInterrupted
        self.recorder = recorder
        self.cameraView = cameraView
        accumulated = 0
        isPaused = recorder.isPaused
        segmentStart = isPaused ? nil : Date()
        phase = .recording

        // The clip keeps the orientation it started in (iPhone is always portrait)
        let angle: CGFloat
        switch interfaceOrientation {
        case .landscapeLeft: angle = 180
        case .landscapeRight: angle = 0
        case .portraitUpsideDown: angle = 270
        default: angle = 90
        }
        cameraView.startFrameDelivery(to: recorder, rotationAngle: angle)

        storageTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            if let free = Self.availableSpace(), free < Self.minimumFreeSpaceWhileRecording {
                self?.autoStop(.lowStorage)
            }
        }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            if ProcessInfo.processInfo.thermalState == .critical { self?.autoStop(.thermal) }
        }
    }

    private func autoStop(_ reason: StopReason) {
        guard phase == .recording else { return }
        onAutoStop?(reason)
    }

    /// Finishes the clip and saves it to Photos. `completion` runs on the main queue.
    func stop(completion: @escaping (Outcome) -> Void) {
        guard phase == .recording, let recorder else { return }
        phase = .saving
        if let segmentStart { accumulated += Date().timeIntervalSince(segmentStart) }
        segmentStart = nil
        storageTimer?.invalidate()
        storageTimer = nil
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
        thermalObserver = nil

        let finish = { [weak self] in
            recorder.finish { outcome in
                switch outcome {
                case .tooShort:
                    self?.reset()
                    completion(.tooShort)
                case .failed(let url):
                    self?.reset()
                    completion(.failed(url))
                case .finished(let url):
                    Self.saveToPhotos(url) { success in
                        self?.reset()
                        completion(success ? .saved(url) : .failed(url))
                    }
                }
            }
        }
        if let cameraView {
            cameraView.stopFrameDelivery(completion: finish)
        } else {
            finish()
        }
    }

    private func reset() {
        recorder = nil
        accumulated = 0
        segmentStart = nil
        isPaused = false
        phase = .idle
    }

    private static func saveToPhotos(_ url: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
        }) { success, error in
            if let error { print("Saving time-lapse to Photos failed: \(error)") }
            DispatchQueue.main.async { completion(success) }
        }
    }

    // MARK: - Pause / resume

    func setBackgrounded(_ backgrounded: Bool) {
        isBackgrounded = backgrounded
        updatePause()
    }

    func setInterrupted(_ interrupted: Bool) {
        isInterrupted = interrupted
        updatePause()
    }

    private func updatePause() {
        let paused = isBackgrounded || isInterrupted
        guard phase == .recording, paused != isPaused else { return }
        recorder?.isPaused = paused
        if paused {
            if let segmentStart { accumulated += Date().timeIntervalSince(segmentStart) }
            segmentStart = nil
        } else {
            segmentStart = Date()
            onResumed?()
        }
        isPaused = paused
    }
}
