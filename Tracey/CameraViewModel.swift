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
    // Weak reference to the camera view to drive zoom / capture mode
    weak var cameraUIViewRef: CameraUIView?

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
    /// True while the user is dragging the image (shows the center snap guides)
    @Published var isDraggingImage = false

    let imageStorage = ImageStorageManager()

    func resetImageTransforms() {
        withAnimation(.easeInOut(duration: 0.3)) {
            imageScale = 1.0
            imageRotation = 0.0
            imageOpacity = 0.6
            imageOffset = .zero
        }
    }

    /// Everything needed to bring a removed reference back (Undo).
    struct RemovedReference {
        let image: UIImage
        let opacity: Double
        let scale: CGFloat
        let rotation: Double
        let offset: CGSize
        let isFlipped: Bool
        let loadedImageName: String?
        let cameraZoom: CGFloat
    }

    /// Removes the reference and returns what is needed to undo it.
    @discardableResult
    func removeOverlayImage() -> RemovedReference? {
        let removed = overlayImage.map { image in
            RemovedReference(
                image: image,
                opacity: imageOpacity,
                scale: imageScale,
                rotation: imageRotation,
                offset: imageOffset,
                isFlipped: isFlipped,
                loadedImageName: imageStorage.loadedImageName,
                cameraZoom: cameraUIViewRef?.getCurrentZoomFactor() ?? 1.0
            )
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            overlayImage = nil
        }
        imageStorage.loadedImageName = nil // Limpiar referencia al nombre de imagen cargada
        isFlipped = false // Reiniciar flip horizontal al borrar
        if isTorchOn { toggleTorch() } // the camera turns off with no image, so does the light
        isPropertiesLocked = false
        resetImageTransforms()
        resetViewport()
        // Reiniciar zoom de cámara al borrar imagen
        cameraUIViewRef?.setZoomFactor(1.0)
        return removed
    }

    /// Undo for "Remove Image". Does nothing if another image was loaded in the meantime.
    func restore(_ removed: RemovedReference) {
        guard overlayImage == nil else { return }
        // Put the transforms back first so the image reappears exactly where it was
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            imageOpacity = removed.opacity
            imageScale = removed.scale
            imageRotation = removed.rotation
            imageOffset = removed.offset
            isFlipped = removed.isFlipped
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            overlayImage = removed.image
        }
        imageStorage.loadedImageName = removed.loadedImageName
        cameraUIViewRef?.setZoomFactor(removed.cameraZoom)
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
            resetViewport()

            // Restore the capture mode the overlay was aligned with (older saves have none)
            if let savedMode = configuration.captureMode {
                captureMode = savedMode
            }

            // Nuevo: cargar el zoom de la cámara si está disponible
            if let cameraUIView = cameraUIViewRef {
                cameraUIView.setZoomFactor(configuration.cameraZoom)
            }
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

    @Published var isPropertiesLocked: Bool = false {
        didSet {
            // When unlocking, return the canvas to its normal position so the image can be edited
            if !isPropertiesLocked && oldValue {
                resetViewport()
            }
        }
    }

    // MARK: - Viewport (move/zoom the whole screen: camera + overlay together)
    // The transform itself lives in CameraUIView (UIKit) so camera and image move as one piece.

    /// True while the locked screen is moved/zoomed away from its normal position.
    @Published var isViewportTransformed: Bool = false

    func resetViewport() {
        cameraUIViewRef?.resetViewport(animated: true)
    }

    // MARK: - Capture mode (video = smoother, photo = full frame)

    private static let captureModeKey = "cameraCaptureMode"

    @Published var captureMode: CameraCaptureMode = {
        let raw = UserDefaults.standard.string(forKey: "cameraCaptureMode") ?? ""
        return CameraCaptureMode(rawValue: raw) ?? .video
    }() {
        didSet {
            guard captureMode != oldValue else { return }
            UserDefaults.standard.set(captureMode.rawValue, forKey: Self.captureModeKey)
            cameraUIViewRef?.setCaptureMode(captureMode)
        }
    }

    func toggleCaptureMode() {
        captureMode = captureMode.toggled
    }

    // Usar variable @Published para la imagen seleccionada desde la galería
    @Published var selectedImageFromGallery: UIImage? {
        didSet {
            if let newValue = selectedImageFromGallery {
                // A new reference starts fresh: it must not inherit the previous image's size,
                // rotation, opacity or position (set without animation, it's a different image)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    imageScale = 1.0
                    imageRotation = 0.0
                    imageOpacity = 0.6
                    imageOffset = .zero
                    overlayImage = newValue
                }
                imageStorage.loadedImageName = nil
                isFlipped = false
                isPropertiesLocked = false
                resetViewport()
                // Reiniciar zoom al cargar desde galería
                cameraUIViewRef?.setZoomFactor(1.0)
            }
        }
    }

    func saveCurrentConfiguration(cameraZoom: CGFloat) -> Bool {
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
            cameraZoom: cameraZoom,
            captureMode: captureMode,
            overwriteImageName: prevLoadedName
        )

        if wasNew && success {
            if let lastConfig = imageStorage.savedConfigurations.last {
                imageStorage.loadedImageName = lastConfig.imageName
            }
        }
        return success
    }
}

