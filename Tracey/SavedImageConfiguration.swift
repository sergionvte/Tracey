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

    init(imageName: String, opacity: Double, scale: Double, rotation: Double, offsetX: Double = 0, offsetY: Double = 0, isFlipped: Bool = false, cameraZoom: CGFloat = 1.0) {
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
    }

    // Nuevo init para sobrescribir manteniendo id y fecha
    init(id: UUID, imageName: String, opacity: Double, scale: Double, rotation: Double, offsetX: Double, offsetY: Double, isFlipped: Bool, dateCreated: Date, cameraZoom: CGFloat) {
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
    }
}
