//
//  GlassUI.swift
//  Tracey
//
//  Shared Liquid Glass building blocks. Uses the real iOS 26 glass APIs and falls back
//  to translucent material on earlier systems (deployment target is iOS 18.5).
//

import SwiftUI
import UIKit

// MARK: - Theme

enum Theme {
    /// Warm amber, like a pencil — the one accent color in the app.
    static let accent = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let danger = Color(red: 1.0, green: 0.38, blue: 0.36)
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
    /// Subtle dark tint for floating glass so white glyphs stay readable over white paper
    static let controlTint = Color.black.opacity(0.3)
}

extension View {
    /// Soft shadow under white glyphs/text on glass, for contrast over bright paper.
    func glyphShadow() -> some View {
        shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1)
    }
}

// MARK: - Glass surface

extension View {
    /// Liquid Glass background in `shape`. Optional tint; `interactive` makes it react to touch.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        if let tint { shape.fill(tint.opacity(0.45)) }
                    }
                }
                .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        }
    }
}

@available(iOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

/// Groups glass shapes so they blend and morph together (iOS 26); plain container before.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Buttons

/// Round glass button with an SF Symbol. Disabled buttons still consume the tap
/// (so the screen doesn't toggle the controls) and call `onDisabledTap` instead.
struct GlassIconButton: View {
    let systemName: String
    let label: String
    var isActive = false
    var activeTint: Color = Theme.accent
    var isEnabled = true
    var size: CGFloat = 48
    var onDisabledTap: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Button {
            if isEnabled { action() } else { onDisabledTap?() }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .semibold))
                // Dim the symbol, not the view: glass inside a GlassEffectContainer is drawn by
                // the container and ignores the button's own opacity.
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.35))
                .contentTransition(.symbolEffect(.replace))
                .glyphShadow()
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassSurface(Circle(), tint: isActive && isEnabled ? activeTint : Theme.controlTint, interactive: isEnabled)
        .accessibilityLabel(label)
    }
}

/// Icon button that lives inside a shared glass capsule (no glass of its own).
struct DockIconButton: View {
    let systemName: String
    let label: String
    var isActive = false
    var isEnabled = true
    var onDisabledTap: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Button {
            if isEnabled { action() } else { onDisabledTap?() }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isActive ? Color.black : Color.white.opacity(isEnabled ? 1 : 0.35))
                .shadow(color: .black.opacity(isActive ? 0 : 0.45), radius: 1.5, x: 0, y: 1)
                .frame(width: 48, height: 48)
                .background {
                    if isActive { Circle().fill(Theme.accent) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Toast

struct ToastMessage: Equatable {
    let id = UUID()
    var icon: String
    var text: String
    var tint: Color = .white
    /// Seconds on screen
    var duration: TimeInterval = 2
    /// Optional button in the toast (e.g. "Undo")
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool { lhs.id == rhs.id }
}

struct ToastView: View {
    let message: ToastMessage
    /// Called when the toast's button is tapped
    var onAction: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(message.tint)
            Text(message.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .glyphShadow()
            if let title = message.actionTitle {
                Button(action: onAction) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.leading, 6)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 42)
        .glassSurface(Capsule(), tint: Theme.controlTint)
        .accessibilityElement(children: message.actionTitle == nil ? .combine : .contain)
    }
}

// MARK: - Haptics

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func rigid() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
