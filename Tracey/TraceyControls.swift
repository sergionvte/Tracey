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
                    .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color.white)
                                .matchedGeometryEffect(id: "selected", in: selection)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.detail)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .glassSurface(Capsule())
        .opacity(isLocked ? 0.5 : 1)
        .animation(Theme.spring, value: mode)
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
                    GlassIconButton(systemName: "viewfinder", label: "Focus center", action: onFocus)
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
                        systemName: "arrow.down.right.and.arrow.up.left",
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
    let onToggleLock: () -> Void
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
                DockIconButton(systemName: "photo.badge.plus", label: "Choose image", action: onImport)
                DockIconButton(systemName: "square.grid.2x2", label: "Library", action: onLibrary)
            }
            .padding(5)
            .glassSurface(Capsule())
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Center: the key action while tracing
            LockButton(isLocked: isLocked, action: onToggleLock)

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
            .glassSurface(Capsule())
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
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .accessibilityLabel("More")
    }
}

struct LockButton: View {
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isLocked ? Color.black : Color.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 68, height: 68)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassSurface(Circle(), tint: isLocked ? Theme.accent : nil, interactive: true)
        .accessibilityLabel(isLocked ? "Unlock image" : "Lock image")
    }
}

// MARK: - Adjust panel

struct AdjustPanel: View {
    @ObservedObject var viewModel: CameraViewModel
    let isLocked: Bool

    var body: some View {
        VStack(spacing: 18) {
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
                value: "\(Int(viewModel.imageOpacity * 100))%"
            ) {
                Slider(value: $viewModel.imageOpacity, in: 0...1)
            }

            // Size and rotation would break the alignment with the paper, so only these are
            // disabled while locked; opacity stays live.
            VStack(spacing: 18) {
                AdjustRow(
                    icon: "arrow.up.left.and.arrow.down.right",
                    title: "Size",
                    value: String(format: "%.1f×", viewModel.imageScale)
                ) {
                    Slider(value: $viewModel.imageScale, in: 0.1...5.0)
                }

                AdjustRow(
                    icon: "rotate.right",
                    title: "Rotation",
                    value: "\(Int(viewModel.imageRotation.isFinite ? viewModel.imageRotation : 0))°"
                ) {
                    Slider(value: $viewModel.imageRotation, in: 0...360)
                }

            }
            .disabled(isLocked)
            .opacity(isLocked ? 0.45 : 1)
        }
        .tint(Theme.accent)
        .padding(20)
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
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            }
            control
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
                    Label("Open Library", systemImage: "square.grid.2x2")
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
