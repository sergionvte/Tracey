//
//  SavedImagesView.swift
//  DrawingReference
//
//  Created by Sergio Navarrete on 31/05/25.
//

// SavedImagesView.swift - Library of saved references as a thumbnail grid
import SwiftUI

struct SavedImagesView: View {
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var storage: ImageStorageManager
    @Binding var isPresented: Bool
    /// Called after a reference was loaded
    var onLoaded: () -> Void = {}
    @State private var pendingDelete: SavedImageConfiguration?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if storage.savedConfigurations.isEmpty {
                    ContentUnavailableView {
                        Label("No saved references", systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text("Use “Save to Library” in the ⋯ menu to keep an image with its position, size and opacity.")
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(storage.savedConfigurations.reversed()) { configuration in
                                SavedReferenceCard(
                                    configuration: configuration,
                                    storage: storage,
                                    onLoad: { load(configuration) },
                                    onDelete: { pendingDelete = configuration }
                                )
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                            }
                        }
                        .padding(16)
                        .animation(Theme.spring, value: storage.savedConfigurations.map(\.id))
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .confirmationDialog(
                "Delete this reference?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { configuration in
                Button("Delete", role: .destructive) {
                    storage.deleteConfiguration(configuration)
                    Haptics.light()
                }
            } message: { _ in
                Text("The image and its saved adjustments will be removed.")
            }
        }
        .tint(Theme.accent)
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func load(_ configuration: SavedImageConfiguration) {
        viewModel.loadConfiguration(configuration)
        Haptics.light()
        isPresented = false
        onLoaded()
    }
}

struct SavedReferenceCard: View {
    let configuration: SavedImageConfiguration
    let storage: ImageStorageManager
    let onLoad: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
            details
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: onLoad)
        .contextMenu {
            Button("Use This Reference", systemImage: "pencil.and.scribble", action: onLoad)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .task(id: configuration.id) {
            guard thumbnail == nil, let full = storage.loadImage(named: configuration.imageName) else { return }
            let small = await full.byPreparingThumbnail(ofSize: CGSize(width: 480, height: 480)) ?? full
            // Show the reference the way it was saved: with its filter applied
            if let filter = configuration.filter.flatMap(ReferenceFilter.init(rawValue:)), filter != .original {
                thumbnail = await Task.detached(priority: .utility) {
                    ReferenceFilterRenderer.shared.render(small, filter: filter, maxLongSide: 480)
                }.value ?? small
            } else {
                thumbnail = small
            }
        }
    }

    private var preview: some View {
        ZStack {
            // Outline is blue lines on transparent: show it on "paper", like the filter tiles
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(configuration.filter == ReferenceFilter.outline.rawValue
                      ? Color.white.opacity(0.92) : Color.black.opacity(0.35))

            if let thumbnail, thumbnail.size.width > 0, thumbnail.size.height > 0 {
                GeometryReader { geo in
                    // Fit the image, then shrink it until its ROTATED bounding box fits the
                    // tile too — works for any aspect ratio, not just squares.
                    let available = CGSize(width: max(geo.size.width - 24, 1), height: max(geo.size.height - 24, 1))
                    let fit = min(available.width / thumbnail.size.width, available.height / thumbnail.size.height)
                    let w = thumbnail.size.width * fit
                    let h = thumbnail.size.height * fit
                    let radians = CGFloat(configuration.rotation) * .pi / 180
                    let boundsW = w * abs(cos(radians)) + h * abs(sin(radians))
                    let boundsH = w * abs(sin(radians)) + h * abs(cos(radians))
                    let shrink = min(1, available.width / boundsW, available.height / boundsH)

                    Image(uiImage: thumbnail)
                        .resizable()
                        .frame(width: w, height: h)
                        .scaleEffect(x: configuration.isFlipped ? -shrink : shrink, y: configuration.isFlippedVertically ? -shrink : shrink)
                        .rotationEffect(.degrees(configuration.rotation))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            } else {
                ProgressView()
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .glassSurface(Circle(), interactive: true)
                    // 44 pt touch target around the 32 pt button
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(2)
            .accessibilityLabel("Delete")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                // e.g. "20 Nov, 14:06" (localized parts)
                Text("\(configuration.dateCreated.formatted(.dateTime.day().month(.abbreviated))), \(configuration.dateCreated.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                // Camera mode the reference was aligned with
                if let mode = configuration.captureMode {
                    Image(systemName: mode.iconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .accessibilityLabel(mode.shortTitle)
                }
            }

            // Chips never wrap; if the rotation chip doesn't fit it is dropped instead
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    opacityChip
                    scaleChip
                    if Int(configuration.rotation) != 0 {
                        chip("rotate.right", "\(Int(configuration.rotation))°")
                    }
                }
                HStack(spacing: 5) {
                    opacityChip
                    scaleChip
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var opacityChip: some View {
        chip("circle.lefthalf.filled", "\(Int(configuration.opacity * 100))%")
    }

    private var scaleChip: some View {
        chip("arrow.up.left.and.arrow.down.right", String(format: "%.1f×", configuration.scale))
    }

    private func chip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.1)))
        .fixedSize()
    }
}
