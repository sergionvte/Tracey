// ContentView.swift - Tracing screen: camera + reference overlay with floating Liquid Glass controls
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var showingImagePicker = false
    @State private var showingControls = true
    @State private var showingImageControls = false // New state for image controls
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
                        scale: viewModel.imageScale,
                        rotation: viewModel.imageRotation,
                        offset: viewModel.imageOffset,
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

                // The image is moved / pinched / rotated by native gestures inside CameraView
                // (same view that draws it), so there is no SwiftUI touch layer on top.

                // Visual snap indicators (only if not locked)
                if viewModel.overlayImage != nil && !viewModel.isPropertiesLocked && viewModel.isDraggingImage {
                    SnapIndicators(
                        dragOffset: .zero,
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
