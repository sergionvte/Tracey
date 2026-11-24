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
        case .video: return String(localized: "Video")
        case .photo: return String(localized: "Photo")
        }
    }

    var detail: String {
        switch self {
        case .video: return String(localized: "Video mode · smoother preview")
        case .photo: return String(localized: "Photo mode · wider frame")
        }
    }
}

// MARK: - Capture mode switch (top left)

struct CaptureModeSwitch: View {
    let mode: CameraCaptureMode
    let isLocked: Bool
    /// Recording a time-lapse: the clip's size is fixed, so the switch is blocked
    var isRecording = false
    let onSelect: (CameraCaptureMode) -> Void
    @Namespace private var selection

    var body: some View {
        let isBlocked = isLocked || isRecording
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
                    .foregroundStyle(isSelected ? Color.black.opacity(isBlocked ? 0.6 : 1)
                                                : Color.white.opacity(isBlocked ? 0.4 : 0.85))
                    .shadow(color: .black.opacity(isSelected ? 0 : 0.45), radius: 1.5, x: 0, y: 1)
                    .padding(.horizontal, 14)
                    // 44 pt tall touch target; the selected pill stays 36 pt
                    .frame(height: 44)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color.white.opacity(isBlocked ? 0.55 : 1))
                                .padding(.vertical, 4)
                                .matchedGeometryEffect(id: "selected", in: selection)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.detail)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(isLocked ? String(localized: "Unlock to change the camera mode.")
                                   : isRecording ? String(localized: "Stop the time-lapse to change the camera mode.") : "")
            }

            // Why it's blocked: lock, or time-lapse. Collapses to nothing otherwise (kept in
            // place, no insertion)
            Image(systemName: isLocked ? "lock.fill" : "timelapse")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isLocked ? Theme.accent : Theme.danger)
                .glyphShadow()
                .frame(width: isBlocked ? 22 : 0)
                .opacity(isBlocked ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
        .glassSurface(Capsule(), tint: Theme.controlTint)
        .animation(Theme.spring, value: mode)
        .animation(Theme.spring, value: isLocked)
        .animation(Theme.spring, value: isRecording)
    }
}

// MARK: - Tool column (top right)

struct ToolColumn: View {
    let timelapsePhase: TimelapseController.Phase
    /// Camera access is off: recording is impossible
    let isCameraDenied: Bool
    let onRecord: () -> Void
    let onRecordWhileDenied: () -> Void
    let isTorchOn: Bool
    let hasImage: Bool
    let showsResetView: Bool
    let onFocus: () -> Void
    let onTorch: () -> Void
    let onResetView: () -> Void

    var body: some View {
        GlassGroup(spacing: 10) {
            VStack(spacing: 10) {
                // The camera only runs once there is an image, so camera tools appear with it
                if hasImage {
                    // Time-lapse: first item; stays enabled while locked
                    RecordButton(
                        phase: timelapsePhase,
                        isEnabled: !isCameraDenied,
                        onDisabledTap: onRecordWhileDenied,
                        action: onRecord
                    )
                    .transition(.scale.combined(with: .opacity))

                    // Focus-point brackets: reads as camera focus (Center Image keeps `scope`)
                    GlassIconButton(systemName: "dot.viewfinder", label: String(localized: "Focus center"), action: onFocus)
                        .transition(.scale.combined(with: .opacity))

                    GlassIconButton(
                        systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                        label: isTorchOn ? String(localized: "Turn light off") : String(localized: "Turn light on"),
                        isActive: isTorchOn,
                        action: onTorch
                    )
                    .transition(.scale.combined(with: .opacity))
                    // Mirroring lives in the Adjust panel, next to size and rotation
                }

                if showsResetView {
                    GlassIconButton(
                        systemName: "arrow.counterclockwise",
                        label: String(localized: "Reset view"),
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
    /// A time-lapse is recording: the image can't be removed (the camera would turn off)
    let isRecording: Bool
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
    let onShowTour: () -> Void
    let onShowSettings: () -> Void
    let onRemove: () -> Void
    let onLockedTap: () -> Void

    var body: some View {
        // No GlassEffectContainer here: the three pieces don't need to morph together, and
        // inside a container the glass ignores opacity (it couldn't fade out in place).
        HStack(spacing: 14) {
            // Left: get a reference
            HStack(spacing: 2) {
                // Changing the image while locked would throw the alignment away
                DockIconButton(systemName: "photo.badge.plus", label: String(localized: "Choose image"),
                               isEnabled: !isLocked, onDisabledTap: onChangeImageWhileLocked, action: onImport)
                DockIconButton(systemName: "photo.stack", label: String(localized: "Library"),
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
                    label: String(localized: "Adjust image"),
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
            Button("How to Use Tracey", systemImage: "questionmark.circle", action: onShowTour)
            Button("Settings", systemImage: "gearshape", action: onShowSettings)
            Divider()
            Button("Remove Image", systemImage: "trash", role: .destructive, action: onRemove)
                .disabled(isLocked || isRecording)
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
                // The pressed glass turns almost white, so the ring is amber on a dark edge
                ZStack {
                    Circle()
                        .stroke(Color.black.opacity(0.3), lineWidth: 6)
                    Group {
                        Circle()
                            .trim(from: 0, to: holdProgress)
                            .stroke(Color.black.opacity(0.6), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        Circle()
                            .trim(from: 0, to: holdProgress)
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    }
                    .rotationEffect(.degrees(-90))
                }
                // Outside the pressed glass, which grows a little while held
                .padding(-11)
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
            .accessibilityLabel(isLocked ? String(localized: "Unlock image") : String(localized: "Lock image"))
            .accessibilityHint(isLocked ? String(localized: "Touch and hold to unlock.") : String(localized: "Fixes the image to the camera."))
            // VoiceOver activation is already deliberate: it unlocks without the hold
            .accessibilityAction { if isLocked { onUnlock() } else { onLock() } }
    }
}

// MARK: - Adjust panel

struct AdjustPanel: View {
    @ObservedObject var viewModel: CameraViewModel
    let isLocked: Bool
    /// Room between the top chrome and the dock; taller content scrolls inside
    var maxHeight: CGFloat = .infinity

    @State private var contentHeight: CGFloat = 0

    /// Model rotation (0..<360) shown as −180…180
    private var signedRotation: Double {
        let rotation = viewModel.imageRotation.isFinite ? viewModel.imageRotation : 0
        return rotation > 180 ? rotation - 360 : rotation
    }

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(contentHeight, 1), maxHeight))
        .tint(Theme.accent)
        .frame(maxWidth: 440)
        // Slightly darker glass so labels stay readable over a busy reference or bright paper
        .glassSurface(RoundedRectangle(cornerRadius: 30, style: .continuous), tint: .black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        // Taps on the panel background must not hide the controls
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture {}
    }

    private var content: some View {
        VStack(spacing: 10) {
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
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, maxHeight: isLocked ? nil : 0, alignment: .topLeading)
                    .opacity(isLocked ? 1 : 0)
                    .clipped()
                    .accessibilityHidden(!isLocked)
            }

            // Filters never change size or position, so they stay available while locked
            FilterPicker(
                selected: viewModel.referenceFilter,
                thumbnails: viewModel.filterThumbnails,
                onSelect: { filter in
                    Haptics.light()
                    viewModel.selectFilter(filter)
                }
            )

            AdjustRow(
                icon: "circle.lefthalf.filled",
                title: String(localized: "Opacity"),
                value: "\(Int(viewModel.imageOpacity * 100))%",
                onReset: { viewModel.imageOpacity = CameraViewModel.defaultOpacity }
            ) {
                Slider(value: $viewModel.imageOpacity, in: 0...1)
            }

            // Size and rotation would break the alignment with the paper, so only these are
            // disabled while locked; opacity stays live.
            VStack(spacing: 10) {
                AdjustRow(
                    icon: "arrow.up.left.and.arrow.down.right",
                    title: String(localized: "Size"),
                    value: String(format: "%.1f×", viewModel.imageScale),
                    onReset: { viewModel.imageScale = 1.0 }
                ) {
                    Slider(value: $viewModel.imageScale, in: 0.1...5.0)
                }

                AdjustRow(
                    icon: "rotate.right",
                    title: String(localized: "Rotation"),
                    value: "\(Int(signedRotation.rounded()))°",
                    onReset: { viewModel.imageRotation = 0 }
                ) {
                    // −180…180 centered on 0; the model keeps 0..<360
                    Slider(value: Binding(
                        get: { signedRotation },
                        set: { viewModel.imageRotation = $0 < 0 ? $0 + 360 : $0 }
                    ), in: -180...180)
                }

                MirrorRow(
                    horizontal: viewModel.isFlipped,
                    vertical: viewModel.isFlippedVertically,
                    onHorizontal: { viewModel.flipOverlayImage() },
                    onVertical: { viewModel.flipOverlayImageVertically() }
                )
            }
            .disabled(isLocked)
            .opacity(isLocked ? 0.45 : 1)

            // Attached to the image; available while locked
            GridRow(divisions: $viewModel.gridDivisions)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// Four tiles with a live preview of the reference under each filter.
private struct FilterPicker: View {
    let selected: ReferenceFilter
    let thumbnails: [ReferenceFilter: UIImage]
    let onSelect: (ReferenceFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "camera.filters")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 20)
                Text("Filter")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 8) {
                ForEach(ReferenceFilter.allCases) { filter in
                    FilterTile(
                        filter: filter,
                        thumbnail: thumbnails[filter],
                        isSelected: filter == selected,
                        action: { onSelect(filter) }
                    )
                }
            }
        }
    }
}

private struct FilterTile: View {
    let filter: ReferenceFilter
    let thumbnail: UIImage?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    // Paper-like backdrop: the Outline preview is lines on transparent
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.85))
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.black.opacity(0.5))
                    }
                }
                .frame(width: 40, height: 40)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.accent, lineWidth: 2)
                        .padding(-2)
                        .opacity(isSelected ? 1 : 0)
                }

                Text(filter.label)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Color.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.accessibilityName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Grid: Off | 3×3 | 4×4 as a native segmented control across the row (44 pt tall).
private struct GridRow: View {
    @Binding var divisions: Int
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let label = HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20)
                .accessibilityHidden(true)
            Text("Grid")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        Group {
            if typeSize >= .xLarge {
                // Large text: the segments get the full width under the label
                VStack(alignment: .leading, spacing: 6) {
                    label
                    picker
                }
            } else {
                HStack(spacing: 10) {
                    label
                    picker
                }
            }
        }
        .onChange(of: divisions) { _, _ in Haptics.light() }
    }

    private var picker: some View {
        Picker("Grid", selection: $divisions) {
            Text("Off").tag(0).accessibilityLabel("Off")
            Text("3×3").tag(3).accessibilityLabel("3 by 3")
            Text("4×4").tag(4).accessibilityLabel("4 by 4")
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// Two independent toggles: mirror left↔right and top↔bottom
private struct MirrorRow: View {
    let horizontal: Bool
    let vertical: Bool
    let onHorizontal: () -> Void
    let onVertical: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize >= .xLarge {
                VStack(alignment: .leading, spacing: 6) {
                    label
                    toggles
                }
            } else {
                HStack(spacing: 10) {
                    label
                    toggles
                }
            }
        }
    }

    private var label: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20)
            Text("Mirror")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 66, alignment: .leading)
        }
        .accessibilityHidden(true)
    }

    private var toggles: some View {
        HStack(spacing: 8) {
            toggle(String(localized: "Horizontal"),
                   accessibility: String(localized: "Mirror horizontally"),
                   icon: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                   isOn: horizontal, action: onHorizontal)
            toggle(String(localized: "Vertical"),
                   accessibility: String(localized: "Mirror vertically"),
                   icon: "arrow.up.and.down.righttriangle.up.righttriangle.down",
                   isOn: vertical, action: onVertical)
        }
    }

    private func toggle(_ title: String, accessibility: String, icon: String, isOn: Bool,
                        action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(isOn ? Color.black : Color.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isOn ? Theme.accent : Color.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize >= .xLarge {
                // Large text: label line above the slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        iconView
                        titleView
                        Spacer()
                        valueView
                    }
                    control
                }
            } else {
                // One compact line: icon, label, slider, value
                HStack(spacing: 10) {
                    iconView
                    titleView
                        .frame(width: 66, alignment: .leading)
                    control
                    valueView
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Reset \(title)") {
            if isEnabled { onReset() }
        }
    }

    private var iconView: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: 20)
    }

    private var titleView: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private var valueView: some View {
        Text(value)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
            .contentTransition(.numericText())
            // Generous hit area for the double-tap reset
            .padding(.vertical, 6)
            .padding(.leading, 12)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard isEnabled else { return }
                withAnimation(.easeOut(duration: 0.2)) { onReset() }
                Haptics.light()
            }
            .padding(.vertical, -6)
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
    let onShowTour: () -> Void
    let onShowSettings: () -> Void
    /// Matches the tour card's height so the crossfade doesn't jump
    var minHeight: CGFloat = 0
    /// Reports the card's own height (before `minHeight`)
    var onNaturalHeight: (CGFloat) -> Void = { _ in }

    var body: some View {
        // At very large text sizes the card scrolls instead of growing past the screen
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onNaturalHeight($0) }
        .frame(maxWidth: 360, minHeight: minHeight)
        .glassSurface(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .onTapGesture {}
    }

    private var content: some View {
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
                    .multilineTextAlignment(.center)
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

                // Side by side; stacked when large text doesn't fit on one line
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { footerLinks }
                    VStack(spacing: 0) { footerLinks }
                }
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var footerLinks: some View {
        Button(action: onShowTour) {
            footerLabel("How Tracey works")
        }
        .buttonStyle(.plain)
        Button(action: onShowSettings) {
            footerLabel("Settings")
        }
        .buttonStyle(.plain)
    }

    private func footerLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white.opacity(0.8))
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 44)
            .contentShape(Rectangle())
    }
}

/// Public pages, opened in the language the app is running in
enum AppLinks {
    private static let base = "https://sergionvte.github.io/Tracey/"
    private static var anchor: String {
        Bundle.main.preferredLocalizations.first == "es" ? "" : "#en"
    }
    static var privacy: URL { URL(string: base + "privacidad.html" + anchor)! }
    static var support: URL { URL(string: base + "soporte.html" + anchor)! }
}

// MARK: - Camera access

/// Compact banner under the top bar when the camera should run but access is denied or
/// restricted. Small on purpose: it must not cover the image or block gestures.
struct CameraAccessBanner: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .glyphShadow()
                .accessibilityHidden(true)
            Text("Camera access is off")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .glyphShadow()
            Button(action: onOpenSettings) {
                Text("Settings")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Theme.accent, in: Capsule())
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Settings to turn on camera access")
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .glyphShadow()
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(height: 44)
        .glassSurface(Capsule(), tint: Theme.controlTint)
        .accessibilityElement(children: .contain)
    }
}
