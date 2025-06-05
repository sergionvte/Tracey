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
    @State private var isPropertiesLocked = false // Lock state

    // Snap to center configuration
    private let snapThreshold: CGFloat = 30 // Distance in points to activate snap

    var body: some View {
        GeometryReader { geometry in
            let screenCenter = CGPoint(
                x: geometry.size.width / 2,
                y: geometry.size.height / 2
            )

            ZStack {
                // Camera view
                CameraView(viewModel: viewModel, cameraUIView: $cameraUIView, isZoomEnabled: !isPropertiesLocked)
                    .ignoresSafeArea()

                // Overlay image with improved gestures
                if let overlayImage = viewModel.overlayImage {
                    Image(uiImage: overlayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(viewModel.imageOpacity)
                        .scaleEffect(x: viewModel.isFlipped ? -1 : 1, y: 1) // Flip horizontally if enabled
                        .scaleEffect(viewModel.imageScale * currentGestureScale) // Apply incremental scale
                        .rotationEffect(.degrees(viewModel.imageRotation))
                        .offset(CGSize(
                            width: viewModel.imageOffset.width + dragOffset.width,
                            height: viewModel.imageOffset.height + dragOffset.height
                        ))
                        .gesture(
                            // Only allow gestures if not locked
                            isPropertiesLocked ? nil :
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
                            isPropertiesLocked ? nil :
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
                if viewModel.overlayImage != nil && !isPropertiesLocked && (abs(dragOffset.width) > 0 || abs(dragOffset.height) > 0) {
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
                                if isPropertiesLocked {
                                    // Consume the tap but do nothing
                                    return
                                }
                                viewModel.flipOverlayImage()
                            }) {
                                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(isPropertiesLocked ? Color.gray.opacity(0.5) : (viewModel.isFlipped ? Color.green.opacity(0.8) : Color.black.opacity(0.6)))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }

                            // Lock button
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isPropertiesLocked.toggle()
                                }

                                // Haptic feedback
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                            }) {
                                Image(systemName: isPropertiesLocked ? "lock.fill" : "lock.open")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(isPropertiesLocked ? Color.red.opacity(0.8) : Color.black.opacity(0.6))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
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

                        ImageControlsView(viewModel: viewModel, isLocked: isPropertiesLocked)
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
                        isPropertiesLocked: isPropertiesLocked
                    )
                }
                .opacity(showingControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: showingControls)

                // Camera zoom indicator and lock state
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("📹 Pinch to zoom • Tap to focus")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(20)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                            // Lock state indicator
                            if viewModel.overlayImage != nil {
                                HStack(spacing: 4) {
                                    Image(systemName: isPropertiesLocked ? "lock.fill" : "lock.open")
                                        .font(.caption2)
                                        .foregroundColor(isPropertiesLocked ? .red : .green)

                                    Text(isPropertiesLocked ? "Properties locked" : "Properties unlocked")
                                        .font(.caption2)
                                        .foregroundColor(isPropertiesLocked ? .red : .green)
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
            withAnimation(.easeInOut(duration: 0.3)) {
                showingControls.toggle()
                if !showingControls {
                    showingImageControls = false
                }
            }
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
