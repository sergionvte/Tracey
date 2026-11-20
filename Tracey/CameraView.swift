//
//  CameraView.swift
//  DrawingReference
//
//  Created by Sergio Navarrete on 31/05/25.
//

// CameraView.swift - Camera preview with zoom, focus and video/photo capture modes
import SwiftUI
import AVFoundation

/// How the camera feed is captured and shown.
/// - video: 16:9 video format (up to 60 fps), fills the screen → smoother preview.
/// - photo: full 4:3 sensor frame, shown completely (letterboxed) → more content visible.
enum CameraCaptureMode: String, Codable, CaseIterable {
    case video
    case photo

    var iconName: String {
        switch self {
        case .video: return "video.fill"
        case .photo: return "camera.fill"
        }
    }

    var title: String {
        switch self {
        case .video: return "Video mode · smoother"
        case .photo: return "Photo mode · wider frame"
        }
    }

    var toggled: CameraCaptureMode {
        self == .video ? .photo : .video
    }
}

struct CameraView: UIViewRepresentable {
    let viewModel: CameraViewModel
    @Binding var cameraUIView: CameraUIView?
    var isZoomEnabled: Bool

    func makeUIView(context: Context) -> CameraUIView {
        let cameraView = CameraUIView()
        cameraView.isZoomEnabled = isZoomEnabled
        cameraView.setupCamera(mode: viewModel.captureMode)
        DispatchQueue.main.async {
            cameraUIView = cameraView
            // Weak reference so the ViewModel can drive zoom / capture mode
            viewModel.cameraUIViewRef = cameraView
        }
        return cameraView
    }

    func updateUIView(_ uiView: CameraUIView, context: Context) {
        uiView.isZoomEnabled = isZoomEnabled
    }
}

class CameraUIView: UIView {
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var captureDevice: AVCaptureDevice?

    /// All session/device configuration runs serially here, off the main thread.
    private let sessionQueue = DispatchQueue(label: "tracey.camera.session")

    var isZoomEnabled: Bool = true

    private(set) var captureMode: CameraCaptureMode = .video

    func setupCamera(mode: CameraCaptureMode) {
        captureMode = mode

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = Self.videoGravity(for: mode)
        layer.addSublayer(previewLayer)

        setupGestures()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("No camera available")
                return
            }
            self.captureDevice = device

            self.captureSession.beginConfiguration()
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                }
            } catch {
                print("Error setting up camera input: \(error)")
                self.captureSession.commitConfiguration()
                return
            }
            self.applyFormat(for: mode, on: device)
            self.captureSession.commitConfiguration()

            self.captureSession.startRunning()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    // MARK: - Capture mode

    /// Switches between the smooth video preview and the full-frame photo preview.
    /// Camera zoom and torch state are preserved.
    func setCaptureMode(_ mode: CameraCaptureMode) {
        guard mode != captureMode else { return }
        captureMode = mode

        sessionQueue.async { [weak self] in
            guard let self, let device = self.captureDevice else { return }
            let previousZoom = device.videoZoomFactor
            let torchWasOn = device.torchMode == .on

            self.captureSession.beginConfiguration()
            self.applyFormat(for: mode, on: device)
            self.captureSession.commitConfiguration()

            // Restore zoom (format change may reset it) and torch
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = Self.clampedZoom(previousZoom, for: device)
                if torchWasOn && device.hasTorch && device.isTorchModeSupported(.on) {
                    try? device.setTorchModeOn(level: 1.0)
                }
                device.unlockForConfiguration()
            } catch {
                print("Error restoring camera state: \(error)")
            }

            DispatchQueue.main.async {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.previewLayer.videoGravity = Self.videoGravity(for: mode)
                CATransaction.commit()
            }
        }
    }

    /// Must be called on `sessionQueue` between begin/commitConfiguration.
    private func applyFormat(for mode: CameraCaptureMode, on device: AVCaptureDevice) {
        switch mode {
        case .photo:
            // Full 4:3 sensor frame
            if captureSession.canSetSessionPreset(.photo) {
                captureSession.sessionPreset = .photo
            }
        case .video:
            if captureSession.canSetSessionPreset(.high) {
                captureSession.sessionPreset = .high
            }
            // Try to upgrade to 1080p @ 60 fps for a smoother preview
            if let format = Self.bestVideoFormat(for: device) {
                do {
                    try device.lockForConfiguration()
                    device.activeFormat = format
                    // Up to 60 fps; the device may drop to 30 fps in low light
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                    device.unlockForConfiguration()
                } catch {
                    print("Error configuring 60 fps format: \(error)")
                }
            }
        }
    }

    private static func bestVideoFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let candidates = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let supports60 = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 60 && $0.minFrameRate <= 30 }
            return dims.width == 1920 && dims.height == 1080 && supports60
        }
        // Prefer full-range 420f
        return candidates.first {
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        } ?? candidates.first
    }

    private static func videoGravity(for mode: CameraCaptureMode) -> AVLayerVideoGravity {
        // Photo mode shows the whole frame so nothing is cropped away
        mode == .photo ? .resizeAspect : .resizeAspectFill
    }

    private static func clampedZoom(_ zoom: CGFloat, for device: AVCaptureDevice) -> CGFloat {
        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
        return max(1.0, min(zoom, maxZoom))
    }

    // MARK: - Gestures

    private func setupGestures() {
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinchGesture)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapToFocus(_:)))
        tapGesture.numberOfTapsRequired = 1
        addGestureRecognizer(tapGesture)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard isZoomEnabled else { gesture.scale = 1.0; return }
        guard let device = captureDevice else { return }

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = Self.clampedZoom(device.videoZoomFactor * gesture.scale, for: device)
            device.unlockForConfiguration()
            gesture.scale = 1.0
        } catch {
            print("Error adjusting zoom: \(error)")
        }
    }

    @objc private func handleTapToFocus(_ gesture: UITapGestureRecognizer) {
        focus(at: gesture.location(in: self))
    }

    func focusAtCenter() {
        focus(at: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    /// Focuses/exposes at a point expressed in this view's own (untransformed) coordinates.
    func focus(at touchPoint: CGPoint) {
        guard let device = captureDevice, let previewLayer else { return }

        let focusPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: touchPoint)

        do {
            try device.lockForConfiguration()

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = focusPoint
                device.focusMode = .autoFocus
            }

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .autoExpose
            }

            device.unlockForConfiguration()
            showFocusIndicator(at: touchPoint)
        } catch {
            print("Error setting focus: \(error)")
        }
    }

    private func showFocusIndicator(at point: CGPoint) {
        let focusView = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        focusView.center = point
        focusView.backgroundColor = UIColor.clear
        focusView.layer.borderColor = UIColor.yellow.cgColor
        focusView.layer.borderWidth = 2
        focusView.layer.cornerRadius = 40
        focusView.alpha = 0

        addSubview(focusView)

        UIView.animate(withDuration: 0.2, animations: {
            focusView.alpha = 1
            focusView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0.5, animations: {
                focusView.alpha = 0
            }) { _ in
                focusView.removeFromSuperview()
            }
        }
    }

    // MARK: - Zoom

    func setZoomFactor(_ zoom: CGFloat) {
        // Serialized with capture-mode changes so a restored zoom isn't overwritten
        sessionQueue.async { [weak self] in
            guard let device = self?.captureDevice else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = Self.clampedZoom(zoom, for: device)
                device.unlockForConfiguration()
            } catch {
                print("Error setting zoom: \(error)")
            }
        }
    }

    func getCurrentZoomFactor() -> CGFloat {
        captureDevice?.videoZoomFactor ?? 1.0
    }
}
