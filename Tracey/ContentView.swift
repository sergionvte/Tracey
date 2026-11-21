// ContentView.swift - Tracing screen: camera + reference overlay with floating Liquid Glass controls
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var showingImagePicker = false
    @State private var showingControls = true
    @State private var showingImageControls = false // New state for image controls
    @State private var cameraUIView: CameraUIView? = nil // Reference to camera view
    /// The toast on screen (nil = hidden)
    @State private var toast: ToastMessage? = nil
    /// Last toast shown; keeps the content while it fades out
    @State private var lastToast: ToastMessage? = nil
    /// Where the toast is on screen (global), so the camera view ignores taps on an action toast
    @State private var toastFrame: CGRect = .zero

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
                    isCameraActive: viewModel.overlayImage != nil,
                    // Belt and braces: never treat a tap on the Undo toast as a screen tap
                    tapExclusionRects: toast?.actionTitle != nil && showingControls
                        ? [toastFrame.insetBy(dx: -8, dy: -8)] : [],
                    onSingleTap: toggleControls
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
                        // Hidden in place until there is an image: the welcome card is the only
                        // call to action
                        let hasImage = viewModel.overlayImage != nil
                        CaptureModeSwitch(
                            mode: viewModel.captureMode,
                            isLocked: viewModel.isPropertiesLocked,
                            onSelect: selectCaptureMode
                        )
                        .opacity(hasImage ? 1 : 0)
                        .allowsHitTesting(hasImage)
                        .accessibilityHidden(!hasImage)
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

                    // Always in the hierarchy (it can hold a button, e.g. Undo): fading it with
                    // opacity/hit testing can't leave an invisible toast catching touches.
                    let isToastVisible = toast != nil
                    ToastView(
                        message: lastToast ?? ToastMessage(icon: "info.circle", text: ""),
                        onAction: performToastAction
                    )
                    .opacity(isToastVisible ? 1 : 0)
                    .offset(y: isToastVisible ? 0 : 12)
                    .scaleEffect(isToastVisible ? 1 : 0.96)
                    // Only a toast with a button takes touches; others let taps reach the screen
                    .allowsHitTesting(isToastVisible && toast?.actionTitle != nil)
                    .accessibilityHidden(!isToastVisible)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { toastFrame = $0 }
                    .padding(.horizontal, 24)

                    // Adjust panel + dock as one item so the hidden panel adds no spacing.
                    // The panel is always in the hierarchy and fades/slides in place: removing it
                    // with a transition while the ⋯ menu was closing (Remove Image) left an
                    // invisible panel over the toast that swallowed the Undo tap.
                    let showsAdjust = showingImageControls && viewModel.overlayImage != nil
                    VStack(spacing: 0) {
                        AdjustPanel(viewModel: viewModel, isLocked: viewModel.isPropertiesLocked)
                            .padding(.horizontal, 16)
                            .padding(.bottom, showsAdjust ? 12 : 0)
                            // Hidden: takes no height (doesn't push the toast up), draws nothing,
                            // takes no touches
                            .frame(height: showsAdjust ? nil : 0, alignment: .bottom)
                            .opacity(showsAdjust ? 1 : 0)
                            .offset(y: showsAdjust ? 0 : 24)
                            .allowsHitTesting(showsAdjust)
                            .accessibilityHidden(!showsAdjust)

                        BottomDock(
                            hasImage: viewModel.overlayImage != nil,
                            isLocked: viewModel.isPropertiesLocked,
                            isAdjustOpen: showingImageControls,
                            onImport: { showingImagePicker = true },
                            onLibrary: { viewModel.showingSavedImages = true },
                            onLock: lock,
                            onUnlock: unlock,
                            onLockTapWhileLocked: holdToUnlockHint,
                            onChangeImageWhileLocked: changeImageWhileLocked,
                            onAdjust: {
                                withAnimation(Theme.spring) { showingImageControls.toggle() }
                                Haptics.light()
                            },
                            onCenter: {
                                viewModel.centerImage()
                                Haptics.light()
                            },
                            onSave: saveConfiguration,
                            onRemove: removeImage,
                            onLockedTap: lockedWarning
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
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

                // Camera access denied: explain and link to Settings (same in-place fading)
                let showsCameraAccess = viewModel.isCameraAccessDenied && viewModel.overlayImage != nil
                    && showingControls && !showingImageControls
                CameraAccessCard(onOpenSettings: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                })
                .padding(.horizontal, 32)
                .opacity(showsCameraAccess ? 1 : 0)
                .scaleEffect(showsCameraAccess ? 1 : 0.96)
                .allowsHitTesting(showsCameraAccess)
                .accessibilityHidden(!showsCameraAccess)
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
        // While locked (or immersive) an edge swipe from the pencil hand shouldn't go home or
        // open Control Center on the first try
        .defersSystemGestures(on: viewModel.isPropertiesLocked || !showingControls ? .all : [])
        .onAppear {
            // Keep the screen active
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            // Restore normal behavior when the app is closed
            UIApplication.shared.isIdleTimerDisabled = false
        }
        // While locked, turning the device must not re-lay out the screen (iPad; iPhone is
        // portrait-only) or the reference would no longer match the paper.
        .onChange(of: viewModel.isPropertiesLocked) { _, locked in
            OrientationLock.freeze(locked)
        }
        // One-time hint the first time an image ever appears
        .onChange(of: viewModel.overlayImage != nil) { _, hasImage in
            // Adding or removing an image (picker, Library, Remove, Undo) always shows the
            // controls, so a hidden state can't carry over to the next image or the welcome card
            if !showingControls {
                withAnimation(.easeInOut(duration: 0.25)) { showingControls = true }
            }
            let key = "hasShownPlacementHint"
            guard hasImage, !UserDefaults.standard.bool(forKey: key) else { return }
            UserDefaults.standard.set(true, forKey: key)
            showToast(ToastMessage(icon: "hand.draw.fill", text: "Drag, pinch & rotate to place it · then tap Lock",
                                   tint: Theme.accent, duration: 3.5))
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $viewModel.selectedImageFromGallery) // Use the property that clears loadedImageName
        }
        .sheet(isPresented: $viewModel.showingSavedImages, onDismiss: {
            showingImageControls = false // Ensure the main menu can be opened
        }) {
            SavedImagesView(viewModel: viewModel, storage: viewModel.imageStorage, isPresented: $viewModel.showingSavedImages,
                            onLoaded: {
                                showToast(ToastMessage(icon: "checkmark.circle.fill", text: "Reference loaded", tint: Theme.accent))
                            })
        }
    }

    private func toggleControls() {
        // Nothing to hide for on the welcome screen: hiding the card there left a blank screen
        guard viewModel.overlayImage != nil else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            showingControls.toggle()
            if !showingControls {
                showingImageControls = false
            }
        }
    }

    // MARK: - Actions

    private func lock() {
        guard !viewModel.isPropertiesLocked else { return }
        withAnimation(Theme.spring) {
            viewModel.isPropertiesLocked = true
            showingImageControls = false
        }
        Haptics.medium()
        showToast(ToastMessage(icon: "lock.fill",
                               text: "Locked · drag & pinch to move the view. Hold the lock to unlock.",
                               tint: Theme.accent, duration: 3.5))
    }

    private func unlock() {
        guard viewModel.isPropertiesLocked else { return }
        withAnimation(Theme.spring) {
            viewModel.isPropertiesLocked = false
        }
        Haptics.rigid()
        showToast(ToastMessage(icon: "lock.open.fill", text: "Unlocked · edit your reference"))
    }

    /// A plain tap on the lock while locked: explain how to unlock.
    private func holdToUnlockHint() {
        Haptics.light()
        showToast(ToastMessage(icon: "lock.fill", text: "Hold to unlock", tint: Theme.accent, duration: 3.5))
    }

    private func changeImageWhileLocked() {
        Haptics.warning()
        showToast(ToastMessage(icon: "lock.fill", text: "Unlock to change image", tint: Theme.accent))
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
        // Saving over the reference that was loaded from the Library updates that entry
        let isUpdate = viewModel.imageStorage.loadedImageName.map { name in
            viewModel.imageStorage.savedConfigurations.contains { $0.imageName == name }
        } ?? false
        if viewModel.saveCurrentConfiguration(cameraZoom: zoom) {
            Haptics.success()
            showToast(ToastMessage(icon: "checkmark.circle.fill",
                                   text: isUpdate ? "Updated in Library" : "Saved to Library",
                                   tint: Theme.accent))
        } else {
            Haptics.warning()
            showToast(ToastMessage(icon: "exclamationmark.triangle.fill", text: "Couldn't save the image", tint: Theme.danger))
        }
    }

    private func lockedWarning() {
        Haptics.warning()
        showToast(ToastMessage(icon: "lock.fill", text: "Unlock to edit", tint: Theme.accent))
    }

    private func removeImage() {
        guard let removed = viewModel.removeOverlayImage() else { return }
        withAnimation(Theme.spring) { showingImageControls = false }
        showToast(ToastMessage(icon: "trash", text: "Image removed", duration: 8, actionTitle: "Undo") {
            viewModel.restore(removed)
            Haptics.light()
        })
    }

    private func performToastAction() {
        guard let message = toast else { return }
        toast = nil
        message.action?()
    }

    private func showToast(_ message: ToastMessage) {
        lastToast = message
        UIAccessibility.post(notification: .announcement, argument: message.text)
        // The countdown starts once the toast has actually animated in, not when it was
        // requested: right after a ⋯ menu action (Remove Image) the menu is still closing and the
        // toast can appear much later, which used to leave almost no time to tap Undo.
        withAnimation(Theme.spring, completionCriteria: .logicallyComplete) {
            toast = message
        } completion: {
            DispatchQueue.main.asyncAfter(deadline: .now() + message.duration) {
                if toast?.id == message.id { toast = nil }
            }
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
            // Each amber guide sits on a thin dark line so it stays visible over white paper

            // Vertical center line
            if showVerticalIndicator {
                ZStack {
                    Rectangle().fill(Color.black.opacity(0.35)).frame(width: 4)
                    Rectangle().fill(Theme.accent.opacity(0.9)).frame(width: 2)
                }
                .position(x: screenCenter.x, y: screenCenter.y)
                .animation(.easeInOut(duration: 0.2), value: showVerticalIndicator)
            }

            // Horizontal center line
            if showHorizontalIndicator {
                ZStack {
                    Rectangle().fill(Color.black.opacity(0.35)).frame(height: 4)
                    Rectangle().fill(Theme.accent.opacity(0.9)).frame(height: 2)
                }
                .position(x: screenCenter.x, y: screenCenter.y)
                .animation(.easeInOut(duration: 0.2), value: showHorizontalIndicator)
            }

            // Center dot
            if showVerticalIndicator || showHorizontalIndicator {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                    .position(x: screenCenter.x, y: screenCenter.y)
                    .animation(.easeInOut(duration: 0.2), value: showVerticalIndicator || showHorizontalIndicator)
            }
        }
        .allowsHitTesting(false) // Allow gestures to pass through
    }
}
