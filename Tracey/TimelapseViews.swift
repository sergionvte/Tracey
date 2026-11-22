//
//  TimelapseViews.swift
//  Tracey
//
//  Record button (top of the tool column) and the recording pill that stays on screen.
//

import SwiftUI

/// First item of the tool column. Idle → `timelapse`; recording → red `stop.fill`;
/// saving → spinner (disabled); camera denied → dimmed, tapping explains why.
struct RecordButton: View {
    let phase: TimelapseController.Phase
    /// False while camera access is off
    let isEnabled: Bool
    let onDisabledTap: () -> Void
    let action: () -> Void

    var body: some View {
        let isRecording = phase == .recording
        let isSaving = phase == .saving
        Button {
            if !isEnabled { onDisabledTap() } else if !isSaving { action() }
        } label: {
            ZStack {
                Image(systemName: isRecording ? "stop.fill" : "timelapse")
                    .font(.system(size: 18, weight: .semibold))
                    // Dim the symbol, not the view (glass in a container ignores opacity)
                    .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.35))
                    .contentTransition(.symbolEffect(.replace))
                    .glyphShadow()
                    .opacity(isSaving ? 0 : 1)
                ProgressView()
                    .tint(.white)
                    .opacity(isSaving ? 1 : 0)
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .glassSurface(Circle(), tint: isRecording ? Theme.danger : Theme.controlTint,
                      interactive: isEnabled && !isSaving)
        .accessibilityLabel(isSaving ? "Saving time-lapse" : isRecording ? "Stop time-lapse" : "Start time-lapse")
    }
}

/// Recording status: pulsing dot, elapsed drawing time and clip length. Stays visible (80%)
/// when the controls are hidden. Tapping stops the recording when the controls are visible,
/// and only brings the controls back when they are hidden, so a stray touch can't end it.
struct TimelapsePill: View {
    @ObservedObject var controller: TimelapseController
    let controlsVisible: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dotDimmed = false

    var body: some View {
        // Ticks every second while recording; effectively idle otherwise
        TimelineView(.periodic(from: .now, by: controller.phase == .idle ? 3600 : 1)) { context in
            let elapsed = controller.elapsed(at: context.date)
            Button(action: onTap) {
                HStack(spacing: 6) {
                    indicator
                    content(elapsed: elapsed)
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .glassSurface(Capsule(), tint: .black.opacity(0.45))
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(elapsed: elapsed))
            .accessibilityHint(controlsVisible && controller.phase == .recording ? "Double-tap to stop." : "")
        }
        .onAppear { startPulse() }
        .onChange(of: reduceMotion) { _, _ in startPulse() }
    }

    @ViewBuilder
    private var indicator: some View {
        if controller.isPaused && controller.phase == .recording {
            Image(systemName: "pause.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 10)
        } else {
            Circle()
                .fill(Theme.danger)
                .frame(width: 8, height: 8)
                .opacity(dotDimmed ? 0.4 : 1)
        }
    }

    @ViewBuilder
    private func content(elapsed: TimeInterval) -> some View {
        switch controller.phase {
        case .saving:
            Text("Saving…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        case .recording where controller.isPaused:
            Text("Paused")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        default:
            Text(Self.clock(elapsed))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
            Text("· \(Self.clock(TimeInterval(controller.clipSeconds)))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func startPulse() {
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dotDimmed = false }
        } else {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { dotDimmed = true }
        }
    }

    /// "12:34", or "1:02:03" from one hour on
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// "12 minutes 34 seconds"
    private static func spoken(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let parts: [(Int, String)] = [(total / 3600, "hour"), ((total % 3600) / 60, "minute"), (total % 60, "second")]
        let words = parts.filter { $0.0 > 0 }.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        return words.isEmpty ? "0 seconds" : words.joined(separator: " ")
    }

    private func accessibilityLabel(elapsed: TimeInterval) -> String {
        switch controller.phase {
        case .saving:
            return "Saving time-lapse"
        default:
            let state = controller.isPaused ? "Time-lapse paused" : "Time-lapse recording"
            return "\(state), \(Self.spoken(elapsed)), clip \(Self.spoken(TimeInterval(controller.clipSeconds)))"
        }
    }
}
