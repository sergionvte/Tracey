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
        case .video: return String(localized: "Video mode · smoother")
        case .photo: return String(localized: "Photo mode · wider frame")
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
    /// Grid over the image: 0 = off, otherwise divisions per side (3 or 4)
    var gridDivisions: Int = 0
}

/// Live result of the user moving / pinching / rotating the reference image.
struct OverlayEdit {
    enum Phase { case changed, ended }
    var offset: CGSize
    var scale: CGFloat
    var rotation: Double
    var isDragging: Bool
    var phase: Phase
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
    /// The camera only runs while this is true (there is a reference image on screen).
    var isCameraActive: Bool
    /// Screen areas (global coordinates) where taps and long presses must be ignored, e.g. a toast
    /// with an Undo button.
    var tapExclusionRects: [CGRect] = []
    /// The camera session was interrupted (true) or resumed (false)
    var onSessionInterruption: (Bool) -> Void = { _ in }
    /// A single tap anywhere on the camera view (shows / hides the floating controls).
    var onSingleTap: () -> Void

    func makeUIView(context: Context) -> CameraUIView {
        let cameraView = CameraUIView()
        cameraView.isZoomEnabled = isZoomEnabled
        cameraView.onSingleTap = onSingleTap
        cameraView.onSessionInterruptionChanged = onSessionInterruption
        cameraView.onCameraAccessDenied = { [weak viewModel] denied in
            guard let viewModel else { return }
            if viewModel.isCameraAuthorized == denied { viewModel.isCameraAuthorized = !denied }
            guard viewModel.isCameraAccessDenied != denied else { return }
            withAnimation(Theme.spring) { viewModel.isCameraAccessDenied = denied }
        }
        cameraView.onViewportTransformedChange = { [weak viewModel] transformed in
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel?.isViewportTransformed = transformed
            }
        }
        cameraView.onOverlayEdit = { [weak viewModel] edit in
            guard let viewModel else { return }
            if edit.phase == .ended {
                // Final values (may include the snap to center) settle with a short animation
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.imageOffset = edit.offset
                    viewModel.imageScale = edit.scale
                    viewModel.imageRotation = edit.rotation
                }
            } else {
                viewModel.imageOffset = edit.offset
                viewModel.imageScale = edit.scale
                viewModel.imageRotation = edit.rotation
            }
            if viewModel.isDraggingImage != edit.isDragging {
                viewModel.isDraggingImage = edit.isDragging
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
        uiView.onSingleTap = onSingleTap
        uiView.onSessionInterruptionChanged = onSessionInterruption
        uiView.tapExclusionRects = tapExclusionRects
        uiView.isViewportEnabled = isViewportEnabled
        uiView.overlayLayoutRect = overlayLayoutRect
        uiView.setCameraActive(isCameraActive)
        let animated = context.transaction.animation != nil && !context.transaction.disablesAnimations
        uiView.setOverlay(overlay, animated: animated)
    }
}

class CameraUIView: UIView, UIGestureRecognizerDelegate {
    private let captureSession = AVCaptureSession()
    /// Raw camera frames for the time-lapse. Added once; it only gets a delegate while recording,
    /// so it costs nothing the rest of the time.
    private let videoDataOutput = AVCaptureVideoDataOutput()
    #if DEBUG
    /// Simulator stand-in for camera frames (no capture device)
    private var syntheticFrames: SyntheticFrameSource?
    #endif
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var captureDevice: AVCaptureDevice?

    /// Single container for the camera preview AND the overlay image.
    /// The viewport transform is applied to this view only, so both always move together.
    private let contentView = UIView()
    private let overlayImageView = UIImageView()
    private var overlayState: OverlayRenderState?
    /// Grid attached to the image: same geometry as the image view, but a sibling (not a
    /// subview) so it doesn't inherit the image's opacity.
    private let gridView = UIView()
    private let gridHaloLayer = CAShapeLayer()
    private let gridLineLayer = CAShapeLayer()
    private var gridPathKey: (size: CGSize, divisions: Int)?

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
    private var pinchGesture: UIPinchGestureRecognizer?

    var isViewportEnabled: Bool = false {
        didSet {
            guard isViewportEnabled != oldValue else { return }
            // Locked: keep the paper in focus even when a hand enters the frame
            setFocusLocked(isViewportEnabled)
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
        backgroundColor = .clear // camera starts off; becomes black when it turns on
        clipsToBounds = true
        contentView.isUserInteractionEnabled = false // all gestures are handled by self
        addSubview(contentView)
        overlayImageView.contentMode = .scaleToFill
        overlayImageView.isHidden = true
        contentView.addSubview(overlayImageView)

        // Grid: 1 pt white line on a 3 pt dark halo (50%), so it reads on white paper (where a
        // white line alone vanishes) and on dark images
        gridView.isUserInteractionEnabled = false
        gridView.isHidden = true
        for layer in [gridHaloLayer, gridLineLayer] {
            layer.fillColor = nil
            layer.lineCap = .square
            gridView.layer.addSublayer(layer)
        }
        gridHaloLayer.strokeColor = UIColor.black.withAlphaComponent(0.5).cgColor
        gridLineLayer.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        contentView.addSubview(gridView)
    }

    /// All session/device configuration runs serially here, off the main thread.
    private let sessionQueue = DispatchQueue(label: "tracey.camera.session")

    var isZoomEnabled: Bool = true

    private(set) var captureMode: CameraCaptureMode = .video

    /// Prepares the preview layer and gestures only. The camera itself is not touched
    /// (no permission prompt, no session) until `setCameraActive(true)`.
    func setupCamera(mode: CameraCaptureMode) {
        captureMode = mode

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = Self.videoGravity(for: mode)
        previewLayer.isHidden = true // until the camera is turned on
        contentView.layer.insertSublayer(previewLayer, at: 0) // below the overlay image

        setupGestures()

        // Phone calls, Control Center camera use, background… pause a time-lapse
        let center = NotificationCenter.default
        center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: captureSession,
                           queue: .main) { [weak self] _ in self?.onSessionInterruptionChanged?(true) }
        center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: captureSession,
                           queue: .main) { [weak self] _ in self?.onSessionInterruptionChanged?(false) }
    }

    /// Main queue: true when the camera session was interrupted, false when it resumed.
    var onSessionInterruptionChanged: ((Bool) -> Void)?

    // MARK: - Time-lapse frames

    /// Sends camera frames to `recorder` (on its queue), rotated to `rotationAngle` so the clip
    /// keeps the interface orientation it started in (90 = portrait).
    func startFrameDelivery(to recorder: TimelapseRecorder, rotationAngle: CGFloat) {
        let mode = captureMode
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.captureDevice != nil else {
                #if DEBUG && targetEnvironment(simulator)
                // Simulator: no camera, feed synthetic frames sized like the real output
                let size = mode == .photo ? CGSize(width: 3024, height: 4032) : CGSize(width: 1080, height: 1920)
                let source = SyntheticFrameSource(recorder: recorder, size: size)
                source.start()
                self.syntheticFrames = source
                #endif
                return
            }
            if let connection = self.videoDataOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
            self.videoDataOutput.setSampleBufferDelegate(recorder, queue: recorder.queue)
        }
    }

    /// Stops sending frames; `completion` runs on the main queue once no more will arrive.
    func stopFrameDelivery(completion: @escaping () -> Void) {
        sessionQueue.async { [weak self] in
            self?.videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
            #if DEBUG
            self?.syntheticFrames?.stop()
            self?.syntheticFrames = nil
            #endif
            DispatchQueue.main.async(execute: completion)
        }
    }

    // MARK: - Camera on/off

    private var isCameraActive = false
    /// Session-queue state: whether the input and format have been configured yet.
    private var isSessionConfigured = false
    /// Zoom requested before the camera was configured (e.g. loading a saved reference).
    private var pendingZoom: CGFloat?

    /// Reports (on the main thread) whether camera access is denied/restricted.
    var onCameraAccessDenied: ((Bool) -> Void)?

    private func reportCameraAccess(denied: Bool) {
        DispatchQueue.main.async { [weak self] in self?.onCameraAccessDenied?(denied) }
    }

    /// Starts the camera when a reference image is on screen and stops it otherwise.
    func setCameraActive(_ active: Bool) {
        guard active != isCameraActive else { return }
        isCameraActive = active
        let mode = captureMode

        // When off, hide the preview (it would freeze on the last frame) and let the
        // idle background behind this view show through.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.isHidden = !active
        backgroundColor = active ? .black : .clear
        CATransaction.commit()

        if active {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                reportCameraAccess(denied: false)
            case .notDetermined:
                // Ask now, and hold the session queue until the user answers so the start
                // below runs with the answer
                let queue = sessionQueue
                queue.suspend()
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    self?.reportCameraAccess(denied: !granted)
                    queue.resume()
                }
            default: // .denied, .restricted
                reportCameraAccess(denied: true)
            }
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if active {
                guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
                if !self.isSessionConfigured {
                    self.configureSession(mode: mode)
                }
                if self.isSessionConfigured && !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
            } else if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    /// Must be called on `sessionQueue`, once camera access is authorized. First call adds the
    /// camera input.
    private func configureSession(mode: CameraCaptureMode) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("No camera available")
            return
        }

        captureSession.beginConfiguration()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            print("Error setting up camera input: \(error)")
            captureSession.commitConfiguration()
            return
        }
        applyFormat(for: mode, on: device)
        // Time-lapse frames (no delegate until recording)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            if let connection = videoDataOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90 // portrait buffers
            }
        }
        captureSession.commitConfiguration()

        captureDevice = device
        isSessionConfigured = true

        if let zoom = pendingZoom {
            pendingZoom = nil
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = Self.clampedZoom(zoom, for: device)
                device.unlockForConfiguration()
            } catch {
                print("Error applying pending zoom: \(error)")
            }
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
            gridView.isHidden = true
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
        layoutGrid(state)
    }

    /// Moves, scales, rotates and mirrors with the image (same bounds, center and transform).
    /// It ignores the image's opacity: a grid alone, with the image at 0%, is a valid use.
    private func layoutGrid(_ state: OverlayRenderState) {
        guard state.gridDivisions > 1 else {
            gridView.isHidden = true
            return
        }
        gridView.isHidden = false
        gridView.bounds = overlayImageView.bounds
        gridView.center = overlayImageView.center
        gridView.transform = overlayImageView.transform

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = gridView.bounds.size
        if gridPathKey?.size != size || gridPathKey?.divisions != state.gridDivisions {
            gridPathKey = (size, state.gridDivisions)
            let path = UIBezierPath(rect: CGRect(origin: .zero, size: size)) // outer border too
            for index in 1..<state.gridDivisions {
                let x = size.width * CGFloat(index) / CGFloat(state.gridDivisions)
                let y = size.height * CGFloat(index) / CGFloat(state.gridDivisions)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            for layer in [gridHaloLayer, gridLineLayer] {
                layer.frame = gridView.bounds
                layer.path = path.cgPath
            }
        }
        CATransaction.commit()
        updateGridLineWidths()
    }

    /// Constant on screen whatever the image size and the locked view's zoom.
    private func updateGridLineWidths() {
        guard !gridView.isHidden, let state = overlayState else { return }
        let scale = max(abs(state.scale) * viewportScale, 0.01)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gridLineLayer.lineWidth = 1 / scale
        gridHaloLayer.lineWidth = 3 / scale
        CATransaction.commit()
    }

    // MARK: - Viewport (move / zoom the whole screen while locked)

    private func applyViewportTransform() {
        // Scale about the screen center, then translate
        contentView.transform = CGAffineTransform(scaleX: viewportScale, y: viewportScale)
            .concatenating(CGAffineTransform(translationX: viewportOffset.x, y: viewportOffset.y))
        updateGridLineWidths()
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
        guard isViewportEnabled else {
            handleImagePan(gesture)
            return
        }
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
        // Pan + pinch (+ rotate) together: two fingers can move, zoom and turn at the same time
        true
    }

    /// Global-coordinate rects where a tap / long press belongs to a control drawn above this view.
    var tapExclusionRects: [CGRect] = []
    /// When the finger went down for the current tap (system uptime)
    private var tapTouchDownTime: TimeInterval = 0

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer is UITapGestureRecognizer || gestureRecognizer is UILongPressGestureRecognizer else {
            return true
        }
        // Only touches that really landed on this view (not on a UIKit view above it)...
        guard touch.view === self else { return false }
        if gestureRecognizer is UITapGestureRecognizer { tapTouchDownTime = touch.timestamp }
        // ...and not on a SwiftUI control drawn above it whose hit test was missed
        let point = touch.location(in: nil)
        return !tapExclusionRects.contains { $0.contains(point) }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer {
            // Locked: drag moves the whole screen. Unlocked: only a drag that starts on the image.
            return isViewportEnabled || isOnImage(gestureRecognizer)
        }
        if gestureRecognizer is UIRotationGestureRecognizer {
            return !isViewportEnabled && isOnImage(gestureRecognizer)
        }
        if gestureRecognizer is UILongPressGestureRecognizer {
            // Locked: a resting hand must not switch the locked focus back to autofocus (the
            // Focus center button still works). Unlocked: a still finger on the image is about
            // to drag it, not asking to focus.
            return !isViewportEnabled && !isOnImage(gestureRecognizer)
        }
        return true
    }

    // MARK: - Editing the image (unlocked)
    //
    // The image is edited with native recognizers on this same view (no SwiftUI overlay on top):
    // every touch reaches one view, so the gestures can't get stuck when fingers land partly
    // on and partly off the image. Values are reported live to the view model.

    var onOverlayEdit: ((OverlayEdit) -> Void)?

    private var editState: (offset: CGSize, scale: CGFloat, rotation: Double)?
    private var rotationAtStart: Double = 0
    private var pinchEditsImage = false
    private var panMovedImage = false
    private let imageScaleRange: ClosedRange<CGFloat> = 0.1...5.0
    private let centerSnapDistance: CGFloat = 30
    private let angleSnapDegrees: Double = 8
    /// Tick when the drag enters a center snap zone or the rotation lands on 0/90/180/270
    private let snapFeedback = UISelectionFeedbackGenerator()
    /// Once snapped, an axis stays at 0 until the drag goes this far from center (hysteresis)
    private let centerReleaseDistance: CGFloat = 40
    /// Where the finger would have put the image without the magnetic center
    private var rawDragOffset: CGSize = .zero
    /// Axes currently held at the center by the magnet
    private var snapLatched = (x: false, y: false)

    /// True when the gesture's touches (or their center) are on the drawn image. A small margin
    /// makes small images easier to grab.
    private func isOnImage(_ gesture: UIGestureRecognizer) -> Bool {
        guard overlayState?.image != nil, !overlayImageView.isHidden else { return false }
        let hitArea = overlayImageView.bounds.insetBy(dx: -16, dy: -16)
        if hitArea.contains(gesture.location(in: overlayImageView)) { return true }
        for index in 0..<gesture.numberOfTouches
        where hitArea.contains(gesture.location(ofTouch: index, in: overlayImageView)) {
            return true
        }
        return false
    }

    private func isActive(_ recognizer: UIGestureRecognizer?) -> Bool {
        guard let recognizer else { return false }
        return recognizer.state == .began || recognizer.state == .changed
    }

    private var isImageGestureActive: Bool {
        let panActive = !isViewportEnabled && isActive(panGesture)
        let pinchActive = pinchEditsImage && isActive(pinchGesture)
        let rotationActive = gestureRecognizers?.contains { $0 is UIRotationGestureRecognizer && isActive($0) } ?? false
        return panActive || pinchActive || rotationActive
    }

    private func beginImageEdit() {
        guard editState == nil, let state = overlayState else { return }
        editState = (state.offset, state.scale, state.rotation)
        panMovedImage = false
        rawDragOffset = state.offset
        snapLatched = (abs(state.offset.width) < 0.5, abs(state.offset.height) < 0.5)
        snapFeedback.prepare()
    }

    private func handleImagePan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { beginImageEdit() }
        // Apply movement on .ended too: when the system coalesces the last touch moves into
        // the "finger up" event, that final stretch would otherwise be lost.
        if [.began, .changed, .ended].contains(gesture.state), var edit = editState {
            let translation = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            if translation != .zero {
                rawDragOffset.width += translation.x
                rawDragOffset.height += translation.y
                // Magnetic center: within the snap distance an axis is held exactly at 0 (so the
                // amber guide only shows when the image really is centered) until the drag pulls
                // it beyond the release distance
                var snapped = false
                if snapLatched.x {
                    if abs(rawDragOffset.width) > centerReleaseDistance { snapLatched.x = false }
                } else if abs(rawDragOffset.width) <= centerSnapDistance {
                    snapLatched.x = true
                    snapped = true
                }
                if snapLatched.y {
                    if abs(rawDragOffset.height) > centerReleaseDistance { snapLatched.y = false }
                } else if abs(rawDragOffset.height) <= centerSnapDistance {
                    snapLatched.y = true
                    snapped = true
                }
                if snapped {
                    snapFeedback.selectionChanged()
                    snapFeedback.prepare()
                }
                edit.offset = CGSize(width: snapLatched.x ? 0 : rawDragOffset.width,
                                     height: snapLatched.y ? 0 : rawDragOffset.height)
                editState = edit
                panMovedImage = true
                publishImageEdit(isDragging: gesture.state != .ended)
            }
        }
        if gesture.state != .began && gesture.state != .changed {
            finishImageEditIfIdle()
        }
    }

    private func handleImagePinch(_ gesture: UIPinchGestureRecognizer) {
        if [.began, .changed, .ended].contains(gesture.state), var edit = editState, gesture.scale != 1 {
            let scaled = edit.scale * gesture.scale
            edit.scale = min(max(scaled, imageScaleRange.lowerBound), imageScaleRange.upperBound)
            editState = edit
            gesture.scale = 1
            publishImageEdit(isDragging: isActive(panGesture))
        }
        if gesture.state != .began && gesture.state != .changed {
            pinchEditsImage = false
            finishImageEditIfIdle()
        }
    }

    @objc private func handleImageRotation(_ gesture: UIRotationGestureRecognizer) {
        if gesture.state == .began {
            beginImageEdit()
            rotationAtStart = editState?.rotation ?? 0
        }
        if [.began, .changed, .ended].contains(gesture.state), var edit = editState {
            let raw = rotationAtStart + Double(gesture.rotation) * 180 / .pi
            let snapped = snappedAngle(raw)
            if snapped != edit.rotation {
                if [0.0, 90, 180, 270].contains(snapped) {
                    snapFeedback.selectionChanged()
                    snapFeedback.prepare()
                }
                edit.rotation = snapped
                editState = edit
                publishImageEdit(isDragging: isActive(panGesture))
            }
        }
        if gesture.state != .began && gesture.state != .changed {
            finishImageEditIfIdle()
        }
    }

    /// Ends the edit only when every image gesture has finished, so a finger lifted mid-pinch
    /// doesn't make the image jump.
    private func finishImageEditIfIdle() {
        guard var edit = editState, !isImageGestureActive else { return }
        // Magnetic center: snap each axis that ended within the threshold (after a drag)
        if panMovedImage {
            if abs(edit.offset.width) <= centerSnapDistance { edit.offset.width = 0 }
            if abs(edit.offset.height) <= centerSnapDistance { edit.offset.height = 0 }
        }
        editState = nil
        panMovedImage = false
        onOverlayEdit?(OverlayEdit(offset: edit.offset, scale: edit.scale, rotation: edit.rotation,
                                   isDragging: false, phase: .ended))
    }

    private func publishImageEdit(isDragging: Bool) {
        guard let edit = editState, var state = overlayState else { return }
        // Draw immediately; the view model gets the same values (so SwiftUI stays in sync)
        state.offset = edit.offset
        state.scale = edit.scale
        state.rotation = edit.rotation
        overlayState = state
        layoutOverlay()
        onOverlayEdit?(OverlayEdit(offset: edit.offset, scale: edit.scale, rotation: edit.rotation,
                                   isDragging: isDragging, phase: .changed))
    }

    /// Normalizes to 0..<360 and snaps to 0/90/180/270 within a few degrees.
    private func snappedAngle(_ angle: Double) -> Double {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        for cardinal in [0.0, 90, 180, 270, 360] where abs(normalized - cardinal) <= angleSnapDegrees {
            return cardinal == 360 ? 0 : cardinal
        }
        return normalized
    }

    // MARK: - Capture mode

    /// Switches between the smooth video preview and the full-frame photo preview.
    /// Camera zoom and torch state are preserved.
    func setCaptureMode(_ mode: CameraCaptureMode) {
        guard mode != captureMode else { return }
        captureMode = mode

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.captureDevice else {
                // Camera not started yet: the new format is used when it starts; just
                // update how the (empty) preview will be framed.
                DispatchQueue.main.async {
                    self.previewLayer.videoGravity = Self.videoGravity(for: mode)
                }
                return
            }
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
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)
        pinchGesture = pinch

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        panGesture = pan

        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleImageRotation(_:)))
        rotation.delegate = self
        addGestureRecognizer(rotation)

        // A tap shows / hides the controls. This view is under every control, so its tap
        // recognizer is the single source of truth (a SwiftUI tap on top never received them).
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)

        // Touch and hold focuses (and meters exposure) at that point
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressToFocus(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delegate = self
        addGestureRecognizer(longPress)
        // A long press must not also count as a tap when the finger lifts. A quick tap isn't
        // delayed: the long press fails as soon as the finger lifts before 0.5 s.
        tapGesture.require(toFail: longPress)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if isViewportEnabled {
            handleViewportPinch(gesture)
            return
        }
        // Unlocked: a pinch that starts on the image resizes it; elsewhere it zooms the camera
        if gesture.state == .began {
            pinchEditsImage = isOnImage(gesture)
            if pinchEditsImage { beginImageEdit() }
        }
        if pinchEditsImage {
            handleImagePinch(gesture)
            return
        }
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

    var onSingleTap: (() -> Void)?

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        // A press held still for a while isn't a tap (e.g. a hold on the image while locked or
        // before dragging, where the long press doesn't run)
        guard ProcessInfo.processInfo.systemUptime - tapTouchDownTime < 0.5 else { return }
        onSingleTap?()
    }

    @objc private func handleLongPressToFocus(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, captureDevice != nil else { return }
        focus(at: gesture.location(in: self))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                // Meter at that point but keep exposure automatic (light changes while drawing)
                device.exposureMode = device.isExposureModeSupported(.continuousAutoExposure)
                    ? .continuousAutoExposure : .autoExpose
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

    /// Locked focus while the reference is locked; continuous autofocus otherwise.
    /// Exposure is left automatic.
    private func setFocusLocked(_ locked: Bool) {
        sessionQueue.async { [weak self] in
            guard let device = self?.captureDevice else { return }
            let mode: AVCaptureDevice.FocusMode = locked ? .locked : .continuousAutoFocus
            guard device.isFocusModeSupported(mode) else { return }
            do {
                try device.lockForConfiguration()
                device.focusMode = mode
                device.unlockForConfiguration()
            } catch {
                print("Error setting focus mode: \(error)")
            }
        }
    }

    // MARK: - Zoom

    func setZoomFactor(_ zoom: CGFloat) {
        // Serialized with capture-mode changes so a restored zoom isn't overwritten
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.captureDevice else {
                // Camera not started yet: apply when it is
                self.pendingZoom = zoom
                return
            }
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
