// ContentView.swift - Con gestos corregidos, controles mejorados, snap al centro, botón de enfoque, candado y pantalla siempre activa
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var showingImagePicker = false
    @State private var showingControls = true
    @State private var showingImageControls = false // Nuevo estado para controles de imagen
    @State private var dragOffset: CGSize = .zero
    @State private var gestureStartScale: CGFloat = 1.0
    @State private var gestureStartRotation: Double = 0.0
    @State private var gestureInProgress = false
    @State private var currentGestureScale: CGFloat = 1.0 // Para el zoom incremental
    @State private var cameraUIView: CameraUIView? = nil // Referencia a la vista de cámara
    @State private var isPropertiesLocked = false // Estado del candado

    // Configuración del snap al centro
    private let snapThreshold: CGFloat = 30 // Distancia en puntos para activar el snap

    var body: some View {
        GeometryReader { geometry in
            let screenCenter = CGPoint(
                x: geometry.size.width / 2,
                y: geometry.size.height / 2
            )

            ZStack {
                // Vista de cámara
                CameraView(viewModel: viewModel, cameraUIView: $cameraUIView, isZoomEnabled: !isPropertiesLocked)
                    .ignoresSafeArea()

                // Imagen superpuesta con gestos mejorados
                if let overlayImage = viewModel.overlayImage {
                    Image(uiImage: overlayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(viewModel.imageOpacity)
                        .scaleEffect(viewModel.imageScale * currentGestureScale) // Aplicar escala incremental
                        .rotationEffect(.degrees(viewModel.imageRotation))
                        .offset(CGSize(
                            width: viewModel.imageOffset.width + dragOffset.width,
                            height: viewModel.imageOffset.height + dragOffset.height
                        ))
                        .gesture(
                            // Solo permitir gestos si no está bloqueado
                            isPropertiesLocked ? nil :
                            // Gesto de escala incremental
                            MagnificationGesture()
                                .onChanged { value in
                                    currentGestureScale = value
                                }
                                .onEnded { value in
                                    // Aplicar el cambio final a la escala base
                                    let finalScale = viewModel.imageScale * value

                                    // Validar que el valor sea finito y esté en el rango permitido
                                    if finalScale.isFinite && finalScale > 0 {
                                        viewModel.imageScale = max(0.1, min(finalScale, 5.0))
                                    }

                                    // Resetear la escala del gesto
                                    currentGestureScale = 1.0
                                }
                                .simultaneously(with:
                                    // Gesto de rotación
                                    RotationGesture()
                                        .onChanged { value in
                                            if !gestureInProgress {
                                                gestureStartRotation = viewModel.imageRotation
                                                gestureInProgress = true
                                            }

                                            let rawRotation = gestureStartRotation + value.degrees
                                            let snappedRotation = snapToCardinalAngles(rawRotation)

                                            // Validar que el valor sea finito antes de asignarlo
                                            if snappedRotation.isFinite {
                                                viewModel.imageRotation = snappedRotation
                                            }
                                        }
                                        .onEnded { value in
                                            // Al terminar el gesto, actualizamos el valor base con el resultado final
                                            let rawRotation = gestureStartRotation + value.degrees
                                            let finalRotation = snapToCardinalAngles(rawRotation)

                                            if finalRotation.isFinite {
                                                // Animación suave hacia el ángulo final
                                                withAnimation(.easeOut(duration: 0.2)) {
                                                    viewModel.imageRotation = finalRotation
                                                }
                                            }
                                            gestureInProgress = false
                                        }
                                )
                        )
                        .simultaneousGesture(
                            // Solo permitir movimiento si no está bloqueado
                            isPropertiesLocked ? nil :
                            // Gesto de movimiento separado con snap al centro
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    // Calcular la posición final propuesta
                                    let proposedOffsetX = viewModel.imageOffset.width + value.translation.width
                                    let proposedOffsetY = viewModel.imageOffset.height + value.translation.height

                                    // Aplicar snap al centro
                                    let snappedOffset = snapToCenter(
                                        offset: CGSize(width: proposedOffsetX, height: proposedOffsetY),
                                        screenCenter: screenCenter
                                    )

                                    // Validar que los valores sean finitos
                                    if snappedOffset.width.isFinite && snappedOffset.height.isFinite {
                                        // Primero actualizar sin animación a la posición actual (incluyendo dragOffset)
                                        viewModel.imageOffset = CGSize(
                                            width: proposedOffsetX,
                                            height: proposedOffsetY
                                        )
                                        dragOffset = .zero

                                        // Luego animar hacia la posición final con snap (si aplica)
                                        if snappedOffset != CGSize(width: proposedOffsetX, height: proposedOffsetY) {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                viewModel.imageOffset = snappedOffset
                                            }
                                        }
                                    } else {
                                        dragOffset = .zero
                                    }
                                }
                        )
                }

                // Indicadores visuales de snap al centro (solo si no está bloqueado)
                if viewModel.overlayImage != nil && !isPropertiesLocked && (abs(dragOffset.width) > 0 || abs(dragOffset.height) > 0) {
                    SnapIndicators(
                        dragOffset: dragOffset,
                        imageOffset: viewModel.imageOffset,
                        screenCenter: screenCenter,
                        snapThreshold: snapThreshold
                    )
                }

                // Botones de enfoque y candado en la esquina superior derecha
                VStack {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            // Botón de enfoque
                            Button(action: {
                                // Enfocar al centro de la pantalla
                                cameraUIView?.focusAtCenter()
                            }) {
                                Image(systemName: "viewfinder.circle")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }

                            // Botón de linterna
                            Button(action: {
                                viewModel.toggleTorch()
                            }) {
                                Image(systemName: viewModel.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(viewModel.isTorchOn ? Color.blue.opacity(0.8) : Color.black.opacity(0.6))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }

                            // Botón de candado
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isPropertiesLocked.toggle()
                                }

                                // Feedback háptico
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                            }) {
                                Image(systemName: isPropertiesLocked ? "lock.fill" : "lock.open")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(isPropertiesLocked ? Color.red.opacity(0.8) : Color.black.opacity(0.6))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 10)
                    }
                    Spacer()
                }
                .opacity(showingControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: showingControls)

                // Controles de imagen (nuevos controles separados) - Solo permitir cambios si no está bloqueado
                if showingImageControls && viewModel.overlayImage != nil {
                    VStack {
                        Spacer()

                        ImageControlsView(viewModel: viewModel, isLocked: isPropertiesLocked)
                            .transition(.move(edge: .bottom).combined(with: .opacity))

                        Spacer().frame(height: 120) // Espacio para los controles principales
                    }
                }

                // Controles principales - AQUÍ AGREGAMOS LA ANIMACIÓN
                VStack {
                    Spacer()
                    ControlsView(
                        viewModel: viewModel,
                        showingImagePicker: $showingImagePicker,
                        showingImageControls: $showingImageControls,
                        isPropertiesLocked: isPropertiesLocked
                    )
                }
                .opacity(showingControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: showingControls)

                // Indicador de zoom de cámara y estado del candado
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("📹 Pellizca para zoom • Toca para enfocar")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(20)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                            // Indicador de estado del candado
                            if viewModel.overlayImage != nil {
                                HStack(spacing: 4) {
                                    Image(systemName: isPropertiesLocked ? "lock.fill" : "lock.open")
                                        .font(.caption2)
                                        .foregroundColor(isPropertiesLocked ? .red : .green)

                                    Text(isPropertiesLocked ? "Propiedades bloqueadas" : "Propiedades desbloqueadas")
                                        .font(.caption2)
                                        .foregroundColor(isPropertiesLocked ? .red : .green)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(15)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    Spacer()
                }
                .opacity(showingControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: showingControls)
            }
        }
        .onAppear {
            // Mantener la pantalla activa
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            // Restaurar el comportamiento normal cuando se cierre la app
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingControls.toggle()
                if !showingControls {
                    showingImageControls = false
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $viewModel.overlayImage)
        }
        .sheet(isPresented: $viewModel.showingSavedImages, onDismiss: {
            showingImageControls = false // Asegura que el menú principal pueda abrirse
        }) {
            SavedImagesView(viewModel: viewModel, isPresented: $viewModel.showingSavedImages)
        }
    }

    // Función para hacer "snap" a ángulos cardinales
    private func snapToCardinalAngles(_ angle: Double) -> Double {
        let normalizedAngle = angle.truncatingRemainder(dividingBy: 360)
        let positiveAngle = normalizedAngle < 0 ? normalizedAngle + 360 : normalizedAngle

        let cardinalAngles: [Double] = [0, 90, 180, 270, 360]
        let snapThreshold: Double = 8 // Grados de "magnetismo" - más sutil

        for cardinalAngle in cardinalAngles {
            let distance = abs(positiveAngle - cardinalAngle)
            let wrappedDistance = min(distance, 360 - distance) // Para el caso de 0° y 360°

            if wrappedDistance <= snapThreshold {
                return cardinalAngle == 360 ? 0 : cardinalAngle // 360° se convierte en 0°
            }
        }

        return positiveAngle
    }

    // Función para hacer snap al centro de la pantalla
    private func snapToCenter(offset: CGSize, screenCenter: CGPoint) -> CGSize {
        var finalOffset = offset

        // Snap horizontal (centro X)
        if abs(offset.width) <= snapThreshold {
            finalOffset.width = 0
        }

        // Snap vertical (centro Y)
        if abs(offset.height) <= snapThreshold {
            finalOffset.height = 0
        }

        return finalOffset
    }
}

// Vista para mostrar indicadores visuales del snap
struct SnapIndicators: View {
    let dragOffset: CGSize
    let imageOffset: CGSize
    let screenCenter: CGPoint
    let snapThreshold: CGFloat

    private var showVerticalIndicator: Bool {
        abs(imageOffset.width + dragOffset.width) <= snapThreshold
    }

    private var showHorizontalIndicator: Bool {
        abs(imageOffset.height + dragOffset.height) <= snapThreshold
    }

    var body: some View {
        ZStack {
            // Línea vertical del centro
            if showVerticalIndicator {
                Rectangle()
                    .fill(Color.yellow.opacity(0.8))
                    .frame(width: 2)
                    .position(x: screenCenter.x, y: screenCenter.y)
                    .animation(.easeInOut(duration: 0.2), value: showVerticalIndicator)
            }

            // Línea horizontal del centro
            if showHorizontalIndicator {
                Rectangle()
                    .fill(Color.yellow.opacity(0.8))
                    .frame(height: 2)
                    .position(x: screenCenter.x, y: screenCenter.y)
                    .animation(.easeInOut(duration: 0.2), value: showHorizontalIndicator)
            }

            // Punto central
            if showVerticalIndicator || showHorizontalIndicator {
                Circle()
                    .fill(Color.yellow.opacity(0.9))
                    .frame(width: 8, height: 8)
                    .position(x: screenCenter.x, y: screenCenter.y)
                    .animation(.easeInOut(duration: 0.2), value: showVerticalIndicator || showHorizontalIndicator)
            }
        }
        .allowsHitTesting(false) // Permitir que los gestos pasen a través
    }
}

// Nueva vista para los controles de imagen con candado
struct ImageControlsView: View {
    @ObservedObject var viewModel: CameraViewModel
    let isLocked: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Línea 1: Opacidad
            VStack(spacing: 4) {
                Text("Opacidad")
                    .foregroundColor(isLocked ? .gray : .white)
                    .font(.caption)
                    .fontWeight(.medium)

                HStack {
                    Text("0%")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption2)

                    Slider(value: $viewModel.imageOpacity, in: 0...1)
                        .frame(width: 180)
                        .disabled(isLocked)
                        .opacity(isLocked ? 0.5 : 1.0)

                    Text("100%")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption2)
                }

                Text("\(Int(viewModel.imageOpacity * 100))%")
                    .foregroundColor(isLocked ? .gray : .white)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }

            Divider()
                .background(Color.white.opacity(0.3))

            // Línea 2: Tamaño
            VStack(spacing: 4) {
                Text("Tamaño")
                    .foregroundColor(isLocked ? .gray : .white)
                    .font(.caption)
                    .fontWeight(.medium)

                HStack {
                    Text("0.1x")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption2)

                    Slider(value: $viewModel.imageScale, in: 0.1...5.0)
                        .frame(width: 180)
                        .disabled(isLocked)
                        .opacity(isLocked ? 0.5 : 1.0)

                    Text("5.0x")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption2)
                }

                Text("\(String(format: "%.1f", viewModel.imageScale))x")
                    .foregroundColor(isLocked ? .gray : .white)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }

            Divider()
                .background(Color.white.opacity(0.3))

            // Línea 3: Rotación
            VStack(spacing: 4) {
                Text("Rotación")
                    .foregroundColor(isLocked ? .gray : .white)
                    .font(.caption)
                    .fontWeight(.medium)

                HStack {
                    Text("0°")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption2)

                    Slider(value: $viewModel.imageRotation, in: 0...360)
                        .frame(width: 180)
                        .disabled(isLocked)
                        .opacity(isLocked ? 0.5 : 1.0)

                    Text("360°")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption2)
                }

                Text("\(Int(viewModel.imageRotation.isFinite ? viewModel.imageRotation : 0))°")
                    .foregroundColor(isLocked ? .gray : .white)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }

            // Indicador de candado si está bloqueado
            if isLocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundColor(.red)

                    Text("Controles bloqueados")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(isLocked ? 0.6 : 0.8))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isLocked ? Color.red.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
}
