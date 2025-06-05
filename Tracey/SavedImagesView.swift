//
//  SavedImagesView.swift
//  DrawingReference
//
//  Created by Sergio Navarrete on 31/05/25.
//

// SavedImagesView.swift - With larger buttons and real-time updates
import SwiftUI

struct SavedImagesView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 15) {
                    ForEach(viewModel.imageStorage.savedConfigurations) { configuration in
                        SavedImageCard(
                            configuration: configuration,
                            viewModel: viewModel,
                            isPresented: $isPresented
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Saved Images")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct SavedImageCard: View {
    let configuration: SavedImageConfiguration
    @ObservedObject var viewModel: CameraViewModel
    @Binding var isPresented: Bool
    @State private var showingDeleteAlert = false
    @State private var isDeleted = false

    var body: some View {
        if !isDeleted {
            HStack(alignment: .center, spacing: 16) {
                GeometryReader { geo in
                    if let image = viewModel.imageStorage.loadImage(named: configuration.imageName) {
                        let side = min(geo.size.width, geo.size.height)
                        let radians = CGFloat(configuration.rotation) * .pi / 180
                        // The maximum factor so the image never exceeds the frame, even at 45°
                        let fitFactor = 1 / (abs(sin(radians)) + abs(cos(radians)))
                        let maxFactor: CGFloat = 1 / sqrt(2) // For 45° in a square
                        let safeFactor = min(fitFactor, maxFactor)
                        let previewSize = side * 0.85 * safeFactor
                        ZStack {
                            Color.clear
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaleEffect(x: configuration.isFlipped ? -1 : 1, y: 1) // Horizontal flip if enabled
                                .frame(width: previewSize, height: previewSize)
                                .opacity(configuration.opacity)
                                .rotationEffect(.degrees(configuration.rotation))
                                .cornerRadius(10)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 120, maxHeight: 140)
                // Info and buttons to the right, aligned and centered
                VStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .center, spacing: 6) {
                        HStack {
                            Text("💧 \(Int(configuration.opacity * 100))%")
                                .font(.system(size: 13, weight: .semibold))
                            Text("📏 \(String(format: "%.1f", configuration.scale))x")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        HStack {
                            Text("🔄 \(Int(configuration.rotation))°")
                                .font(.system(size: 13, weight: .semibold))
                            Text("📍 (\(Int(configuration.offsetX)), \(Int(configuration.offsetY)))")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    VStack(alignment: .center, spacing: 10) {
                        Button(action: {
                            viewModel.loadConfiguration(configuration)
                            isPresented = false
                        }) {
                            Text("Load")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: 140)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                        Button(action: {
                            showingDeleteAlert = true
                        }) {
                            Text("Delete")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: 140)
                                .padding(.vertical, 8)
                                .background(Color.red)
                                .cornerRadius(12)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: 170, alignment: .center)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .frame(maxWidth: .infinity)
            .opacity(isDeleted ? 0 : 1)
            .animation(.easeOut(duration: 0.3), value: isDeleted)
            .alert("Confirm Deletion", isPresented: Binding(get: { showingDeleteAlert && !isDeleted }, set: { showingDeleteAlert = $0 })) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isDeleted = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.imageStorage.deleteConfiguration(configuration)
                        showingDeleteAlert = false // Force alert close if still active
                    }
                }
            } message: {
                Text("Are you sure you want to delete this saved image?")
            }
        }
    }
}

// Extension for specific corners
fileprivate extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}

fileprivate struct RoundedCorner: Shape {
    var radius: CGFloat = 12.0
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
