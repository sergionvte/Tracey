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
            HStack(alignment: .center, spacing: 16) {
                GeometryReader { geo in
                    if let image = viewModel.imageStorage.loadImage(named: configuration.imageName) {
                        let side = min(geo.size.width, geo.size.height)
                        let radians = CGFloat(configuration.rotation) * .pi / 180
                        // El factor máximo para que la imagen nunca sobresalga del frame, incluso a 45°
                        let fitFactor = 1 / (abs(sin(radians)) + abs(cos(radians)))
                        let maxFactor: CGFloat = 1 / sqrt(2) // Para 45° en un cuadrado
                        let safeFactor = min(fitFactor, maxFactor)
                        let previewSize = side * 0.85 * safeFactor
                        ZStack {
                            Color.clear
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaleEffect(x: configuration.isFlipped ? -1 : 1, y: 1) // Flip horizontal si está activado
                                .frame(width: previewSize, height: previewSize)
                                .opacity(configuration.opacity)
                                .rotationEffect(.degrees(configuration.rotation))
                                .cornerRadius(10)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 120, maxHeight: 140)
                // Info y botones a la derecha, alineados y centrados
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
                            Text("Cargar")
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
                            Text("Borrar")
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

// Extensión para esquinas específicas
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
