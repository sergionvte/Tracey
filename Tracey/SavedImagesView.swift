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
            thumbnail = await full.byPreparingThumbnail(ofSize: CGSize(width: 480, height: 480)) ?? full
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.35))

            if let thumbnail {
                // Rotated images are scaled down so they never spill out of the tile
                let radians = CGFloat(configuration.rotation) * .pi / 180
                let fit = 1 / (abs(sin(radians)) + abs(cos(radians)))
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: configuration.isFlipped ? -fit : fit, y: fit)
                    .rotationEffect(.degrees(configuration.rotation))
                    .padding(12)
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
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassSurface(Circle(), interactive: true)
            .padding(8)
            .accessibilityLabel("Delete")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(configuration.dateCreated, format: .dateTime.day().month(.abbreviated).year())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                chip("circle.lefthalf.filled", "\(Int(configuration.opacity * 100))%")
                chip("arrow.up.left.and.arrow.down.right", String(format: "%.1f×", configuration.scale))
                if let mode = configuration.captureMode {
                    chip(mode.iconName, nil)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private func chip(_ icon: String, _ text: String?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            if let text {
                Text(text)
                    .font(.caption2.weight(.semibold).monospacedDigit())
            }
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}
