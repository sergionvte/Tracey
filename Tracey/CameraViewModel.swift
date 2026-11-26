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

    /// The full photo as picked or loaded, upright. It is what gets saved; a crop never
    /// discards it, so cropping again can always go back to the whole photo.
    @Published private(set) var sourceImage: UIImage?
    /// Part of `sourceImage` that is used, normalized 0–1 (origin top-left)
    @Published private(set) var cropRect = ImageCropping.unitRect

    /// What is traced: `sourceImage` cut to `cropRect`. Never filtered.
    @Published var overlayImage: UIImage? = nil {
        didSet {
            if overlayImage !== oldValue { overlayImageChanged() }
        }
    }
    /// Opacity a new reference starts at (and double-tap resets to)
    static let defaultOpacity: Double = 0.5

    @Published var imageOpacity: Double = CameraViewModel.defaultOpacity {
        didSet {
            // Validar que el valor sea finito y esté en el rango correcto
            if !imageOpacity.isFinite || imageOpacity < 0 || imageOpacity > 1 {
                imageOpacity = max(0, min(oldValue.isFinite ? oldValue : Self.defaultOpacity, 1))
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
    /// While a time-lapse records, the output size is fixed: loading a reference must not
    /// switch the capture mode
    var isCaptureModeFrozen = false

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
    /// Detail and line color of the Outline filter (per reference; saved with it)
    @Published private(set) var outlineStyle = OutlineStyle(detail: 0.5, color: .preferred)

    /// Fires when a filter couldn't be applied (it falls back to Original)
    let filterFailed = PassthroughSubject<Void, Never>()

    /// Rendered filters for the current image. The outline style is part of the key only for
    /// the Outline filter.
    private struct FilterKey: Hashable {
        let filter: ReferenceFilter
        let outline: OutlineStyle?
    }
    private var filteredCache: [FilterKey: UIImage] = [:]
    private var filterGeneration = 0
    /// Slider drags and color-picker drags re-render after a short pause, not on every change
    private var outlineRenderWork: DispatchWorkItem?
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

    private func filterKey(_ filter: ReferenceFilter) -> FilterKey {
        FilterKey(filter: filter, outline: filter == .outline ? outlineStyle : nil)
    }

    /// Outline detail, 0 (main shapes) … 1 (fine lines). Re-renders shortly after the last change.
    func setOutlineDetail(_ detail: Double) {
        let clamped = detail.isFinite ? min(max(detail, 0), 1) : 0.5
        guard clamped != outlineStyle.detail else { return }
        outlineStyle.detail = clamped
        scheduleOutlineRender()
    }

    /// Outline line color. It also becomes the color new references start with.
    func setOutlineColor(_ color: OutlineColor) {
        OutlineColor.preferred = color
        guard color != outlineStyle.color else { return }
        outlineStyle.color = color
        scheduleOutlineRender()
    }

    private func scheduleOutlineRender() {
        outlineRenderWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.referenceFilter == .outline { self.updateDisplayImage(keepPrevious: true) }
            self.generateOutlineThumbnail()
        }
        outlineRenderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
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
        let key = filterKey(filter)
        let outline = outlineStyle
        if let cached = filteredCache[key] {
            displayImage = cached
            return
        }
        if !keepPrevious { displayImage = nil }
        let generation = filterGeneration
        filterQueue.async { [weak self] in
            // Long side ≤ 2048 px: plenty for an overlay, and quick to filter
            let result = ReferenceFilterRenderer.shared.render(source, filter: filter, outline: outline, maxLongSide: 2048)
            DispatchQueue.main.async {
                guard let self, self.overlayImage === source else { return }
                if let result {
                    self.filteredCache[key] = result
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
        let outline = outlineStyle
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
                    thumbnail = Self.outlineThumbnail(of: source, style: outline)
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

    // MARK: - Crop

    /// What `undoCrop` needs to go back
    struct CropUndo {
        let source: UIImage
        let cropRect: CGRect
        let scale: CGFloat
        let offset: CGSize
    }

    /// Shows only `rect` of the full photo. The part that stays keeps its place and size on
    /// screen (`layoutSize` = the overlay layout rect). Returns nil when nothing changed.
    func applyCrop(_ rect: CGRect, layoutSize: CGSize) -> CropUndo? {
        guard let source = sourceImage else { return nil }
        let newCrop = ImageCropping.sanitized(rect)
        guard newCrop != cropRect, let cropped = ImageCropping.crop(source, to: newCrop) else { return nil }
        let undo = CropUndo(source: source, cropRect: cropRect, scale: imageScale, offset: imageOffset)
        let placement = ImageCropping.placementAfterCrop(
            sourceSize: source.size, oldCrop: cropRect, newCrop: newCrop, layoutSize: layoutSize,
            scale: imageScale, offset: imageOffset, rotation: imageRotation,
            isFlipped: isFlipped, isFlippedVertically: isFlippedVertically)
        setCrop(newCrop, image: cropped, scale: placement.scale, offset: placement.offset)
        return undo
    }

    /// Back to the crop and placement before `applyCrop` (ignored if another image was loaded)
    func undoCrop(_ undo: CropUndo) {
        guard sourceImage === undo.source,
              let image = ImageCropping.crop(undo.source, to: undo.cropRect) else { return }
        setCrop(undo.cropRect, image: image, scale: undo.scale, offset: undo.offset)
    }

    private func setCrop(_ rect: CGRect, image: UIImage, scale: CGFloat, offset: CGSize) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            cropRect = rect
            imageScale = scale
            imageOffset = offset
            overlayImage = image
        }
    }

    /// Edges found at 120 px turn into a solid blob: trace at 480 px, then shrink.
    private static func outlineThumbnail(of source: UIImage, style: OutlineStyle) -> UIImage? {
        let renderer = ReferenceFilterRenderer.shared
        return renderer.render(source, filter: .outline, outline: style, maxLongSide: 480)
            .flatMap { renderer.render($0, filter: .original, maxLongSide: 120) }
    }

    /// Redraws only the Outline tile (after a detail or color change)
    private func generateOutlineThumbnail() {
        guard let source = overlayImage else { return }
        let outline = outlineStyle
        thumbnailQueue.async { [weak self] in
            let thumbnail = Self.outlineThumbnail(of: source, style: outline)
            DispatchQueue.main.async {
                guard let self, self.overlayImage === source, self.outlineStyle == outline, let thumbnail else { return }
                self.filterThumbnails[.outline] = thumbnail
            }
        }
    }

    func resetImageTransforms() {
        withAnimation(.easeInOut(duration: 0.3)) {
            imageScale = 1.0
            imageRotation = 0.0
            imageOpacity = Self.defaultOpacity
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
        let isFlippedVertically: Bool
        let loadedImageName: String?
        let cameraZoom: CGFloat
        let filter: ReferenceFilter
        let gridDivisions: Int
        let outlineStyle: OutlineStyle
        let sourceImage: UIImage?
        let cropRect: CGRect
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
                isFlippedVertically: isFlippedVertically,
                loadedImageName: imageStorage.loadedImageName,
                cameraZoom: cameraUIViewRef?.getCurrentZoomFactor() ?? 1.0,
                filter: referenceFilter,
                gridDivisions: gridDivisions,
                outlineStyle: outlineStyle,
                sourceImage: sourceImage,
                cropRect: cropRect
            )
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            overlayImage = nil
        }
        sourceImage = nil
        cropRect = ImageCropping.unitRect
        setFilterForNewImage(.original)
        gridDivisions = 0
        imageStorage.loadedImageName = nil // Limpiar referencia al nombre de imagen cargada
        isFlipped = false // Reiniciar flip horizontal al borrar
        isFlippedVertically = false
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
            isFlippedVertically = removed.isFlippedVertically
            setFilterForNewImage(removed.filter)
            gridDivisions = removed.gridDivisions
            outlineStyle = removed.outlineStyle
            sourceImage = removed.sourceImage ?? removed.image
            cropRect = removed.cropRect
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
            // The entry's own outline; loading doesn't change the preferred color
            outlineStyle = configuration.outlineStyle
            // The saved file is the full photo; show the part that was kept
            let upright = ImageCropping.normalizedUp(image)
            let crop = ImageCropping.sanitized(configuration.cropRect)
            sourceImage = upright
            cropRect = crop
            let savedGrid = configuration.gridDivisions ?? 0
            gridDivisions = [3, 4].contains(savedGrid) ? savedGrid : 0
            overlayImage = ImageCropping.crop(upright, to: crop) ?? upright
            imageStorage.loadedImageName = configuration.imageName // Guardar el nombre de la imagen cargada

            // Validar todos los valores antes de asignarlos
            imageOpacity = configuration.opacity.isFinite ? max(0, min(configuration.opacity, 1)) : Self.defaultOpacity
            imageScale = configuration.scale.isFinite && configuration.scale > 0 ? CGFloat(configuration.scale) : 1.0
            imageRotation = configuration.rotation.isFinite ? configuration.rotation : 0.0
            isFlipped = configuration.isFlipped // Cargar flip
            isFlippedVertically = configuration.isFlippedVertically

            let offsetWidth = configuration.offsetX.isFinite ? configuration.offsetX : 0.0
            let offsetHeight = configuration.offsetY.isFinite ? configuration.offsetY : 0.0
            imageOffset = CGSize(width: offsetWidth, height: offsetHeight)
            isPropertiesLocked = false // Reiniciar estado de bloqueo al cargar desde imágenes guardadas
            resetViewport()

            // Restore the capture mode the overlay was aligned with (older saves have none)
            if let savedMode = configuration.captureMode, !isCaptureModeFrozen {
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

    @Published var isFlippedVertically: Bool = false

    func flipOverlayImageVertically() {
        isFlippedVertically.toggle()
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
                    imageOpacity = Self.defaultOpacity
                    imageOffset = .zero
                    setFilterForNewImage(.original) // a fresh image starts unfiltered
                    gridDivisions = 0
                    outlineStyle = OutlineStyle(detail: 0.5, color: .preferred)
                    let upright = ImageCropping.normalizedUp(newValue)
                    sourceImage = upright
                    cropRect = ImageCropping.unitRect
                    overlayImage = upright
                }
                imageStorage.loadedImageName = nil
                isFlipped = false
                isFlippedVertically = false
                isPropertiesLocked = false
                resetViewport()
                // Reiniciar zoom al cargar desde galería
                cameraUIViewRef?.setZoomFactor(1.0)
            }
        }
    }

    func saveCurrentConfiguration(cameraZoom: CGFloat) -> Bool {
        // The full photo is stored with its crop rectangle
        guard let image = sourceImage ?? overlayImage else { return false }

        let safeOpacity = imageOpacity.isFinite ? imageOpacity : Self.defaultOpacity
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
            isFlippedVertically: isFlippedVertically,
            cameraZoom: cameraZoom,
            captureMode: captureMode,
            filter: referenceFilter.rawValue,
            gridDivisions: gridDivisions,
            outlineStyle: outlineStyle,
            cropRect: cropRect == ImageCropping.unitRect ? nil : cropRect,
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

