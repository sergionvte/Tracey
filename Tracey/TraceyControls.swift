//
//  TraceyControls.swift
//  Tracey
//
//  Floating Liquid Glass controls for the tracing screen. Kept minimal so the paper and
//  the reference image stay the focus; everything is reachable with a thumb.
//

import SwiftUI

extension CameraCaptureMode {
    var shortTitle: String {
        switch self {
        case .video: return "Video"
        case .photo: return "Photo"
        }
    }

    var detail: String {
        switch self {
        case .video: return "Video mode · smoother preview"
        case .photo: return "Photo mode · wider frame"
        }
    }
}

// MARK: - Capture mode switch (top left)

struct CaptureModeSwitch: View {
    let mode: CameraCaptureMode
    let isLocked: Bool
    let onSelect: (CameraCaptureMode) -> Void
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CameraCaptureMode.allCases, id: \.self) { option in
                let isSelected = option == mode
                Button {
                    onSelect(option)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.iconName)
                            .font(.system(size: 12, weight: .semibold))
                        Text(option.shortTitle)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    // Locked: only the segments dim (the glass stays readable) + a lock glyph
                    .foregroundStyle(isSelected ? Color.black.opacity(isLocked ? 0.6 : 1)
                                                : Color.white.opacity(isLocked ? 0.4 : 0.85))
                    .shadow(color: .black.opacity(isSelected ? 0 : 0.45), radius: 1.5, x: 0, y: 1)
                    .padding(.horizontal, 14)
                    // 44 pt tall touch target; the selected pill stays 36 pt
                    .frame(height: 44)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color.white.opacity(isLocked ? 0.55 : 1))
                                .padding(.vertical, 4)
                                .matchedGeometryEffect(id: "selected", in: selection)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.detail)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(isLocked ? "Unlock to change the camera mode." : "")
            }

            // Collapses to nothing while unlocked (kept in place, no insertion)
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
                .glyphShadow()
                .frame(width: isLocked ? 22 : 0)
                .opacity(isLocked ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
        .glassSurface(Capsule(), tint: Theme.controlTint)
        .animation(Theme.spring, value: mode)
        .animation(Theme.spring, value: isLocked)
    }
}

// MARK: - Tool column (top right)

struct ToolColumn: View {
    let isTorchOn: Bool
    let isFlipped: Bool
    let hasImage: Bool
    let isLocked: Bool
    let showsResetView: Bool
    let onFocus: () -> Void
    let onTorch: () -> Void
    let onFlip: () -> Void
    let onLockedTap: () -> Void
    let onResetView: () -> Void

    var body: some View {
        GlassGroup(spacing: 10) {
            VStack(spacing: 10) {
                // The camera only runs once there is an image, so camera tools appear with it
                if hasImage {
                    // Focus-point brackets: reads as camera focus (Center Image keeps `scope`)
                    GlassIconButton(systemName: "dot.viewfinder", label: "Focus center", action: onFocus)
                        .transition(.scale.combined(with: .opacity))

                    GlassIconButton(
                        systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                        label: isTorchOn ? "Turn light off" : "Turn light on",
                        isActive: isTorchOn,
                        action: onTorch
                    )
                    .transition(.scale.combined(with: .opacity))

                    GlassIconButton(
                        systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                        label: "Mirror image",
                        isActive: isFlipped,
                        isEnabled: !isLocked,
                        onDisabledTap: onLockedTap,
                        action: onFlip
                    )
                    .transition(.scale.combined(with: .opacity))
                }

                if showsResetView {
                    GlassIconButton(
                        systemName: "arrow.counterclockwise",
                        label: "Reset view",
                        isActive: true,
                        action: onResetView
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(Theme.spring, value: showsResetView)
        .animation(Theme.spring, value: hasImage)
    }
}

// MARK: - Bottom dock

struct BottomDock: View {
    let hasImage: Bool
    let isLocked: Bool
    let isAdjustOpen: Bool
    let onImport: () -> Void
    let onLibrary: () -> Void
    let onLock: () -> Void
    let onUnlock: () -> Void
    let onLockTapWhileLocked: () -> Void
    /// Choose image / Library while locked
    let onChangeImageWhileLocked: () -> Void
    let onAdjust: () -> Void
    let onCenter: () -> Void
    let onSave: () -> Void
    let onRemove: () -> Void
    let onLockedTap: () -> Void

    var body: some View {
        // No GlassEffectContainer here: the three pieces don't need to morph together, and
        // inside a container the glass ignores opacity (it couldn't fade out in place).
        HStack(spacing: 14) {
            // Left: get a reference
            HStack(spacing: 2) {
                // Changing the image while locked would throw the alignment away
                DockIconButton(systemName: "photo.badge.plus", label: "Choose image",
                               isEnabled: !isLocked, onDisabledTap: onChangeImageWhileLocked, action: onImport)
                DockIconButton(systemName: "photo.stack", label: "Library",
                               isEnabled: !isLocked, onDisabledTap: onChangeImageWhileLocked, action: onLibrary)
            }
            .padding(5)
            .glassSurface(Capsule(), tint: Theme.controlTint)
            // No image yet: the welcome card is the only call to action. Faded in place so the
            // dock keeps its layout.
            .opacity(hasImage ? 1 : 0)
            .allowsHitTesting(hasImage)
            .accessibilityHidden(!hasImage)
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Center: the key action while tracing
            LockButton(isLocked: isLocked, onLock: onLock, onUnlock: onUnlock, onLockedTap: onLockTapWhileLocked)
                .opacity(hasImage ? 1 : 0)
                .scaleEffect(hasImage ? 1 : 0.85)
                .allowsHitTesting(hasImage)
                .accessibilityHidden(!hasImage)

            // Right: edit the reference. Always in the hierarchy and only faded when there is
            // no image: removing it (right as the ⋯ menu it hosts closes, e.g. "Remove Image")
            // made the glass capsule slide down off screen.
            HStack(spacing: 2) {
                // Stays enabled while locked: opacity can still be changed mid-trace
                DockIconButton(
                    systemName: "slider.horizontal.3",
                    label: "Adjust image",
                    isActive: isAdjustOpen,
                    action: onAdjust
                )
                moreMenu
            }
            .padding(5)
            .glassSurface(Capsule(), tint: Theme.controlTint)
            .opacity(hasImage ? 1 : 0)
            .scaleEffect(hasImage ? 1 : 0.85)
            .allowsHitTesting(hasImage)
            .accessibilityHidden(!hasImage)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(Theme.spring, value: hasImage)
    }

    private var moreMenu: some View {
        Menu {
            Button("Center Image", systemImage: "scope", action: onCenter)
                .disabled(isLocked)
            Button("Save to Library", systemImage: "square.and.arrow.down", action: onSave)
            Divider()
            Button("Remove Image", systemImage: "trash", role: .destructive, action: onRemove)
                .disabled(isLocked)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .glyphShadow()
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .accessibilityLabel("More")
    }
}

/// Locking is a single tap. Unlocking needs a deliberate press and hold (a ring fills up), so
/// a stray touch while drawing can't undo the alignment; a plain tap just explains that.
struct LockButton: View {
    let isLocked: Bool
    let onLock: () -> Void
    let onUnlock: () -> Void
    /// Plain tap while locked
    let onLockedTap: () -> Void

    @State private var holdProgress: CGFloat = 0
    private let holdDuration: Double = 0.6

    var body: some View {
        Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(isLocked ? Color.black : Color.white)
            .contentTransition(.symbolEffect(.replace))
            .shadow(color: .black.opacity(isLocked ? 0 : 0.45), radius: 1.5, x: 0, y: 1)
            .frame(width: 68, height: 68)
            .contentShape(Circle())
            .glassSurface(Circle(), tint: isLocked ? Theme.accent : Theme.controlTint, interactive: true)
            .overlay {
                // Hold-to-unlock progress ring, just outside the button
                ZStack {
                    Circle()
                        .stroke(Color.black.opacity(0.35), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: holdProgress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(-6)
                .opacity(holdProgress > 0 ? 1 : 0)
                .allowsHitTesting(false)
            }
            .onTapGesture {
                if isLocked { onLockedTap() } else { onLock() }
            }
            .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 40) {
                if isLocked { onUnlock() } else { onLock() }
            } onPressingChanged: { pressing in
                if pressing && isLocked {
                    withAnimation(.linear(duration: holdDuration)) { holdProgress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
                }
            }
            // The ring belongs to the locked state: clear it as soon as it unlocks, even while
            // the finger is still down
            .onChange(of: isLocked) { _, locked in
                if !locked { withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 } }
            }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isLocked ? "Unlock image" : "Lock image")
            .accessibilityHint(isLocked ? "Touch and hold to unlock." : "Fixes the image to the camera.")
            // VoiceOver activation is already deliberate: it unlocks without the hold
            .accessibilityAction { if isLocked { onUnlock() } else { onLock() } }
    }
}

// MARK: - Adjust panel

struct AdjustPanel: View {
    @ObservedObject var viewModel: CameraViewModel
    let isLocked: Bool

    /// Model rotation (0..<360) shown as −180…180
    private var signedRotation: Double {
        let rotation = viewModel.imageRotation.isFinite ? viewModel.imageRotation : 0
        return rotation > 180 ? rotation - 360 : rotation
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Adjust")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    if isLocked {
                        Label("Locked", systemImage: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                // Collapses to nothing while unlocked (kept in place, no insertion)
                Text("Unlock to resize or rotate")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, maxHeight: isLocked ? nil : 0, alignment: .topLeading)
                    .opacity(isLocked ? 1 : 0)
                    .clipped()
                    .accessibilityHidden(!isLocked)
            }

            AdjustRow(
                icon: "circle.lefthalf.filled",
                title: "Opacity",
                value: "\(Int(viewModel.imageOpacity * 100))%",
                onReset: { viewModel.imageOpacity = 0.6 }
            ) {
                Slider(value: $viewModel.imageOpacity, in: 0...1)
            }

            // Size and rotation would break the alignment with the paper, so only these are
            // disabled while locked; opacity stays live.
            VStack(spacing: 14) {
                AdjustRow(
                    icon: "arrow.up.left.and.arrow.down.right",
                    title: "Size",
                    value: String(format: "%.1f×", viewModel.imageScale),
                    onReset: { viewModel.imageScale = 1.0 }
                ) {
                    Slider(value: $viewModel.imageScale, in: 0.1...5.0)
                }

                AdjustRow(
                    icon: "rotate.right",
                    title: "Rotation",
                    value: "\(Int(signedRotation.rounded()))°",
                    onReset: { viewModel.imageRotation = 0 }
                ) {
                    // −180…180 centered on 0; the model keeps 0..<360
                    Slider(value: Binding(
                        get: { signedRotation },
                        set: { viewModel.imageRotation = $0 < 0 ? $0 + 360 : $0 }
                    ), in: -180...180)
                }
            }
            .disabled(isLocked)
            .opacity(isLocked ? 0.45 : 1)
        }
        .tint(Theme.accent)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: 440)
        // Slightly darker glass so labels stay readable over a busy reference or bright paper
        .glassSurface(RoundedRectangle(cornerRadius: 30, style: .continuous), tint: .black.opacity(0.35))
        // Taps on the panel background must not hide the controls
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture {}
    }
}

private struct AdjustRow<Control: View>: View {
    let icon: String
    let title: String
    let value: String
    /// Double-tap on the value resets the row to its default
    let onReset: () -> Void
    @ViewBuilder var control: Control
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 20)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.numericText())
                    // Generous hit area for the double-tap reset
                    .padding(.vertical, 6)
                    .padding(.leading, 16)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        guard isEnabled else { return }
                        withAnimation(.easeOut(duration: 0.2)) { onReset() }
                        Haptics.light()
                    }
                    .padding(.vertical, -6)
            }
            control
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Reset \(title)") {
            if isEnabled { onReset() }
        }
    }
}

// MARK: - Empty state

/// Calm graphite backdrop with a soft amber glow, shown while the camera is off.
struct IdleBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.11), Color(white: 0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Theme.accent.opacity(0.22), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 420
            )
        }
    }
}

struct EmptyStateCard: View {
    let onImport: () -> Void
    let onLibrary: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(width: 76, height: 76)
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(spacing: 8) {
                Text("Ready to trace")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Pick a reference image. It floats over your camera so you can trace it onto paper.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button(action: onImport) {
                    Label("Choose Image", systemImage: "photo.badge.plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onLibrary) {
                    Label("Open Library", systemImage: "photo.stack")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassSurface(Capsule(), interactive: true)
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .glassSurface(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .onTapGesture {}
    }
}

// MARK: - Camera access

/// Shown when the camera should run but access is denied or restricted.
struct CameraAccessCard: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Camera access is off")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("Tracey needs the camera to show your paper.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onOpenSettings) {
                Label("Open Settings", systemImage: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .glassSurface(RoundedRectangle(cornerRadius: 34, style: .continuous), tint: .black.opacity(0.35))
        // Taps on the card must not hide the controls
        .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .onTapGesture {}
    }
}
