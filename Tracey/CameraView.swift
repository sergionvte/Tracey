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

/// Everything needed to draw the overlay image exactly like the SwiftUI layout used to:
/// aspect-fit inside the safe area, then flip → scale → rotate (about its center) → offset.
struct OverlayRenderState: Equatable {
    var image: UIImage?
    var opacity: Double
    var scale: CGFloat
    var rotation: Double // degrees, clockwise
    var offset: CGSize
    var isFlipped: Bool
}

struct CameraView: UIViewRepresentable {
    let viewModel: CameraViewModel
    @Binding var cameraUIView: CameraUIView?
    var isZoomEnabled: Bool
    /// When true (properties locked) drag/pinch move and zoom camera + image together.
    var isViewportEnabled: Bool
    var overlay: OverlayRenderState
    /// Rect (in this view's coordinates) the overlay image is fitted and centered in.
    var overlayLayoutRect: CGRect

    func makeUIView(context: Context) -> CameraUIView {
        let cameraView = CameraUIView()
        cameraView.isZoomEnabled = isZoomEnabled
        cameraView.onViewportTransformedChange = { [weak viewModel] transformed in
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel?.isViewportTransformed = transformed
            }
        }
        cameraView.setupCamera(mode: viewModel.captureMode)
        DispatchQueue.main.async {
            cameraUIView = cameraView
            // Weak reference so the ViewModel can drive zoom / capture mode / viewport
            viewModel.cameraUIViewRef = cameraView
        }
        return cameraView
    }

    func updateUIView(_ uiView: CameraUIView, context: Context) {
        uiView.isZoomEnabled = isZoomEnabled
        uiView.isViewportEnabled = isViewportEnabled
        uiView.overlayLayoutRect = overlayLayoutRect
        let animated = context.transaction.animation != nil && !context.transaction.disablesAnimations
        uiView.setOverlay(overlay, animated: animated)
    }
}

class CameraUIView: UIView, UIGestureRecognizerDelegate {
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var captureDevice: AVCaptureDevice?

    /// Single container for the camera preview AND the overlay image.
    /// The viewport transform is applied to this view only, so both always move together.
    private let contentView = UIView()
    private let overlayImageView = UIImageView()
    private var overlayState: OverlayRenderState?

    var overlayLayoutRect: CGRect = .zero {
        didSet {
            if overlayLayoutRect != oldValue { layoutOverlay() }
        }
    }

    // Viewport (the "move the whole screen" transform)
    private var viewportScale: CGFloat = 1.0
    private var viewportOffset: CGPoint = .zero
    // 0.25x (zoomed out, everything smaller) up to 10x (zoomed in); 1x is the normal view
    private let viewportScaleRange: ClosedRange<CGFloat> = 0.25...10.0
    private var lastReportedTransformed = false
    var onViewportTransformedChange: ((Bool) -> Void)?
    private var panGesture: UIPanGestureRecognizer?

    var isViewportEnabled: Bool = false {
        didSet {
            guard isViewportEnabled != oldValue else { return }
            panGesture?.isEnabled = isViewportEnabled
            if !isViewportEnabled {
                // Unlocking returns to the normal view so the image can be edited
                resetViewport(animated: true)
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .black
        clipsToBounds = true
        contentView.isUserInteractionEnabled = false // all gestures are handled by self
        addSubview(contentView)
        overlayImageView.contentMode = .scaleToFill
        overlayImageView.isHidden = true
        contentView.addSubview(overlayImageView)
    }

    /// All session/device configuration runs serially here, off the main thread.
    private let sessionQueue = DispatchQueue(label: "tracey.camera.session")

    var isZoomEnabled: Bool = true

    private(set) var captureMode: CameraCaptureMode = .video

    func setupCamera(mode: CameraCaptureMode) {
        captureMode = mode

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = Self.videoGravity(for: mode)
        contentView.layer.insertSublayer(previewLayer, at: 0) // below the overlay image

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
        CATransaction.begin()
        CATransaction.setDisableActions(true) // no implicit animations → no lag behind the image
        // contentView may carry a transform, so size it via bounds/center (never frame)
        contentView.bounds = bounds
        contentView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        previewLayer?.frame = contentView.bounds
        CATransaction.commit()
        layoutOverlay()
        clampViewport()
        applyViewportTransform()
    }

    // MARK: - Overlay image

    func setOverlay(_ state: OverlayRenderState, animated: Bool) {
        guard state != overlayState else { return }
        overlayState = state
        if animated && !overlayImageView.isHidden && state.image != nil {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]) {
                self.layoutOverlay()
            }
        } else {
            layoutOverlay()
        }
    }

    private func layoutOverlay() {
        guard let state = overlayState, let image = state.image,
              overlayLayoutRect.width > 0, overlayLayoutRect.height > 0,
              image.size.width > 0, image.size.height > 0 else {
            overlayImageView.isHidden = true
            overlayImageView.image = nil
            return
        }

        if overlayImageView.image !== image {
            overlayImageView.image = image
        }
        overlayImageView.isHidden = false

        // Aspect-fit inside the layout rect (same as SwiftUI .aspectRatio(contentMode: .fit))
        let fit = min(overlayLayoutRect.width / image.size.width, overlayLayoutRect.height / image.size.height)
        overlayImageView.bounds = CGRect(x: 0, y: 0, width: image.size.width * fit, height: image.size.height * fit)
        overlayImageView.center = CGPoint(
            x: overlayLayoutRect.midX + state.offset.width,
            y: overlayLayoutRect.midY + state.offset.height
        )
        // flip → scale → rotate, all about the image center
        let flipScaleX = (state.isFlipped ? -1 : 1) * state.scale
        overlayImageView.transform = CGAffineTransform(scaleX: flipScaleX, y: state.scale)
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(state.rotation) * .pi / 180))
        overlayImageView.alpha = CGFloat(state.opacity)
    }

    // MARK: - Viewport (move / zoom the whole screen while locked)

    private func applyViewportTransform() {
        // Scale about the screen center, then translate
        contentView.transform = CGAffineTransform(scaleX: viewportScale, y: viewportScale)
            .concatenating(CGAffineTransform(translationX: viewportOffset.x, y: viewportOffset.y))
    }

    private func clampViewport() {
        viewportScale = min(max(viewportScale, viewportScaleRange.lowerBound), viewportScaleRange.upperBound)
        // Never let the canvas leave the screen completely. When zoomed out (scale < 1) the
        // smaller canvas can still be moved until its center reaches any screen edge.
        let maxX = bounds.width * max(viewportScale, 1) / 2
        let maxY = bounds.height * max(viewportScale, 1) / 2
        viewportOffset.x = min(max(viewportOffset.x, -maxX), maxX)
        viewportOffset.y = min(max(viewportOffset.y, -maxY), maxY)
    }

    private func reportViewportState() {
        let transformed = abs(viewportScale - 1) > 0.001 || abs(viewportOffset.x) > 0.5 || abs(viewportOffset.y) > 0.5
        guard transformed != lastReportedTransformed else { return }
        lastReportedTransformed = transformed
        onViewportTransformedChange?(transformed)
    }

    func resetViewport(animated: Bool) {
        viewportScale = 1.0
        viewportOffset = .zero
        if animated {
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.applyViewportTransform()
            }
        } else {
            applyViewportTransform()
        }
        reportViewportState()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isViewportEnabled else { return }
        let translation = gesture.translation(in: self)
        viewportOffset.x += translation.x
        viewportOffset.y += translation.y
        gesture.setTranslation(.zero, in: self)
        clampViewport()
        applyViewportTransform()
        reportViewportState()
    }

    private func handleViewportPinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        let newScale = min(max(viewportScale * gesture.scale, viewportScaleRange.lowerBound), viewportScaleRange.upperBound)
        let ratio = newScale / viewportScale
        // Keep the point between the fingers fixed while zooming
        let location = gesture.location(in: self)
        let fromCenter = CGPoint(x: location.x - bounds.midX, y: location.y - bounds.midY)
        viewportOffset.x = fromCenter.x * (1 - ratio) + viewportOffset.x * ratio
        viewportOffset.y = fromCenter.y * (1 - ratio) + viewportOffset.y * ratio
        viewportScale = newScale
        gesture.scale = 1.0
        clampViewport()
        applyViewportTransform()
        reportViewportState()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Pan + pinch together: two fingers can move and zoom at the same time
        true
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
        pinchGesture.delegate = self
        addGestureRecognizer(pinchGesture)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.isEnabled = isViewportEnabled
        addGestureRecognizer(pan)
        panGesture = pan

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapToFocus(_:)))
        tapGesture.numberOfTapsRequired = 1
        addGestureRecognizer(tapGesture)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if isViewportEnabled {
            handleViewportPinch(gesture)
            return
        }
        // Unlocked: pinch changes the real camera zoom
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

    /// Focuses/exposes at a point on screen (this view's coordinates), accounting for the viewport.
    func focus(at touchPoint: CGPoint) {
        guard let device = captureDevice, let previewLayer else { return }

        // Undo the viewport move/zoom to find which part of the camera image was touched
        let layerPoint = contentView.convert(touchPoint, from: self)
        let focusPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)

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
