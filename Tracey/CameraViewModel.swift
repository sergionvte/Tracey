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

    /// The reference as picked/loaded. Never filtered: it's what gets saved, undone and stored.
    @Published var overlayImage: UIImage? = nil {
        didSet {
            if overlayImage !== oldValue { overlayImageChanged() }
        }
    }
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
    /// Camera access is denied or restricted (shows a card that links to Settings)
    @Published var isCameraAccessDenied = false
    /// Camera access has been granted (false while undecided or denied)
    @Published var isCameraAuthorized = false

    let imageStorage = ImageStorageManager()

    // MARK: - Filters

    /// Filter applied to what is drawn over the camera
    @Published private(set) var referenceFilter: ReferenceFilter = .original
    /// What is drawn: `overlayImage` with `referenceFilter` applied (same point size)
    @Published private(set) var displayImage: UIImage?
    /// Small previews of the current reference with each filter (Adjust panel tiles)
    @Published private(set) var filterThumbnails: [ReferenceFilter: UIImage] = [:]
    /// Grid over the reference: 0 = off, 3 or 4 divisions per side
    @Published var gridDivisions: Int = 0

    /// Fires when a filter couldn't be applied (it falls back to Original)
    let filterFailed = PassthroughSubject<Void, Never>()

    private var filteredCache: [ReferenceFilter: UIImage] = [:]
    private var filterGeneration = 0
    private let filterQueue = DispatchQueue(label: "tracey.filters", qos: .userInitiated)
    private let thumbnailQueue = DispatchQueue(label: "tracey.filters.thumbnails", qos: .utility)

    /// Picks a filter. The overlay switches once the filtered image is ready; until then the
    /// previous one stays on screen (no flash).
    func selectFilter(_ filter: ReferenceFilter) {
        guard filter != referenceFilter else { return }
        referenceFilter = filter
        updateDisplayImage(keepPrevious: true)
    }

    /// Sets the filter for an image that is about to be shown (call before setting overlayImage).
    private func setFilterForNewImage(_ filter: ReferenceFilter) {
        referenceFilter = filter
    }

    private func overlayImageChanged() {
        filteredCache = [:]
        filterThumbnails = [:]
        // A different image: don't keep showing the previous one while the filter renders
        updateDisplayImage(keepPrevious: false)
        generateFilterThumbnails()
    }

    private func updateDisplayImage(keepPrevious: Bool) {
        filterGeneration += 1
        guard let source = overlayImage else {
            displayImage = nil
            return
        }
        let filter = referenceFilter
        if filter == .original {
            displayImage = source
            return
        }
        if let cached = filteredCache[filter] {
            displayImage = cached
            return
        }
        if !keepPrevious { displayImage = nil }
        let generation = filterGeneration
        filterQueue.async { [weak self] in
            // Long side ≤ 2048 px: plenty for an overlay, and quick to filter
            let result = ReferenceFilterRenderer.shared.render(source, filter: filter, maxLongSide: 2048)
            DispatchQueue.main.async {
                guard let self, self.overlayImage === source else { return }
                if let result {
                    self.filteredCache[filter] = result
                    if generation == self.filterGeneration { self.displayImage = result }
                } else if generation == self.filterGeneration {
                    self.referenceFilter = .original
                    self.displayImage = source
                    self.filterFailed.send()
                }
            }
        }
    }

    private func generateFilterThumbnails() {
        guard let source = overlayImage else { return }
        thumbnailQueue.async { [weak self] in
            let renderer = ReferenceFilterRenderer.shared
            // 120 px previews, filtered from one small copy
            guard let small = renderer.render(source, filter: .original, maxLongSide: 120) else { return }
            for filter in ReferenceFilter.allCases {
                let thumbnail: UIImage?
                switch filter {
                case .original:
                    thumbnail = small
                case .outline:
                    // Edges found at 120 px turn into a solid blob: trace at 480 px, then shrink
                    thumbnail = renderer.render(source, filter: .outline, maxLongSide: 480)
                        .flatMap { renderer.render($0, filter: .original, maxLongSide: 120) }
                default:
                    thumbnail = renderer.render(small, filter: filter, maxLongSide: 120)
                }
                DispatchQueue.main.async {
                    guard let self, self.overlayImage === source else { return }
                    self.filterThumbnails[filter] = thumbnail ?? small
                }
            }
        }
    }

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
        let filter: ReferenceFilter
        let gridDivisions: Int
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
                cameraZoom: cameraUIViewRef?.getCurrentZoomFactor() ?? 1.0,
                filter: referenceFilter,
                gridDivisions: gridDivisions
            )
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            overlayImage = nil
        }
        setFilterForNewImage(.original)
        gridDivisions = 0
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
            setFilterForNewImage(removed.filter)
            gridDivisions = removed.gridDivisions
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            overlayImage = removed.image
        }
        imageStorage.loadedImageName = removed.loadedImageName
        cameraUIViewRef?.setZoomFactor(removed.cameraZoom)
    }

    func loadConfiguration(_ configuration: SavedImageConfiguration) {
        if let image = imageStorage.loadImage(named: configuration.imageName) {
            // Older saves have no filter: they load as Original
            setFilterForNewImage(configuration.filter.flatMap(ReferenceFilter.init(rawValue:)) ?? .original)
            let savedGrid = configuration.gridDivisions ?? 0
            gridDivisions = [3, 4].contains(savedGrid) ? savedGrid : 0
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
                    setFilterForNewImage(.original) // a fresh image starts unfiltered
                    gridDivisions = 0
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
            filter: referenceFilter.rawValue,
            gridDivisions: gridDivisions,
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

