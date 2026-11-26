//
//  SavedImageConfiguration.swift
//  DrawingReference
//
//  Created by Sergio Navarrete on 31/05/25.
//

// SavedImageConfiguration.swift - Con posición
import SwiftUI
import Foundation

struct SavedImageConfiguration: Codable, Identifiable {
    let id: UUID
    let imageName: String
    let opacity: Double
    let scale: Double
    let rotation: Double
    let offsetX: Double
    let offsetY: Double
    let isFlipped: Bool // Nuevo campo para flip horizontal
    let dateCreated: Date
    let cameraZoom: CGFloat // Nuevo campo para el zoom de la cámara
    let captureMode: CameraCaptureMode? // Optional so configurations saved before this field still decode
    /// ReferenceFilter raw value (nil in older saves = Original)
    let filter: String?
    /// Grid divisions (3 or 4); nil or 0 = off
    let gridDivisions: Int?
    /// Vertical mirror (nil in older saves = not mirrored)
    let verticalMirror: Bool?
    var isFlippedVertically: Bool { verticalMirror ?? false }
    /// Outline filter detail (nil in older saves = the middle)
    let outlineDetail: Double?
    /// Outline line color (nil in older saves = blue)
    let outlineColor: OutlineColor?
    /// Part of the image that is shown, normalized (nil in older saves = the whole image).
    /// The saved file is always the full photo.
    let cropRect: CGRect?
    var outlineStyle: OutlineStyle {
        OutlineStyle(detail: outlineDetail ?? 0.5, color: outlineColor ?? .blue)
    }

    init(imageName: String, opacity: Double, scale: Double, rotation: Double, offsetX: Double = 0, offsetY: Double = 0, isFlipped: Bool = false, isFlippedVertically: Bool = false, cameraZoom: CGFloat = 1.0, captureMode: CameraCaptureMode? = nil, filter: String? = nil, gridDivisions: Int? = nil, outlineStyle: OutlineStyle = OutlineStyle(), cropRect: CGRect? = nil) {
        self.id = UUID()
        self.imageName = imageName
        self.opacity = opacity
        self.scale = scale
        self.rotation = rotation
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.isFlipped = isFlipped
        self.dateCreated = Date()
        self.cameraZoom = cameraZoom
        self.captureMode = captureMode
        self.filter = filter
        self.gridDivisions = gridDivisions
        self.verticalMirror = isFlippedVertically
        self.outlineDetail = outlineStyle.detail
        self.outlineColor = outlineStyle.color
        self.cropRect = cropRect
    }

    // Nuevo init para sobrescribir manteniendo id y fecha
    init(id: UUID, imageName: String, opacity: Double, scale: Double, rotation: Double, offsetX: Double, offsetY: Double, isFlipped: Bool, isFlippedVertically: Bool, dateCreated: Date, cameraZoom: CGFloat, captureMode: CameraCaptureMode?, filter: String?, gridDivisions: Int?, outlineStyle: OutlineStyle, cropRect: CGRect?) {
        self.id = id
        self.imageName = imageName
        self.opacity = opacity
        self.scale = scale
        self.rotation = rotation
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.isFlipped = isFlipped
        self.dateCreated = dateCreated
        self.cameraZoom = cameraZoom
        self.captureMode = captureMode
        self.filter = filter
        self.gridDivisions = gridDivisions
        self.verticalMirror = isFlippedVertically
        self.outlineDetail = outlineStyle.detail
        self.outlineColor = outlineStyle.color
        self.cropRect = cropRect
    }
}
