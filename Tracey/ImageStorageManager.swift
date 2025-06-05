//
//  ImageStorageManager.swift
//  DrawingReference
//
//  Created by Sergio Navarrete on 31/05/25.
//

import SwiftUI
import Foundation

// Asegúrate de que SavedImageConfiguration.swift esté en el mismo target que ImageStorageManager.swift

class ImageStorageManager: ObservableObject {
    @Published var savedConfigurations: [SavedImageConfiguration] = []

    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let configurationsFileName = "savedConfigurations.json"

    // Store the name of the currently loaded image
    var loadedImageName: String? = nil

    init() {
        loadConfigurations()
    }

    // MARK: - Overwrite if a configuration with the same image already exists
    func saveImageConfiguration(image: UIImage, opacity: Double, scale: Double, rotation: Double, offsetX: Double = 0, offsetY: Double = 0, isFlipped: Bool = false, cameraZoom: CGFloat = 1.0, overwriteImageName: String? = nil) -> Bool {
        let imageName: String
        if let overwriteName = overwriteImageName {
            imageName = overwriteName
        } else {
            imageName = "image_\(UUID().uuidString).jpg"
        }
        let imageURL = documentsDirectory.appendingPathComponent(imageName)

        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return false }

        do {
            try imageData.write(to: imageURL)

            if let overwriteName = overwriteImageName, let idx = savedConfigurations.firstIndex(where: { $0.imageName == overwriteName }) {
                let oldConfig = savedConfigurations[idx]
                let newConfig = SavedImageConfiguration(
                    id: oldConfig.id,
                    imageName: imageName,
                    opacity: opacity,
                    scale: scale,
                    rotation: rotation,
                    offsetX: offsetX,
                    offsetY: offsetY,
                    isFlipped: isFlipped,
                    dateCreated: oldConfig.dateCreated,
                    cameraZoom: cameraZoom
                )
                savedConfigurations[idx] = newConfig
                saveConfigurations()
                return true
            }

            let configuration = SavedImageConfiguration(
                imageName: imageName,
                opacity: opacity,
                scale: scale,
                rotation: rotation,
                offsetX: offsetX,
                offsetY: offsetY,
                isFlipped: isFlipped,
                cameraZoom: cameraZoom
            )
            savedConfigurations.append(configuration)
            saveConfigurations()
            return true
        } catch {
            print("Error saving image: \(error)")
            return false
        }
    }

    func loadImage(named imageName: String) -> UIImage? {
        let imageURL = documentsDirectory.appendingPathComponent(imageName)
        return UIImage(contentsOfFile: imageURL.path)
    }

    func deleteConfiguration(_ configuration: SavedImageConfiguration) {
        // Delete image from disk
        let imageURL = documentsDirectory.appendingPathComponent(configuration.imageName)
        try? FileManager.default.removeItem(at: imageURL)

        // Remove from the list
        savedConfigurations.removeAll { $0.id == configuration.id }
        saveConfigurations()
    }

    private func saveConfigurations() {
        let configurationsURL = documentsDirectory.appendingPathComponent(configurationsFileName)

        do {
            let data = try JSONEncoder().encode(savedConfigurations)
            try data.write(to: configurationsURL)
        } catch {
            print("Error saving configurations: \(error)")
        }
    }

    private func loadConfigurations() {
        let configurationsURL = documentsDirectory.appendingPathComponent(configurationsFileName)

        do {
            let data = try Data(contentsOf: configurationsURL)
            savedConfigurations = try JSONDecoder().decode([SavedImageConfiguration].self, from: data)
        } catch {
            print("Error loading configurations: \(error)")
            savedConfigurations = []
        }
    }
}
