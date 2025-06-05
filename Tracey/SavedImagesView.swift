//
//  SavedImagesView.swift
//  DrawingReference
//
//  Created by Sergio Navarrete on 31/05/25.
//

// SavedImagesView.swift - Con botones más grandes y actualización en tiempo real
import SwiftUI

struct SavedImagesView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 15) {
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
            .navigationTitle("Imágenes Guardadas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
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
            VStack {
                if let image = viewModel.imageStorage.loadImage(named: configuration.imageName) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 120)
                        .opacity(configuration.opacity)
                        .scaleEffect(min(configuration.scale * 0.5, 1.0))
                        .rotationEffect(.degrees(configuration.rotation))
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("💧 \(Int(configuration.opacity * 100))%")
                            .font(.caption2)
                        Text("📏 \(String(format: "%.1f", configuration.scale))x")
                            .font(.caption2)
                    }
                    HStack {
                        Text("🔄 \(Int(configuration.rotation))°")
                            .font(.caption2)
                        Text("📍 (\(Int(configuration.offsetX)), \(Int(configuration.offsetY)))")
                            .font(.caption2)
                    }
                }
                .foregroundColor(.secondary)

                // Botones de texto uno sobre otro
                VStack(spacing: 8) {
                    Button(action: {
                        viewModel.loadConfiguration(configuration)
                        isPresented = false
                    }) {
                        Text("Cargar")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(15)
                    }

                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        Text("Borrar")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(15)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .opacity(isDeleted ? 0 : 1)
            .animation(.easeOut(duration: 0.3), value: isDeleted)
            .alert("Confirmar eliminación", isPresented: Binding(get: { showingDeleteAlert && !isDeleted }, set: { showingDeleteAlert = $0 })) {
                Button("Cancelar", role: .cancel) { }
                Button("Eliminar", role: .destructive) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isDeleted = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.imageStorage.deleteConfiguration(configuration)
                        showingDeleteAlert = false // Forzar cierre de alerta si aún está activa
                    }
                }
            } message: {
                Text("¿Estás seguro de que quieres eliminar esta imagen guardada?")
            }
        }
    }
}
