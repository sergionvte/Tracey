//
//  CropView.swift
//  Tracey
//
//  Full-screen crop editor. It always works on the full photo, starting from the current crop,
//  so a crop can be widened again or reset at any time.
//

import SwiftUI

enum CropHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, move

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    var isCorner: Bool { (movesLeft || movesRight) && (movesTop || movesBottom) }
}

/// Crop-frame math in normalized image coordinates (0–1, origin top-left).
enum CropRectMath {
    /// `rect` after dragging `handle` by `translation` (normalized). Stays inside the image,
    /// keeps at least `minSize` per side and, when `aspect` (normalized width / height) is set,
    /// keeps that proportion: corners grow from the opposite corner, edges from the middle.
    static func adjust(_ rect: CGRect, handle: CropHandle, by translation: CGSize,
                       aspect: CGFloat?, minSize: CGFloat) -> CGRect {
        if handle == .move {
            var moved = rect
            moved.origin.x = clamp(rect.minX + translation.width, 0, 1 - rect.width)
            moved.origin.y = clamp(rect.minY + translation.height, 0, 1 - rect.height)
            return moved
        }
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesLeft { minX = clamp(minX + translation.width, 0, maxX - minSize) }
        if handle.movesRight { maxX = clamp(maxX + translation.width, minX + minSize, 1) }
        if handle.movesTop { minY = clamp(minY + translation.height, 0, maxY - minSize) }
        if handle.movesBottom { maxY = clamp(maxY + translation.height, minY + minSize, 1) }
        let free = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard let aspect, aspect > 0, aspect.isFinite else { return free }

        // Smallest width that keeps both sides at least minSize
        let minWidth = max(minSize, minSize * aspect)
        if handle.isCorner {
            // Grows from the opposite corner and follows whichever side was pulled further
            let anchorX = handle.movesLeft ? rect.maxX : rect.minX
            let anchorY = handle.movesTop ? rect.maxY : rect.minY
            let roomX = handle.movesLeft ? anchorX : 1 - anchorX
            let roomY = handle.movesTop ? anchorY : 1 - anchorY
            var width = max(free.width, free.height * aspect)
            width = min(width, roomX, roomY * aspect)
            width = max(width, min(minWidth, roomX, roomY * aspect))
            let height = width / aspect
            return CGRect(x: handle.movesLeft ? anchorX - width : anchorX,
                          y: handle.movesTop ? anchorY - height : anchorY,
                          width: width, height: height)
        }
        if handle.movesLeft || handle.movesRight {
            var width = min(free.width, aspect) // height can't pass 1
            width = max(width, min(minWidth, aspect))
            let height = width / aspect
            let x = handle.movesLeft ? clamp(rect.maxX - width, 0, 1 - width) : clamp(rect.minX, 0, 1 - width)
            return CGRect(x: x, y: clamp(rect.midY - height / 2, 0, 1 - height), width: width, height: height)
        }
        var height = min(free.height, 1 / aspect) // width can't pass 1
        height = max(height, min(minWidth / aspect, 1 / aspect))
        let width = height * aspect
        let y = handle.movesTop ? clamp(rect.maxY - height, 0, 1 - height) : clamp(rect.minY, 0, 1 - height)
        return CGRect(x: clamp(rect.midX - width / 2, 0, 1 - width), y: y, width: width, height: height)
    }

    /// The largest rect with `aspect` (normalized width / height) inside the image, centered on
    /// `rect` as far as the borders allow.
    static func fitted(_ rect: CGRect, aspect: CGFloat) -> CGRect {
        guard aspect > 0, aspect.isFinite else { return rect }
        var width = min(1, aspect)
        var height = width / aspect
        if height > 1 { height = 1; width = aspect }
        return CGRect(x: clamp(rect.midX - width / 2, 0, 1 - width),
                      y: clamp(rect.midY - height / 2, 0, 1 - height),
                      width: width, height: height)
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), max(low, high))
    }
}

struct CropView: View {
    /// The full photo (upright)
    let image: UIImage
    let initialRect: CGRect
    let onCancel: () -> Void
    let onDone: (CGRect) -> Void

    @State private var rect: CGRect = ImageCropping.unitRect
    @State private var aspect: CropAspect = .free
    @State private var landscape = false
    @State private var dragStart: (rect: CGRect, handle: CropHandle)?

    private let minSize = ImageCropping.minimumSide

    /// Proportion of the frame in normalized coordinates (pixel ratio × height / width)
    private var normalizedAspect: CGFloat? {
        guard let ratio = aspect.ratio(sourceSize: image.size, landscape: landscape),
              image.size.width > 0 else { return nil }
        return ratio * image.size.height / image.size.width
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geometry in
                canvas(in: geometry.size)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            aspectBar
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onAppear { rect = ImageCropping.sanitized(initialRect) }
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(.body)
                .frame(minHeight: 44)
            Spacer()
            Button("Reset") {
                withAnimation(Theme.spring) {
                    aspect = .free
                    rect = ImageCropping.unitRect
                }
                Haptics.light()
            }
            .font(.body)
            .frame(minHeight: 44)
            .disabled(rect == ImageCropping.unitRect && aspect == .free)
            Spacer()
            Button("Done") { onDone(rect) }
                .font(.body.weight(.semibold))
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var aspectBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CropAspect.allCases) { option in
                    aspectChip(option)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
    }

    private func aspectChip(_ option: CropAspect) -> some View {
        let isSelected = option == aspect
        return Button {
            Haptics.light()
            withAnimation(Theme.spring) {
                if isSelected && option.canTurn {
                    landscape.toggle()
                } else {
                    aspect = option
                }
                if let normalizedAspect { rect = CropRectMath.fitted(rect, aspect: normalizedAspect) }
            }
        } label: {
            HStack(spacing: 6) {
                if option.canTurn && isSelected {
                    Image(systemName: landscape ? "rectangle" : "rectangle.portrait")
                        .font(.footnote.weight(.semibold))
                }
                Text(option.label)
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .background(isSelected ? Theme.accent : Color.white.opacity(0.12), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.canTurn && isSelected
                            ? "\(option.label), \(landscape ? String(localized: "landscape") : String(localized: "portrait"))"
                            : option.label)
        .accessibilityHint(option.canTurn && isSelected ? String(localized: "Double-tap to turn the frame.") : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Canvas

    private func canvas(in available: CGSize) -> some View {
        let fit = min(available.width / max(image.size.width, 1), available.height / max(image.size.height, 1))
        let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        let frame = CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                           width: rect.width * size.width, height: rect.height * size.height)
        return ZStack(alignment: .topLeading) {
            Image(uiImage: image)
                .resizable()
                .frame(width: size.width, height: size.height)

            // Dim what is cut away
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(frame)
            }
            .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))

            CropFrameOverlay(frame: frame)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(dragGesture(frame: frame, size: size))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Crop")
        .accessibilityValue("\(Int((rect.width * 100).rounded()))% × \(Int((rect.height * 100).rounded()))%")
    }

    private func dragGesture(frame: CGRect, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = (rect, Self.handle(at: value.startLocation, frame: frame))
                }
                guard let start = dragStart, size.width > 0, size.height > 0 else { return }
                let translation = CGSize(width: value.translation.width / size.width,
                                         height: value.translation.height / size.height)
                rect = CropRectMath.adjust(start.rect, handle: start.handle, by: translation,
                                           aspect: normalizedAspect, minSize: minSize)
            }
            .onEnded { _ in dragStart = nil }
    }

    /// Corners win within 32 pt, then edges within 24 pt; anywhere else moves the frame.
    private static func handle(at point: CGPoint, frame: CGRect) -> CropHandle {
        let corner: CGFloat = 32, edge: CGFloat = 24
        let nearLeft = abs(point.x - frame.minX) < corner, nearRight = abs(point.x - frame.maxX) < corner
        let nearTop = abs(point.y - frame.minY) < corner, nearBottom = abs(point.y - frame.maxY) < corner
        switch (nearLeft, nearRight, nearTop, nearBottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        default: break
        }
        let withinX = point.x > frame.minX && point.x < frame.maxX
        let withinY = point.y > frame.minY && point.y < frame.maxY
        if withinY && abs(point.x - frame.minX) < edge { return .left }
        if withinY && abs(point.x - frame.maxX) < edge { return .right }
        if withinX && abs(point.y - frame.minY) < edge { return .top }
        if withinX && abs(point.y - frame.maxY) < edge { return .bottom }
        return .move
    }
}

/// Border, rule-of-thirds lines and corner/edge grips of the crop frame.
private struct CropFrameOverlay: View {
    let frame: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                for i in 1...2 {
                    let x = frame.minX + frame.width * CGFloat(i) / 3
                    let y = frame.minY + frame.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: frame.minY)); path.addLine(to: CGPoint(x: x, y: frame.maxY))
                    path.move(to: CGPoint(x: frame.minX, y: y)); path.addLine(to: CGPoint(x: frame.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)

            Path { path in path.addRect(frame) }
                .stroke(Color.white, lineWidth: 1)

            Path { path in
                let l: CGFloat = min(22, frame.width / 3, frame.height / 3)
                // Corners
                for (x, y, dx, dy) in [(frame.minX, frame.minY, 1.0, 1.0), (frame.maxX, frame.minY, -1.0, 1.0),
                                       (frame.minX, frame.maxY, 1.0, -1.0), (frame.maxX, frame.maxY, -1.0, -1.0)] {
                    path.move(to: CGPoint(x: x + dx * l, y: y))
                    path.addLine(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + dy * l))
                }
                // Edge grips
                path.move(to: CGPoint(x: frame.midX - l / 2, y: frame.minY)); path.addLine(to: CGPoint(x: frame.midX + l / 2, y: frame.minY))
                path.move(to: CGPoint(x: frame.midX - l / 2, y: frame.maxY)); path.addLine(to: CGPoint(x: frame.midX + l / 2, y: frame.maxY))
                path.move(to: CGPoint(x: frame.minX, y: frame.midY - l / 2)); path.addLine(to: CGPoint(x: frame.minX, y: frame.midY + l / 2))
                path.move(to: CGPoint(x: frame.maxX, y: frame.midY - l / 2)); path.addLine(to: CGPoint(x: frame.maxX, y: frame.midY + l / 2))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}
