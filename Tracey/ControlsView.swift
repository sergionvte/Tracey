//
//  ControlsView.swift
//  DrawingReference
//
//  Created by Sergio Navarrete on 31/05/25.
//

// ControlsView.swift - Con menú hamburguesa animado y diseño minimalista
import SwiftUI

struct ControlsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Binding var showingImagePicker: Bool
    @Binding var showingImageControls: Bool
    let isPropertiesLocked: Bool
    @State private var showingSaveAlert = false
    @State private var saveSuccess = false
    @State private var isMenuExpanded = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Botones del menú - aparecen en círculo perfecto alrededor del botón principal
                if isMenuExpanded {
                    //let radius: CGFloat = 85
                    let radius: CGFloat = 70
                    let angleStep: CGFloat = .pi / 3 // 60 grados entre cada botón

                    // Botón Seleccionar imagen (posición 0° - arriba)
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isMenuExpanded = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showingImagePicker = true
                        }
                    }) {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 45, height: 45)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .offset(
                        x: radius * sin(0),
                        y: -radius * cos(0)
                    )
                    .scaleEffect(isMenuExpanded ? 1.0 : 0.1)
                    .opacity(isMenuExpanded ? 1.0 : 0.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1), value: isMenuExpanded)

                    // Botón Ver imágenes guardadas (posición 60° - arriba derecha)
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isMenuExpanded = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            viewModel.showingSavedImages = true
                        }
                    }) {
                        Image(systemName: "folder")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 45, height: 45)
                            .background(Color.green)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .offset(
                        x: radius * sin(angleStep),
                        y: -radius * cos(angleStep)
                    )
                    .scaleEffect(isMenuExpanded ? 1.0 : 0.1)
                    .opacity(isMenuExpanded ? 1.0 : 0.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.15), value: isMenuExpanded)

                    // Botones adicionales cuando hay imagen
                    if viewModel.overlayImage != nil {
                        // Botón Controles de imagen (posición 120° - abajo derecha)
                        Button(action: {
                            if !isPropertiesLocked {
                                // Cerrar menú principal con animación suave
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    isMenuExpanded = false
                                }
                                // Esperar a que termine la animación de cierre antes de abrir propiedades
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                                        showingImageControls = true
                                    }
                                }
                            }
                        }) {
                            Image(systemName: showingImageControls ? "slider.horizontal.below.rectangle" : "slider.horizontal.3")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 45, height: 45)
                                .background(isPropertiesLocked ? Color.gray.opacity(0.5) : (showingImageControls ? Color.yellow : Color.gray))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .offset(
                            x: radius * sin(angleStep * 2),
                            y: -radius * cos(angleStep * 2)
                        )
                        .scaleEffect(isMenuExpanded ? 1.0 : 0.1)
                        .opacity(isMenuExpanded ? (isPropertiesLocked ? 0.6 : 1.0) : 0.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.2), value: isMenuExpanded)
                        .disabled(isPropertiesLocked)

                        // Botón Centrar imagen (posición 180° - abajo)
                        Button(action: {
                            if !isPropertiesLocked {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    isMenuExpanded = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    viewModel.centerImage()
                                }
                            }
                        }) {
                            Image(systemName: "scope")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 45, height: 45)
                                .background(isPropertiesLocked ? Color.gray.opacity(0.5) : Color.purple)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .offset(
                            x: radius * sin(angleStep * 3),
                            y: -radius * cos(angleStep * 3)
                        )
                        .scaleEffect(isMenuExpanded ? 1.0 : 0.1)
                        .opacity(isMenuExpanded ? (isPropertiesLocked ? 0.6 : 1.0) : 0.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.25), value: isMenuExpanded)
                        .disabled(isPropertiesLocked)

                        // Botón Guardar (posición 240° - abajo izquierda)
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isMenuExpanded = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                saveSuccess = viewModel.saveCurrentConfiguration()
                                showingSaveAlert = true
                            }
                        }) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 45, height: 45)
                                .background(Color.orange)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .offset(
                            x: radius * sin(angleStep * 4),
                            y: -radius * cos(angleStep * 4)
                        )
                        .scaleEffect(isMenuExpanded ? 1.0 : 0.1)
                        .opacity(isMenuExpanded ? 1.0 : 0.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.3), value: isMenuExpanded)

                        // Botón Limpiar imagen (posición 300° - arriba izquierda)
                        Button(action: {
                            if !isPropertiesLocked {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    isMenuExpanded = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    viewModel.removeOverlayImage()
                                    // Cerrar propiedades suavemente cuando se elimina la imagen
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                        showingImageControls = false
                                    }
                                }
                            }
                        }) {
                            Image(systemName: "trash")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 45, height: 45)
                                .background(isPropertiesLocked ? Color.gray.opacity(0.5) : Color.red)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .offset(
                            x: radius * sin(angleStep * 5),
                            y: -radius * cos(angleStep * 5)
                        )
                        .scaleEffect(isMenuExpanded ? 1.0 : 0.1)
                        .opacity(isMenuExpanded ? (isPropertiesLocked ? 0.6 : 1.0) : 0.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.35), value: isMenuExpanded)
                        .disabled(isPropertiesLocked)
                    }
                }

                // Botón principal (hamburguesa/cerrar)
                Button(action: {
                    // Si el menú de propiedades está abierto, cerrarlo y abrir el menú principal
                    if showingImageControls {
                        // Cerrar menú de propiedades con transición suave
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            showingImageControls = false
                        }
                        // Abrir el menú principal después de cerrar propiedades con timing perfecto
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                isMenuExpanded = true
                            }
                        }
                    } else {
                        // Toggle del menú principal con animación mejorada
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                            isMenuExpanded.toggle()
                        }
                    }
                }) {
                    ZStack {
                        // Fondo del botón con gradiente dinámico y transiciones suaves
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        showingImageControls ? Color.pink : (isMenuExpanded ? Color.pink : Color.blue),
                                        showingImageControls ? Color.pink.opacity(0.8) : (isMenuExpanded ? Color.pink.opacity(0.8) : Color.blue.opacity(0.8))
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showingImageControls)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isMenuExpanded)

                        // Ícono que cambia según el contexto con transiciones mejoradas
                        Image(systemName: showingImageControls ? "xmark" : (isMenuExpanded ? "xmark" : "ellipsis"))
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(showingImageControls ? 0 : (isMenuExpanded ? 180 : 0)))
                            .scaleEffect(showingImageControls ? 1.2 : (isMenuExpanded ? 1.1 : 1.0))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showingImageControls)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isMenuExpanded)
                    }
                }
                .scaleEffect(showingImageControls ? 1.2 : (isMenuExpanded ? 1.1 : 1.0))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showingImageControls)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isMenuExpanded)

                // Fondo difuminado cuando el menú está abierto - con transición mejorada
                if isMenuExpanded {
                    Circle()
                        .fill(Color.black.opacity(0.08))
                        //.fill(Color.black.opacity(0))
                        .frame(width: 220, height: 220)
                        .scaleEffect(isMenuExpanded ? 1.0 : 0.1)
                        .opacity(isMenuExpanded ? 1.0 : 0.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isMenuExpanded)
                        .allowsHitTesting(false)
                        .zIndex(-1)
                }
            }
        }
        .padding(.bottom, 50)
        // Observar cambios en showingImageControls para cerrar el menú principal con transición suave
        .onChange(of: showingImageControls) { oldValue, newValue in
            if newValue && isMenuExpanded {
                // Si se abre el menú de propiedades y el menú principal está abierto, cerrar el menú principal suavemente
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isMenuExpanded = false
                }
            }
        }
        .alert("Guardar Imagen", isPresented: $showingSaveAlert) {
            Button("OK") { }
        } message: {
            Text(saveSuccess ? "Imagen guardada correctamente" : "Error al guardar la imagen")
        }
    }
}
