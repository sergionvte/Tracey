//
//  ControlsView.swift
//  DrawingReference
//
//  Created by Sergio Navarrete on 31/05/25.
//

// ControlsView.swift - Con botón para mostrar/ocultar controles de imagen y soporte para candado
import SwiftUI

struct ControlsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Binding var showingImagePicker: Bool
    @Binding var showingImageControls: Bool
    let isPropertiesLocked: Bool
    @State private var showingSaveAlert = false
    @State private var saveSuccess = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Botones principales
            HStack(spacing: 15) {
                // Seleccionar imagen
                Button(action: {
                    showingImagePicker = true
                }) {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                
                // Ver imágenes guardadas
                Button(action: {
                    viewModel.showingSavedImages = true
                }) {
                    Image(systemName: "folder")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.green)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                
                // Botones adicionales cuando hay imagen
                if viewModel.overlayImage != nil {
                    // Mostrar/ocultar controles de imagen
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingImageControls.toggle()
                        }
                    }) {
                        Image(systemName: showingImageControls ? "slider.horizontal.below.rectangle" : "slider.horizontal.3")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(showingImageControls ? Color.yellow : Color.gray)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    
                    // Centrar imagen - Deshabilitado si está bloqueado
                    Button(action: {
                        if !isPropertiesLocked {
                            viewModel.centerImage()
                        }
                    }) {
                        Image(systemName: "scope")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(isPropertiesLocked ? Color.gray.opacity(0.5) : Color.purple)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .opacity(isPropertiesLocked ? 0.6 : 1.0)
                    .disabled(isPropertiesLocked)
                    
                    // Guardar configuración actual
                    Button(action: {
                        saveSuccess = viewModel.saveCurrentConfiguration()
                        showingSaveAlert = true
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.orange)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    
                    // Limpiar imagen
                    Button(action: {
                        viewModel.removeOverlayImage()
                        showingImageControls = false
                    }) {
                        Image(systemName: "trash")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.red)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
            }
        }
        .padding(.bottom, 50)
        .alert("Guardar Imagen", isPresented: $showingSaveAlert) {
            Button("OK") { }
        } message: {
            Text(saveSuccess ? "Imagen guardada correctamente" : "Error al guardar la imagen")
        }
    }
}
