//
//  CameraViewModel.swift
//  DrawingReference
//
//  Created by Sergio Navarrete on 31/05/25.
//

// CameraViewModel.swift - Con validaciones para evitar valores infinitos o NaN
import SwiftUI
import Combine
import AVFoundation
import Foundation
import UIKit

class CameraViewModel: ObservableObject {
    @Published var overlayImage: UIImage? = nil
    @Published var imageOpacity: Double = 0.6 {
        didSet {
            // Validar que el valor sea finito y esté en el rango correcto
            if !imageOpacity.isFinite || imageOpacity < 0 || imageOpacity > 1 {
                imageOpacity = max(0, min(oldValue.isFinite ? oldValue : 0.6, 1))
            }
        }
    }
    @Published var imageScale: CGFloat = 1.0 {
        didSet {
            // Validar que el valor sea finito y esté en el rango correcto
            if !imageScale.isFinite || imageScale <= 0 {
                imageScale = oldValue.isFinite && oldValue > 0 ? oldValue : 1.0
            }
        }
    }
    @Published var imageRotation: Double = 0.0 {
        didSet {
            // Validar que el valor sea finito
            if !imageRotation.isFinite {
                imageRotation = oldValue.isFinite ? oldValue : 0.0
            }
            // Normalizar la rotación entre 0 y 360
            while imageRotation < 0 {
                imageRotation += 360
            }
            while imageRotation >= 360 {
                imageRotation -= 360
            }
        }
    }
    @Published var imageOffset: CGSize = .zero {
        didSet {
            // Validar que los valores sean finitos
            if !imageOffset.width.isFinite || !imageOffset.height.isFinite {
                imageOffset = CGSize(
                    width: oldValue.width.isFinite ? oldValue.width : 0,
                    height: oldValue.height.isFinite ? oldValue.height : 0
                )
            }
        }
    }
    @Published var showingSavedImages = false

    let imageStorage = ImageStorageManager()

    func resetImageTransforms() {
        withAnimation(.easeInOut(duration: 0.3)) {
            imageScale = 1.0
            imageRotation = 0.0
            imageOpacity = 0.6
            imageOffset = .zero
        }
    }

    func removeOverlayImage() {
        withAnimation(.easeInOut(duration: 0.2)) {
            overlayImage = nil
        }
        imageStorage.loadedImageName = nil // Limpiar referencia al nombre de imagen cargada
        isFlipped = false // Reiniciar flip horizontal al borrar
        resetImageTransforms()
    }

    // Cuando se selecciona una nueva imagen desde la galería, limpiar loadedImageName
    var selectedImageFromGallery: UIImage? {
        get { overlayImage }
        set {
            overlayImage = newValue
            if newValue != nil {
                imageStorage.loadedImageName = nil // Forzar nuevo guardado
                isFlipped = false // Reiniciar flip horizontal
                isPropertiesLocked = false // Reiniciar estado de bloqueo al cargar desde la galería
            }
        }
    }

    func saveCurrentConfiguration() -> Bool {
        guard let image = overlayImage else { return false }

        let safeOpacity = imageOpacity.isFinite ? imageOpacity : 0.6
        let safeScale = imageScale.isFinite && imageScale > 0 ? imageScale : 1.0
        let safeRotation = imageRotation.isFinite ? imageRotation : 0.0
        let safeOffsetX = imageOffset.width.isFinite ? imageOffset.width : 0.0
        let safeOffsetY = imageOffset.height.isFinite ? imageOffset.height : 0.0
        let safeIsFlipped = isFlipped

        let wasNew = imageStorage.loadedImageName == nil
        let prevLoadedName = imageStorage.loadedImageName

        let success = imageStorage.saveImageConfiguration(
            image: image,
            opacity: safeOpacity,
            scale: Double(safeScale),
            rotation: safeRotation,
            offsetX: safeOffsetX,
            offsetY: safeOffsetY,
            isFlipped: safeIsFlipped,
            overwriteImageName: prevLoadedName
        )

        // Si era una imagen nueva y se guardó bien, asignar el nombre de la imagen guardada
        if wasNew && success {
            // Buscar la última configuración guardada (la más reciente)
            if let lastConfig = imageStorage.savedConfigurations.last {
                imageStorage.loadedImageName = lastConfig.imageName
            }
        }
        return success
    }

    func loadConfiguration(_ configuration: SavedImageConfiguration) {
        if let image = imageStorage.loadImage(named: configuration.imageName) {
            overlayImage = image
            imageStorage.loadedImageName = configuration.imageName // Guardar el nombre de la imagen cargada

            // Validar todos los valores antes de asignarlos
            imageOpacity = configuration.opacity.isFinite ? max(0, min(configuration.opacity, 1)) : 0.6
            imageScale = configuration.scale.isFinite && configuration.scale > 0 ? CGFloat(configuration.scale) : 1.0
            imageRotation = configuration.rotation.isFinite ? configuration.rotation : 0.0
            isFlipped = configuration.isFlipped // Cargar flip

            let offsetWidth = configuration.offsetX.isFinite ? configuration.offsetX : 0.0
            let offsetHeight = configuration.offsetY.isFinite ? configuration.offsetY : 0.0
            imageOffset = CGSize(width: offsetWidth, height: offsetHeight)
            isPropertiesLocked = false // Reiniciar estado de bloqueo al cargar desde imágenes guardadas
        }
    }

    func centerImage() {
        // Animación suave para centrar la imagen
        withAnimation(.easeInOut(duration: 0.3)) {
            imageOffset = .zero
        }
    }

    @Published var isTorchOn: Bool = false

    func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            if device.torchMode == .on {
                device.torchMode = .off
                isTorchOn = false
            } else {
                try device.setTorchModeOn(level: 1.0)
                isTorchOn = true
            }
            device.unlockForConfiguration()
        } catch {
            print("Error toggling torch: \(error)")
        }
    }

    @Published var isFlipped: Bool = false

    func flipOverlayImage() {
        isFlipped.toggle()
    }

    @Published var isPropertiesLocked: Bool = false // Agregar esta propiedad para gestionar el estado de bloqueo globalmente

}

