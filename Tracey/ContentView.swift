// ContentView.swift - Tracing screen: camera + reference overlay with floating Liquid Glass controls
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var showingImagePicker = false
    @State private var showingControls = true
    @State private var showingImageControls = false // New state for image controls
    @State private var dragOffset: CGSize = .zero
    @State private var gestureStartScale: CGFloat = 1.0
    @State private var gestureStartRotation: Double = 0.0
    @State private var gestureInProgress = false
    @State private var currentGestureScale: CGFloat = 1.0 // For incremental zoom
    @State private var cameraUIView: CameraUIView? = nil // Reference to camera view
    @State private var toast: ToastMessage? = nil

    // Snap to center configuration
    private let snapThreshold: CGFloat = 30 // Distance in points to activate snap

    var body: some View {
        GeometryReader { geometry in
            // The camera preview fills the WHOLE screen (it ignores the safe area), so its center
            // is the screen center — not the safe-area center, which sits lower because the top
            // inset (Dynamic Island) is taller than the bottom one. Center the overlay on the
            // camera so "centered" means centered on what the camera shows.
            let cameraCenterShift = CGSize(
                width: (geometry.safeAreaInsets.trailing - geometry.safeAreaInsets.leading) / 2,
                height: (geometry.safeAreaInsets.bottom - geometry.safeAreaInsets.top) / 2
            )
            let screenCenter = CGPoint(
                x: geometry.size.width / 2 + cameraCenterShift.width,
                y: geometry.size.height / 2 + cameraCenterShift.height
            )

            ZStack {
                // Shown while the camera is off (no reference image yet)
                IdleBackground()
                    .ignoresSafeArea()

                // Camera view. The overlay image is DRAWN inside the camera view (same UIKit
                // container as the camera preview), so while locked, moving/zooming the screen
                // moves both as one piece and they can never drift apart.
                CameraView(
                    viewModel: viewModel,
                    cameraUIView: $cameraUIView,
                    isZoomEnabled: !viewModel.isPropertiesLocked,
                    isViewportEnabled: viewModel.isPropertiesLocked,
                    overlay: OverlayRenderState(
                        image: viewModel.overlayImage,
                        opacity: viewModel.imageOpacity,
                        scale: viewModel.imageScale * currentGestureScale,
                        rotation: viewModel.imageRotation,
                        offset: CGSize(
                            width: viewModel.imageOffset.width + dragOffset.width,
                            height: viewModel.imageOffset.height + dragOffset.height
                        ),
                        isFlipped: viewModel.isFlipped
                    ),
                    overlayLayoutRect: CGRect(
                        x: geometry.safeAreaInsets.leading + cameraCenterShift.width,
                        y: geometry.safeAreaInsets.top + cameraCenterShift.height,
                        width: geometry.size.width,
                        height: geometry.size.height
                    ),
                    // Camera stays off until there is a reference image to trace
                    isCameraActive: viewModel.overlayImage != nil
                )
                .ignoresSafeArea()

                // Invisible touch target with the same layout as the drawn image, used to
                // edit it while unlocked. While locked it is removed so touches reach the camera
                // view (drag/pinch move the whole screen, tap focuses).
                if let overlayImage = viewModel.overlayImage, !viewModel.isPropertiesLocked {
                    Color.clear
                        .aspectRatio(overlayImage.size, contentMode: .fit)
                        .contentShape(Rectangle())
                        .scaleEffect(x: viewModel.isFlipped ? -1 : 1, y: 1) // Flip horizontally if enabled
                        .scaleEffect(viewModel.imageScale * currentGestureScale) // Apply incremental scale
                        .rotationEffect(.degrees(viewModel.imageRotation))
                        .offset(CGSize(
                            width: viewModel.imageOffset.width + dragOffset.width + cameraCenterShift.width,
                            height: viewModel.imageOffset.height + dragOffset.height + cameraCenterShift.height
                        ))
                        .gesture(
                            viewModel.isPropertiesLocked ? nil :
                            // Incremental scale gesture
                            MagnificationGesture()
                                .onChanged { value in
                                    currentGestureScale = value
                                }
                                .onEnded { value in
                                    // Apply final change to base scale
                                    let finalScale = viewModel.imageScale * value

                                    // Validate that the value is finite and within the allowed range
                                    if finalScale.isFinite && finalScale > 0 {
                                        viewModel.imageScale = max(0.1, min(finalScale, 5.0))
                                    }

                                    // Reset gesture scale
                                    currentGestureScale = 1.0
                                }
                                .simultaneously(with:
                                    // Rotation gesture
                                    RotationGesture()
                                        .onChanged { value in
                                            if !gestureInProgress {
                                                gestureStartRotation = viewModel.imageRotation
                                                gestureInProgress = true
                                            }

                                            let rawRotation = gestureStartRotation + value.degrees
                                            let snappedRotation = snapToCardinalAngles(rawRotation)

                                            // Validate that the value is finite before assigning
                                            if snappedRotation.isFinite {
                                                viewModel.imageRotation = snappedRotation
                                            }
                                        }
                                        .onEnded { value in
                                            // Update base value with final result at gesture end
                                            let rawRotation = gestureStartRotation + value.degrees
                                            let finalRotation = snapToCardinalAngles(rawRotation)

                                            if finalRotation.isFinite {
                                                // Smooth animation to final angle
                                                withAnimation(.easeOut(duration: 0.2)) {
                                                    viewModel.imageRotation = finalRotation
                                                }
                                            }
                                            gestureInProgress = false
                                        }
                                )
                        )
                        .simultaneousGesture(
                            // Only allow movement if not locked
                            viewModel.isPropertiesLocked ? nil :
                            // Separate movement gesture with snap to center
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    // Calculate proposed final position
                                    let proposedOffsetX = viewModel.imageOffset.width + value.translation.width
                                    let proposedOffsetY = viewModel.imageOffset.height + value.translation.height

                                    // Apply snap to center
                                    let snappedOffset = snapToCenter(
                                        offset: CGSize(width: proposedOffsetX, height: proposedOffsetY),
                                        screenCenter: screenCenter
                                    )

                                    // Validate that the values are finite
                                    if snappedOffset.width.isFinite && snappedOffset.height.isFinite {
                                        // First update without animation to current position (including dragOffset)
                                        viewModel.imageOffset = CGSize(
                                            width: proposedOffsetX,
                                            height: proposedOffsetY
                                        )
                                        dragOffset = .zero

                                        // Then animate to final position with snap (if applies)
                                        if snappedOffset != CGSize(width: proposedOffsetX, height: proposedOffsetY) {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                viewModel.imageOffset = snappedOffset
                                            }
                                        }
                                    } else {
                                        dragOffset = .zero
                                    }
                                }
                        )
                }

                // Visual snap indicators (only if not locked)
                if viewModel.overlayImage != nil && !viewModel.isPropertiesLocked && (abs(dragOffset.width) > 0 || abs(dragOffset.height) > 0) {
                    SnapIndicators(
                        dragOffset: dragOffset,
                        imageOffset: viewModel.imageOffset,
                        screenCenter: screenCenter,
                        snapThreshold: snapThreshold
                    )
                }

                // MARK: Glass controls
                VStack(spacing: 12) {
                    HStack(alignment: .top) {
                        CaptureModeSwitch(
                            mode: viewModel.captureMode,
                            isLocked: viewModel.isPropertiesLocked,
                            onSelect: selectCaptureMode
                        )
                        Spacer(minLength: 12)
                        ToolColumn(
                            isTorchOn: viewModel.isTorchOn,
                            isFlipped: viewModel.isFlipped,
                            hasImage: viewModel.overlayImage != nil,
                            isLocked: viewModel.isPropertiesLocked,
                            showsResetView: viewModel.isPropertiesLocked && viewModel.isViewportTransformed,
                            onFocus: {
                                cameraUIView?.focusAtCenter()
                                Haptics.light()
                            },
                            onTorch: {
                                viewModel.toggleTorch()
                                Haptics.light()
                            },
                            onFlip: {
                                viewModel.flipOverlayImage()
                                Haptics.light()
                            },
                            onLockedTap: lockedWarning,
                            onResetView: {
                                viewModel.resetViewport()
                                Haptics.light()
                            }
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    Spacer(minLength: 0)

                    if let toast {
                        ToastView(message: toast)
                            .id(toast.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if showingImageControls && viewModel.overlayImage != nil {
                        AdjustPanel(viewModel: viewModel, isLocked: viewModel.isPropertiesLocked)
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    BottomDock(
                        hasImage: viewModel.overlayImage != nil,
                        isLocked: viewModel.isPropertiesLocked,
                        isAdjustOpen: showingImageControls,
                        onImport: { showingImagePicker = true },
                        onLibrary: { viewModel.showingSavedImages = true },
                        onToggleLock: toggleLock,
                        onAdjust: {
                            withAnimation(Theme.spring) { showingImageControls.toggle() }
                            Haptics.light()
                        },
                        onCenter: {
                            viewModel.centerImage()
                            Haptics.light()
                        },
                        onSave: saveConfiguration,
                        onRemove: {
                            viewModel.removeOverlayImage()
                            withAnimation(Theme.spring) { showingImageControls = false }
                        },
                        onLockedTap: lockedWarning
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .opacity(showingControls ? 1 : 0)
                .allowsHitTesting(showingControls)

                // Welcome card until there is a reference image.
                // Always in the hierarchy (never inserted/removed): if it were removed with a
                // transition while the picker/library sheet covers the screen, SwiftUI can leave
                // the invisible card stuck in the middle swallowing touches, so the new image
                // couldn't be dragged until some other state change. Driving visibility and
                // hit-testing from state makes it stop catching touches immediately.
                let showsWelcome = viewModel.overlayImage == nil && showingControls
                EmptyStateCard(
                    onImport: { showingImagePicker = true },
                    onLibrary: { viewModel.showingSavedImages = true }
                )
                .padding(.horizontal, 32)
                .opacity(showsWelcome ? 1 : 0)
                .scaleEffect(showsWelcome ? 1 : 0.96)
                .allowsHitTesting(showsWelcome)
                .accessibilityHidden(!showsWelcome)
            }
            .animation(Theme.spring, value: showingImageControls)
            .animation(Theme.spring, value: toast)
            .animation(.easeInOut(duration: 0.25), value: showingControls)
            .animation(Theme.spring, value: viewModel.overlayImage == nil)
        }
        .preferredColorScheme(.dark)
        // Immersive while drawing: hiding the controls also hides the status bar and home indicator
        .statusBarHidden(!showingControls)
        .persistentSystemOverlays(showingControls ? .automatic : .hidden)
        .onAppear {
            // Keep the screen active
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            // Restore normal behavior when the app is closed
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onTapGesture {
            toggleControls()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $viewModel.selectedImageFromGallery) // Use the property that clears loadedImageName
        }
        .sheet(isPresented: $viewModel.showingSavedImages, onDismiss: {
            showingImageControls = false // Ensure the main menu can be opened
        }) {
            SavedImagesView(viewModel: viewModel, storage: viewModel.imageStorage, isPresented: $viewModel.showingSavedImages)
        }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showingControls.toggle()
            if !showingControls {
                showingImageControls = false
            }
        }
    }

    // MARK: - Actions

    private func toggleLock() {
        withAnimation(Theme.spring) {
            viewModel.isPropertiesLocked.toggle()
            if viewModel.isPropertiesLocked { showingImageControls = false }
        }
        Haptics.medium()
        if viewModel.isPropertiesLocked {
            showToast(ToastMessage(icon: "lock.fill", text: "Locked · drag & pinch to move the view", tint: Theme.accent))
        } else {
            showToast(ToastMessage(icon: "lock.open.fill", text: "Unlocked · edit your reference"))
        }
    }

    private func selectCaptureMode(_ mode: CameraCaptureMode) {
        guard mode != viewModel.captureMode else { return }
        guard !viewModel.isPropertiesLocked else {
            lockedWarning()
            return
        }
        viewModel.captureMode = mode
        Haptics.light()
        showToast(ToastMessage(icon: mode.iconName, text: mode.detail))
    }

    private func saveConfiguration() {
        let zoom = viewModel.cameraUIViewRef?.getCurrentZoomFactor() ?? 1.0
        if viewModel.saveCurrentConfiguration(cameraZoom: zoom) {
            Haptics.success()
            showToast(ToastMessage(icon: "checkmark.circle.fill", text: "Saved to Library", tint: Theme.accent))
        } else {
            Haptics.warning()
            showToast(ToastMessage(icon: "exclamationmark.triangle.fill", text: "Couldn't save the image", tint: Theme.danger))
        }
    }

    private func lockedWarning() {
        Haptics.warning()
        showToast(ToastMessage(icon: "lock.fill", text: "Unlock to edit", tint: Theme.accent))
    }

    private func showToast(_ message: ToastMessage) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if toast?.id == message.id { toast = nil }
        }
    }

    // Function to snap to cardinal angles
    private func snapToCardinalAngles(_ angle: Double) -> Double {
        let normalizedAngle = angle.truncatingRemainder(dividingBy: 360)
        let positiveAngle = normalizedAngle < 0 ? normalizedAngle + 360 : normalizedAngle

        let cardinalAngles: [Double] = [0, 90, 180, 270, 360]
        let snapThreshold: Double = 8 // Degrees of "magnetism" - more subtle

        for cardinalAngle in cardinalAngles {
            let distance = abs(positiveAngle - cardinalAngle)
            let wrappedDistance = min(distance, 360 - distance) // For the case of 0° and 360°

            if wrappedDistance <= snapThreshold {
                return cardinalAngle == 360 ? 0 : cardinalAngle // 360° becomes 0°
            }
        }

        return positiveAngle
    }

    // Function to snap to the center of the screen
    private func snapToCenter(offset: CGSize, screenCenter: CGPoint) -> CGSize {
        var finalOffset = offset

        // Horizontal snap (X center)
        if abs(offset.width) <= snapThreshold {
            finalOffset.width = 0
        }

        // Vertical snap (Y center)
        if abs(offset.height) <= snapThreshold {
            finalOffset.height = 0
        }

        return finalOffset
    }
}

// Snap indicators view
struct SnapIndicators: View {
    let dragOffset: CGSize
    let imageOffset: CGSize
    let screenCenter: CGPoint
    let snapThreshold: CGFloat

    private var showVerticalIndicator: Bool {
        abs(imageOffset.width + dragOffset.width) <= snapThreshold
    }

    private var showHorizontalIndicator: Bool {
        abs(imageOffset.height + dragOffset.height) <= snapThreshold
    }

    var body: some View {
        ZStack {
            // Vertical center line
            if showVerticalIndicator {
                Rectangle()
                    .fill(Theme.accent.opacity(0.9))
                    .frame(width: 2)
                    .position(x: screenCenter.x, y: screenCenter.y)
                    .animation(.easeInOut(duration: 0.2), value: showVerticalIndicator)
            }

            // Horizontal center line
            if showHorizontalIndicator {
                Rectangle()
                    .fill(Theme.accent.opacity(0.9))
                    .frame(height: 2)
                    .position(x: screenCenter.x, y: screenCenter.y)
                    .animation(.easeInOut(duration: 0.2), value: showHorizontalIndicator)
            }

            // Center dot
            if showVerticalIndicator || showHorizontalIndicator {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 8, height: 8)
                    .position(x: screenCenter.x, y: screenCenter.y)
                    .animation(.easeInOut(duration: 0.2), value: showVerticalIndicator || showHorizontalIndicator)
            }
        }
        .allowsHitTesting(false) // Allow gestures to pass through
    }
}
