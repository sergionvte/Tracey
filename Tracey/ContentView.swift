// ContentView.swift - Tracing screen: camera + reference overlay with floating Liquid Glass controls
import SwiftUI
import UIKit
import Photos

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @StateObject private var timelapse = TimelapseController()
    @State private var timelapseAlert: TimelapseAlert?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingImagePicker = false
    @State private var showingSettings = false
    /// The crop screen, while open
    @State private var cropSession: CropSession?
    /// Looking for the sheet in the camera
    @State private var isFittingSheet = false
    /// "How to Use Tracey" from Settings: the tour opens once the sheet is gone
    @State private var tourAfterSettings = false
    @State private var showingControls = true
    @State private var showingImageControls = false // New state for image controls
    @State private var cameraUIView: CameraUIView? = nil // Reference to camera view
    /// The toast on screen (nil = hidden)
    @State private var toast: ToastMessage? = nil
    /// Last toast shown; keeps the content while it fades out
    @State private var lastToast: ToastMessage? = nil
    /// Plain toasts waiting behind a toast with a button
    @State private var queuedToasts: [(message: ToastMessage, queuedAt: Date)] = []
    /// Where the toast is on screen (global), so the camera view ignores taps on an action toast
    @State private var toastFrame: CGRect = .zero
    /// The camera-access banner was dismissed (for this session)
    @State private var isCameraBannerDismissed = false
    /// A reference was picked in the Library; confirm once the sheet has closed
    @State private var pendingReferenceLoadedToast = false
    /// First-launch tour (also reopened from the welcome card and the ⋯ menu). Read once at
    /// launch so the first frame already shows the tour, not the welcome card.
    @State private var isTourPresented = !UserDefaults.standard.bool(forKey: ContentView.hasSeenTourKey)
    @State private var tourPage = 0
    /// Natural heights of the welcome and tour cards (they share the taller one)
    @State private var welcomeCardHeight: CGFloat = 0
    @State private var tourCardHeight: CGFloat = 0
    /// Bottom of the top row (tool column), in the chrome's coordinates
    @State private var topChromeBottom: CGFloat = 0
    private static let chromeSpace = "chrome"
    /// Dock: 68 pt lock button + 8 pt to the bottom safe area
    private static let dockBottomPadding: CGFloat = 8
    /// Space reserved under the toast/panel layer for the dock and the gap above it
    private static let dockReservedHeight: CGFloat = 68 + dockBottomPadding + 12
    private static let hasSeenTourKey = "hasSeenTour"

    // Snap to center configuration
    private let snapThreshold: CGFloat = 30 // Distance in points to activate snap

    var body: some View {
        presentations(on: screen)
    }

    private var screen: some View {
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
                        // The filtered version is drawn; the original stays in overlayImage
                        image: viewModel.displayImage,
                        opacity: viewModel.imageOpacity,
                        scale: viewModel.imageScale,
                        rotation: viewModel.imageRotation,
                        offset: viewModel.imageOffset,
                        isFlipped: viewModel.isFlipped,
                        isFlippedVertically: viewModel.isFlippedVertically,
                        gridDivisions: viewModel.gridDivisions
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
                    onSessionInterruption: { timelapse.setInterrupted($0) },
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
                // Three independent layers, so nothing can push the dock around: the top row,
                // the dock pinned to the bottom safe area, and the toast + Adjust panel floating
                // just above the dock (the panel's height is capped and it scrolls inside).
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        // Hidden in place until there is an image: the welcome card is the only
                        // call to action
                        let hasImage = viewModel.overlayImage != nil
                        VStack(alignment: .leading, spacing: 10) {
                            CaptureModeSwitch(
                                mode: viewModel.captureMode,
                                isLocked: viewModel.isPropertiesLocked,
                                isRecording: timelapse.isActive,
                                onSelect: selectCaptureMode
                            )
                            .opacity(hasImage ? 1 : 0)
                            .allowsHitTesting(hasImage)
                            .accessibilityHidden(!hasImage)

                            // Camera access denied: a compact banner (fades in place) instead of a
                            // card over the middle of the image
                            let showsCameraBanner = viewModel.isCameraAccessDenied && hasImage && !isCameraBannerDismissed
                            CameraAccessBanner(
                                onOpenSettings: {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                },
                                onDismiss: {
                                    withAnimation(Theme.spring) { isCameraBannerDismissed = true }
                                }
                            )
                            .opacity(showsCameraBanner ? 1 : 0)
                            .offset(y: showsCameraBanner ? 0 : -6)
                            .allowsHitTesting(showsCameraBanner)
                            .accessibilityHidden(!showsCameraBanner)
                        }
                        Spacer(minLength: 12)
                        ToolColumn(
                            timelapsePhase: timelapse.phase,
                            isCameraDenied: viewModel.isCameraAccessDenied,
                            onRecord: recordTapped,
                            onRecordWhileDenied: {
                                Haptics.warning()
                                showToast(ToastMessage(icon: "video.slash.fill", text: String(localized: "Camera access is off"), tint: Theme.accent))
                            },
                            isTorchOn: viewModel.isTorchOn,
                            hasImage: viewModel.overlayImage != nil,
                            showsResetView: viewModel.isPropertiesLocked && viewModel.isViewportTransformed,
                            onFocus: {
                                cameraUIView?.focusAtCenter()
                                Haptics.light()
                            },
                            onTorch: {
                                viewModel.toggleTorch()
                                Haptics.light()
                            },
                            onResetView: {
                                viewModel.resetViewport()
                                Haptics.light()
                            },
                            isFittingSheet: isFittingSheet,
                            onFitToSheet: fitToSheetFromButton
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    // Bottom of the top chrome (tool column), to cap the Adjust panel's height
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.chromeSpace)).maxY } action: {
                        topChromeBottom = $0
                    }

                    Spacer(minLength: 0)
                }
                .opacity(showingControls ? 1 : 0)
                .allowsHitTesting(showingControls)
                .accessibilityHidden(isTourPresented)

                // Toast + Adjust panel, bottom-anchored just above the dock
                toastAndAdjustPanel(geometry)

                // Dock pinned to the bottom safe area: its position never depends on the toast,
                // the panel or the text size
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    BottomDock(
                        hasImage: viewModel.overlayImage != nil,
                        isLocked: viewModel.isPropertiesLocked,
                        isRecording: timelapse.isActive,
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
                        onShowTour: openTour,
                        onShowSettings: { showingSettings = true },
                        onRemove: removeImage,
                        onLockedTap: lockedWarning
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, Self.dockBottomPadding)
                }
                .opacity(showingControls ? 1 : 0)
                .allowsHitTesting(showingControls)
                .accessibilityHidden(isTourPresented)

                // Time-lapse status. Its own layer so it stays (at 80%) when the controls are
                // hidden. Second row, left of the tool column: the top row has no room for it
                // next to the Video/Photo switch (which grows with the lock glyph). In immersive
                // mode it moves up to the top-right corner instead of floating mid-screen.
                let showsPill = timelapse.isActive
                TimelapsePill(
                    controller: timelapse,
                    controlsVisible: showingControls,
                    onTap: pillTapped
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, showingControls ? 4 + 58 : 4)
                .padding(.trailing, showingControls ? 16 + 48 + 12 : 16)
                .opacity(showsPill ? (showingControls ? 1 : 0.8) : 0)
                .allowsHitTesting(showsPill)
                .accessibilityHidden(!showsPill || isTourPresented)

                // Welcome card until there is a reference image.
                // Always in the hierarchy (never inserted/removed): if it were removed with a
                // transition while the picker/library sheet covers the screen, SwiftUI can leave
                // the invisible card stuck in the middle swallowing touches, so the new image
                // couldn't be dragged until some other state change. Driving visibility and
                // hit-testing from state makes it stop catching touches immediately.
                let showsWelcome = viewModel.overlayImage == nil && showingControls && !isTourPresented
                // Both cards get the taller one's height, so swapping them doesn't jump
                let sharedCardHeight = min(max(welcomeCardHeight, tourCardHeight), geometry.size.height - 24)
                EmptyStateCard(
                    onImport: { showingImagePicker = true },
                    onLibrary: { viewModel.showingSavedImages = true },
                    onShowTour: openTour,
                    onShowSettings: { showingSettings = true },
                    minHeight: sharedCardHeight,
                    onNaturalHeight: { welcomeCardHeight = $0 }
                )
                .padding(.horizontal, 32)
                // Never taller than the screen: an oversized card (large text) would grow the
                // stack, which GeometryReader pins top-leading, pushing the dock off screen
                .frame(maxHeight: geometry.size.height - 24)
                .opacity(showsWelcome ? 1 : 0)
                .scaleEffect(showsWelcome ? 1 : 0.96)
                .allowsHitTesting(showsWelcome)
                .accessibilityHidden(!showsWelcome)

                // Tour over an image: a scrim that absorbs taps so nothing underneath can be hit
                // (camera and lock state stay as they are). Kept in place and faded.
                let showsTourScrim = isTourPresented && viewModel.overlayImage != nil
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .opacity(showsTourScrim ? 1 : 0)
                    .allowsHitTesting(showsTourScrim)
                    .accessibilityHidden(true)

                // Same spot and style as the welcome card; crossfades with it
                TourCard(page: $tourPage, onFinish: finishTour,
                         maxHeight: geometry.size.height - 24,
                         minHeight: sharedCardHeight,
                         onNaturalHeight: { tourCardHeight = $0 })
                    .padding(.horizontal, 32)
                    .frame(maxHeight: geometry.size.height - 24)
                    .opacity(isTourPresented ? 1 : 0)
                    .scaleEffect(isTourPresented ? 1 : 0.96)
                    .allowsHitTesting(isTourPresented)
                    .accessibilityHidden(!isTourPresented)
            }
            .coordinateSpace(.named(Self.chromeSpace))
            .animation(Theme.spring, value: isTourPresented)
            .animation(Theme.spring, value: timelapse.phase)
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
            timelapse.onAutoStop = { reason in stopTimelapse(reason) }
            timelapse.onResumed = {
                showToast(ToastMessage(icon: "timelapse", text: String(localized: "Time-lapse resumed")))
            }
            #if DEBUG
            // UI tests and screenshots: start with a reference without going through the picker
            if ProcessInfo.processInfo.arguments.contains("-TraceySampleReference"),
               viewModel.overlayImage == nil {
                viewModel.selectedImageFromGallery = UIImage(named: AppIconChoice.notebook.previewImageName)
            }
            #endif
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
            showPlacementHintIfNeeded()
        }
        .onChange(of: viewModel.isCameraAuthorized) { _, _ in showPlacementHintIfNeeded() }
        .onReceive(viewModel.filterFailed) { _ in
            Haptics.warning()
            showToast(ToastMessage(icon: "exclamationmark.triangle.fill", text: String(localized: "Couldn't apply filter"), tint: Theme.danger))
        }
        .onChange(of: scenePhase) { _, phase in
            timelapse.setBackgrounded(phase == .background)
            showPlacementHintIfNeeded()
        }
        .onChange(of: timelapse.phase) { _, phase in
            viewModel.isCaptureModeFrozen = phase != .idle
        }
    }

    /// Alerts, sheets and the crop screen (kept apart from `screen` so the type-checker copes)
    private func presentations(on content: some View) -> some View {
        content
        .alert("Can't save time-lapses", isPresented: alertBinding(.photosDenied)) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow Tracey to add videos to Photos in Settings.")
        }
        .alert("Not enough storage", isPresented: alertBinding(.lowStorage)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Free up at least 1 GB to record a time-lapse.")
        }
        .fullScreenCover(item: $cropSession, content: cropScreen)
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $viewModel.selectedImageFromGallery) // Use the property that clears loadedImageName
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            if tourAfterSettings {
                tourAfterSettings = false
                openTour()
            }
        }) {
            SettingsView(onShowTour: { tourAfterSettings = true })
        }
        .sheet(isPresented: $viewModel.showingSavedImages, onDismiss: {
            showingImageControls = false // Ensure the main menu can be opened
            // Confirm only once the sheet is gone, so the toast isn't animating under it
            if pendingReferenceLoadedToast {
                pendingReferenceLoadedToast = false
                showToast(ToastMessage(icon: "checkmark.circle.fill", text: String(localized: "Reference loaded"), tint: Theme.accent))
            }
        }) {
            SavedImagesView(viewModel: viewModel, storage: viewModel.imageStorage, isPresented: $viewModel.showingSavedImages,
                            onLoaded: { pendingReferenceLoadedToast = true })
        }
    }

    /// One-time hint the first time an image is on screen. Waits until camera access is granted
    /// and the app is active, so the camera permission alert can't hide it; the flag is only set
    /// when the hint is really shown.
    private func showPlacementHintIfNeeded() {
        let key = "hasShownPlacementHint"
        func canShow() -> Bool {
            viewModel.overlayImage != nil && viewModel.isCameraAuthorized
                && UIApplication.shared.applicationState == .active
                && !UserDefaults.standard.bool(forKey: key)
        }
        guard canShow() else { return }
        // Give a just-answered permission alert time to go away
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard canShow() else { return }
            UserDefaults.standard.set(true, forKey: key)
            showToast(ToastMessage(icon: "hand.draw.fill", text: String(localized: "Drag, pinch & rotate to place it · then tap Lock"),
                                   tint: Theme.accent, duration: 3.5))
        }
    }

    private func openTour() {
        tourPage = 0
        withAnimation(Theme.spring) {
            showingImageControls = false // don't stack two glass cards
            isTourPresented = true
        }
    }

    /// Skip or Get Started. The flag is only set here, so quitting mid-tour shows it again.
    private func finishTour() {
        UserDefaults.standard.set(true, forKey: Self.hasSeenTourKey)
        withAnimation(Theme.spring) { isTourPresented = false }
    }

    private func toggleControls() {
        // Nothing to hide for on the welcome screen: hiding the card there left a blank screen
        guard viewModel.overlayImage != nil else { return }
        // With the Adjust panel open, a tap on the screen just closes the panel
        if showingImageControls && showingControls {
            withAnimation(Theme.spring) { showingImageControls = false }
            return
        }
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
                               text: String(localized: "Locked · drag & pinch to move the view. Hold the lock to unlock."),
                               tint: Theme.accent, duration: 3.5))
    }

    private func unlock() {
        guard viewModel.isPropertiesLocked else { return }
        withAnimation(Theme.spring) {
            viewModel.isPropertiesLocked = false
        }
        Haptics.rigid()
        showToast(ToastMessage(icon: "lock.open.fill", text: String(localized: "Unlocked · edit your reference")))
    }

    /// A plain tap on the lock while locked: explain how to unlock.
    private func holdToUnlockHint() {
        Haptics.light()
        showToast(ToastMessage(icon: "lock.fill", text: String(localized: "Hold to unlock"), tint: Theme.accent, duration: 3.5))
    }

    private func changeImageWhileLocked() {
        Haptics.warning()
        showToast(ToastMessage(icon: "lock.fill", text: String(localized: "Unlock to change image"), tint: Theme.accent))
    }

    private func selectCaptureMode(_ mode: CameraCaptureMode) {
        guard mode != viewModel.captureMode else { return }
        // The clip's size is fixed when recording starts
        guard !timelapse.isActive else {
            Haptics.warning()
            showToast(ToastMessage(icon: "timelapse", text: String(localized: "Stop the time-lapse to change camera mode"), tint: Theme.accent))
            return
        }
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
                                   text: isUpdate ? String(localized: "Updated in Library") : String(localized: "Saved to Library"),
                                   tint: Theme.accent))
        } else {
            Haptics.warning()
            showToast(ToastMessage(icon: "exclamationmark.triangle.fill", text: String(localized: "Couldn't save the image"), tint: Theme.danger))
        }
    }

    private func lockedWarning() {
        Haptics.warning()
        showToast(ToastMessage(icon: "lock.fill", text: String(localized: "Unlock to edit"), tint: Theme.accent))
    }

    // MARK: - Crop

    struct CropSession: Identifiable {
        let id = UUID()
        let image: UIImage
        let rect: CGRect
        /// Runs once the crop screen closes (Done or Cancel)
        var then: (() -> Void)?
    }

    /// Opens the crop screen on the full photo. `then` runs when it closes.
    private func openCrop(then: (() -> Void)? = nil) {
        guard !viewModel.isPropertiesLocked else {
            lockedWarning()
            return
        }
        guard let source = viewModel.sourceImage else { return }
        cropSession = CropSession(image: source, rect: viewModel.cropRect, then: then)
    }

    /// Toast and Adjust panel, bottom-anchored just above the dock
    private func toastAndAdjustPanel(_ geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
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
            .padding(.bottom, isToastVisible ? 12 : 0)
            // An invisible toast takes no space
            .frame(height: isToastVisible ? nil : 0, alignment: .bottom)

            // Adjust panel + dock as one item so the hidden panel adds no spacing.
            // The panel is always in the hierarchy and fades/slides in place: removing it
            // with a transition while the ⋯ menu was closing (Remove Image) left an
            // invisible panel over the toast that swallowed the Undo tap.
            let showsAdjust = showingImageControls && viewModel.overlayImage != nil
            let panelMaxHeight = max(160, geometry.size.height - Self.dockReservedHeight - 12 - topChromeBottom)
            AdjustPanel(viewModel: viewModel, isLocked: viewModel.isPropertiesLocked, maxHeight: panelMaxHeight,
                        onCrop: openCropFromPanel)
                .padding(.horizontal, 16)
                // Hidden: takes no height, draws nothing, takes no touches
                .frame(height: showsAdjust ? nil : 0, alignment: .bottom)
                .opacity(showsAdjust ? 1 : 0)
                .offset(y: showsAdjust ? 0 : 24)
                .allowsHitTesting(showsAdjust)
                .accessibilityHidden(!showsAdjust)
        }
        .padding(.bottom, Self.dockReservedHeight)
        .opacity(showingControls ? 1 : 0)
        .allowsHitTesting(showingControls)
        .accessibilityHidden(isTourPresented)
    }

    // MARK: - Fit to sheet

    private func fitToSheetFromButton() { fitToSheet(automatic: false) }

    /// Finds the paper and puts the image on it, with Undo. `automatic` (right after opening an
    /// image) waits longer for the camera to start and says nothing while locked.
    private func fitToSheet(automatic: Bool) {
        guard !isFittingSheet, let image = viewModel.overlayImage, let camera = cameraUIView else { return }
        guard !viewModel.isPropertiesLocked else {
            if !automatic { lockedWarning() }
            return
        }
        isFittingSheet = true
        camera.detectSheetPlacement(imageSize: image.size, currentRotation: viewModel.imageRotation,
                                    timeout: automatic ? 2.5 : 1.2) { placement in
            isFittingSheet = false
            // The image may have changed or been locked while looking
            guard viewModel.overlayImage === image, !viewModel.isPropertiesLocked else { return }
            guard let placement else {
                Haptics.warning()
                showToast(ToastMessage(icon: "doc.viewfinder",
                                       text: String(localized: "Couldn't find the sheet · show all of it, in good light"),
                                       tint: Theme.danger, duration: 3.5))
                return
            }
            let undo = viewModel.applyPlacement(offset: placement.offset, scale: placement.scale, rotation: placement.rotation)
            Haptics.light()
            showToast(ToastMessage(icon: "doc.viewfinder", text: String(localized: "Placed on the sheet"), duration: 8,
                                   actionTitle: String(localized: "Undo"), action: {
                viewModel.undoPlacement(undo)
                Haptics.light()
            }))
        }
    }

    private func openCropFromPanel() { openCrop() }

    private func cropScreen(_ session: CropSession) -> some View {
        CropView(
            image: session.image,
            initialRect: session.rect,
            onCancel: {
                cropSession = nil
                session.then?()
            },
            onDone: { rect in
                cropSession = nil
                applyCrop(rect)
                session.then?()
            }
        )
    }

    private func applyCrop(_ rect: CGRect) {
        let layoutSize = cameraUIView?.overlayLayoutRect.size ?? .zero
        guard let undo = viewModel.applyCrop(rect, layoutSize: layoutSize) else { return }
        Haptics.light()
        showToast(ToastMessage(icon: "crop", text: String(localized: "Image cropped"), duration: 8,
                               actionTitle: String(localized: "Undo"), action: {
            viewModel.undoCrop(undo)
            Haptics.light()
        }))
    }

    private func removeImage() {
        guard let removed = viewModel.removeOverlayImage() else { return }
        withAnimation(Theme.spring) { showingImageControls = false }
        showToast(ToastMessage(icon: "trash", text: String(localized: "Image removed"), duration: 8, actionTitle: String(localized: "Undo"), action: {
            viewModel.restore(removed)
            Haptics.light()
        }))
    }

    // MARK: - Time-lapse

    enum TimelapseAlert {
        case photosDenied
        case lowStorage
    }

    private func alertBinding(_ alert: TimelapseAlert) -> Binding<Bool> {
        Binding(get: { timelapseAlert == alert }, set: { if !$0 { timelapseAlert = nil } })
    }

    private func recordTapped() {
        switch timelapse.phase {
        case .idle: startTimelapse()
        case .recording: stopTimelapse(.user)
        case .saving: break
        }
    }

    /// Tapping the pill: stops with the controls visible; with them hidden it only shows them,
    /// so a stray touch while drawing can't end the recording.
    private func pillTapped() {
        if showingControls {
            if timelapse.phase == .recording { stopTimelapse(.user) }
        } else {
            toggleControls()
        }
    }

    private func startTimelapse() {
        // Ask for (add-only) Photos access up front, so a finished clip is never lost
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            startTimelapseIfEnoughSpace()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                DispatchQueue.main.async {
                    if status == .authorized || status == .limited {
                        startTimelapseIfEnoughSpace()
                    } else {
                        timelapseAlert = .photosDenied
                    }
                }
            }
        default:
            timelapseAlert = .photosDenied
        }
    }

    private func startTimelapseIfEnoughSpace() {
        if let free = TimelapseController.availableSpace(), free < TimelapseController.minimumFreeSpaceToStart {
            timelapseAlert = .lowStorage
            return
        }
        guard let cameraUIView else { return }
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }.first ?? .portrait
        timelapse.start(cameraView: cameraUIView, interfaceOrientation: orientation)
        Haptics.medium()
        showToast(ToastMessage(icon: "timelapse", text: String(localized: "Time-lapse started · 1 frame every 2 s"),
                               tint: Theme.danger, duration: 3.5))
    }

    private func stopTimelapse(_ reason: TimelapseController.StopReason) {
        guard timelapse.phase == .recording else { return }
        timelapse.stop { outcome in
            switch outcome {
            case .saved(let url):
                Haptics.success()
                let (icon, text): (String, String)
                switch reason {
                case .user: (icon, text) = ("checkmark.circle.fill", String(localized: "Time-lapse saved to Photos"))
                case .timeLimit: (icon, text) = ("checkmark.circle.fill", String(localized: "Time-lapse stopped at 3 hours · saved to Photos"))
                case .lowStorage: (icon, text) = ("exclamationmark.triangle.fill", String(localized: "Storage almost full · time-lapse saved to Photos"))
                case .thermal: (icon, text) = ("thermometer.high", String(localized: "Phone is too warm · time-lapse saved to Photos"))
                }
                showToast(ToastMessage(icon: icon, text: text, tint: Theme.accent, duration: 8,
                                       actionTitle: String(localized: "Share"), action: { shareFile(url) }))
            case .tooShort:
                Haptics.warning()
                showToast(ToastMessage(icon: "exclamationmark.triangle.fill",
                                       text: String(localized: "Too short to save · record at least 20 s"), duration: 3.5))
            case .failed(let url):
                Haptics.warning()
                if let url {
                    // Still keepable through the share sheet (Save to Files, AirDrop)
                    showToast(ToastMessage(icon: "exclamationmark.triangle.fill", text: String(localized: "Couldn't save to Photos"),
                                           tint: Theme.danger, duration: 8,
                                           actionTitle: String(localized: "Share"), action: { shareFile(url) }))
                } else {
                    showToast(ToastMessage(icon: "exclamationmark.triangle.fill", text: String(localized: "Couldn't save to Photos"),
                                           tint: Theme.danger, duration: 3.5))
                }
            }
        }
    }

    /// Share sheet for a finished clip; the temporary file is deleted when it closes. (If Share
    /// is never used, the file goes when the next recording starts or at the next launch.)
    private func shareFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        guard var presenter = window?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, _, _, _ in
            if timelapse.lastClipURL == url { timelapse.discardLastClip() }
        }
        if let popover = sheet.popoverPresentationController, let view = presenter.view {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 120, width: 1, height: 1)
        }
        presenter.present(sheet, animated: true)
    }

    private func performToastAction() {
        guard let message = toast else { return }
        dismissToast()
        message.action?()
    }

    /// A toast with a button (Undo, Share) isn't replaced by a plain one: the plain one waits
    /// until it's gone, so a Lock or mode toast can't take away Undo or Share.
    private func showToast(_ message: ToastMessage) {
        if let current = toast, current.actionTitle != nil, message.actionTitle == nil {
            queuedToasts.append((message, Date()))
            if queuedToasts.count > 3 { queuedToasts.removeFirst() }
            return
        }
        presentToast(message)
    }

    private func dismissToast() {
        toast = nil
        // Next queued toast, unless it's no longer relevant
        while let next = queuedToasts.first {
            queuedToasts.removeFirst()
            if Date().timeIntervalSince(next.queuedAt) < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { presentToast(next.message) }
                break
            }
        }
    }

    private func presentToast(_ message: ToastMessage) {
        lastToast = message
        UIAccessibility.post(notification: .announcement, argument: message.text)
        // The countdown starts once the toast has actually animated in, not when it was
        // requested: right after a ⋯ menu action (Remove Image) the menu is still closing and the
        // toast can appear much later, which used to leave almost no time to tap Undo.
        withAnimation(Theme.spring, completionCriteria: .logicallyComplete) {
            toast = message
        } completion: {
            DispatchQueue.main.asyncAfter(deadline: .now() + message.duration) {
                if toast?.id == message.id { dismissToast() }
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
