// ContentView.swift - With corrected gestures, improved controls, snap to center, focus button, lock, and always-on screen
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
                    )
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

                // Focus and lock buttons in the top right corner
                VStack {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            // Capture mode button: video (smoother) / photo (wider frame).
                            // Disabled while locked because switching changes the camera framing.
                            Button(action: {
                                guard !viewModel.isPropertiesLocked else { return }
                                viewModel.toggleCaptureMode()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }) {
                                Image(systemName: viewModel.captureMode.iconName)
                                    .font(.title3)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(viewModel.isPropertiesLocked ? Color.gray.opacity(0.5) : (viewModel.captureMode == .photo ? Color.orange.opacity(0.85) : Color.black.opacity(0.6)))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                            .accessibilityLabel(viewModel.captureMode == .video ? "Switch to photo mode" : "Switch to video mode")

                            // Focus button
                            Button(action: {
                                // Focus at the center of the screen
                                cameraUIView?.focusAtCenter()
                            }) {
                                Image(systemName: "viewfinder.circle")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }

                            // Torch button
                            Button(action: {
                                viewModel.toggleTorch()
                            }) {
                                Image(systemName: viewModel.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(viewModel.isTorchOn ? Color.blue.opacity(0.8) : Color.black.opacity(0.6))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }

                            // Horizontal flip button (between torch and lock)
                            Button(action: {
                                if viewModel.isPropertiesLocked {
                                    // Consume the tap but do nothing
                                    return
                                }
                                viewModel.flipOverlayImage()
                            }) {
                                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(viewModel.isPropertiesLocked ? Color.gray.opacity(0.5) : (viewModel.isFlipped ? Color.green.opacity(0.8) : Color.black.opacity(0.6)))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }

                            // Lock button
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.isPropertiesLocked.toggle()
                                }

                                // Haptic feedback
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                            }) {
                                Image(systemName: viewModel.isPropertiesLocked ? "lock.fill" : "lock.open")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(viewModel.isPropertiesLocked ? Color.red.opacity(0.8) : Color.black.opacity(0.6))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }

                            // Reset view button: only when the locked screen has been moved/zoomed
                            if viewModel.isPropertiesLocked && viewModel.isViewportTransformed {
                                Button(action: {
                                    viewModel.resetViewport()
                                }) {
                                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(Color.blue.opacity(0.8))
                                        .clipShape(Circle())
                                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                }
                                .accessibilityLabel("Reset view")
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 10)
                    }
                    Spacer()
                }
                .opacity(showingControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: showingControls)

                // Image controls (new separate controls) - Only allow changes if not locked
                if showingImageControls && viewModel.overlayImage != nil {
                    VStack {
                        Spacer()

                        ImageControlsView(viewModel: viewModel, isLocked: viewModel.isPropertiesLocked)
                            .transition(.move(edge: .bottom).combined(with: .opacity))

                        Spacer().frame(height: 120) // Space for main controls
                    }
                }

                // Main controls - HERE WE ADD THE ANIMATION
                VStack {
                    Spacer()
                    ControlsView(
                        viewModel: viewModel,
                        showingImagePicker: $showingImagePicker,
                        showingImageControls: $showingImageControls,
                        isPropertiesLocked: viewModel.isPropertiesLocked
                    )
                }
                .opacity(showingControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: showingControls)

                // Camera zoom indicator and lock state
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.isPropertiesLocked
                                 ? "✋ Drag to move • Pinch to zoom view"
                                 : "📹 Pinch to zoom • Tap to focus")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(20)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                            // Capture mode indicator
                            HStack(spacing: 4) {
                                Image(systemName: viewModel.captureMode.iconName)
                                    .font(.caption2)
                                Text(viewModel.captureMode.title)
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(15)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                            // Lock state indicator
                            if viewModel.overlayImage != nil {
                                HStack(spacing: 4) {
                                    Image(systemName: viewModel.isPropertiesLocked ? "lock.fill" : "lock.open")
                                        .font(.caption2)
                                        .foregroundColor(viewModel.isPropertiesLocked ? .red : .green)

                                    Text(viewModel.isPropertiesLocked ? "Properties locked" : "Properties unlocked")
                                        .font(.caption2)
                                        .foregroundColor(viewModel.isPropertiesLocked ? .red : .green)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(15)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    Spacer()
                }
                .opacity(showingControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: showingControls)
            }
        }
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
            SavedImagesView(viewModel: viewModel, isPresented: $viewModel.showingSavedImages)
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
                    .fill(Color.yellow.opacity(0.8))
                    .frame(width: 2)
                    .position(x: screenCenter.x, y: screenCenter.y)
                    .animation(.easeInOut(duration: 0.2), value: showVerticalIndicator)
            }

            // Horizontal center line
            if showHorizontalIndicator {
                Rectangle()
                    .fill(Color.yellow.opacity(0.8))
                    .frame(height: 2)
                    .position(x: screenCenter.x, y: screenCenter.y)
                    .animation(.easeInOut(duration: 0.2), value: showHorizontalIndicator)
            }

            // Center dot
            if showVerticalIndicator || showHorizontalIndicator {
                Circle()
                    .fill(Color.yellow.opacity(0.9))
                    .frame(width: 8, height: 8)
                    .position(x: screenCenter.x, y: screenCenter.y)
                    .animation(.easeInOut(duration: 0.2), value: showVerticalIndicator || showHorizontalIndicator)
            }
        }
        .allowsHitTesting(false) // Allow gestures to pass through
    }
}

// New view for image controls with lock
struct ImageControlsView: View {
    @ObservedObject var viewModel: CameraViewModel
    let isLocked: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Row 1: Opacity
            VStack(spacing: 4) {
                Text("Opacity")
                    .foregroundColor(isLocked ? .gray : .white)
                    .font(.caption)
                    .fontWeight(.medium)

                HStack {
                    Text("0%")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption2)

                    Slider(value: $viewModel.imageOpacity, in: 0...1)
                        .frame(width: 180)
                        .disabled(isLocked)
                        .opacity(isLocked ? 0.5 : 1.0)

                    Text("100%")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption2)
                }

                Text("\(Int(viewModel.imageOpacity * 100))%")
                    .foregroundColor(isLocked ? .gray : .white)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }

            Divider()
                .background(Color.white.opacity(0.3))

            // Row 2: Size
            VStack(spacing: 4) {
                Text("Size")
                    .foregroundColor(isLocked ? .gray : .white)
                    .font(.caption)
                    .fontWeight(.medium)

                HStack {
                    Text("0.1x")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption2)

                    Slider(value: $viewModel.imageScale, in: 0.1...5.0)
                        .frame(width: 180)
                        .disabled(isLocked)
                        .opacity(isLocked ? 0.5 : 1.0)

                    Text("5.0x")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption2)
                }

                Text("\(String(format: "%.1f", viewModel.imageScale))x")
                    .foregroundColor(isLocked ? .gray : .white)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }

            Divider()
                .background(Color.white.opacity(0.3))

            // Row 3: Rotation
            VStack(spacing: 4) {
                Text("Rotation")
                    .foregroundColor(isLocked ? .gray : .white)
                    .font(.caption)
                    .fontWeight(.medium)

                HStack {
                    Text("0°")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption2)

                    Slider(value: $viewModel.imageRotation, in: 0...360)
                        .frame(width: 180)
                        .disabled(isLocked)
                        .opacity(isLocked ? 0.5 : 1.0)

                    Text("360°")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption2)
                }

                Text("\(Int(viewModel.imageRotation.isFinite ? viewModel.imageRotation : 0))°")
                    .foregroundColor(isLocked ? .gray : .white)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }

            // Lock indicator if locked
            if isLocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundColor(.red)

                    Text("Controls locked")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(isLocked ? 0.6 : 0.8))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isLocked ? Color.red.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
}
