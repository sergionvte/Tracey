//
//  ImageStorageManager.swift
//  DrawingReference
//
//  Created by Sergio Navarrete on 31/05/25.
//

// ImageStorageManager.swift - Con posición
import SwiftUI
import Foundation

class ImageStorageManager: ObservableObject {
    @Published var savedConfigurations: [SavedImageConfiguration] = []
    
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let configurationsFileName = "savedConfigurations.json"
    
    init() {
        loadConfigurations()
    }
    
    func saveImageConfiguration(image: UIImage, opacity: Double, scale: Double, rotation: Double, offsetX: Double = 0, offsetY: Double = 0) -> Bool {
        // Generar nombre único para la imagen
        let imageName = "image_\(UUID().uuidString).jpg"
        let imageURL = documentsDirectory.appendingPathComponent(imageName)
        
        // Guardar imagen
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return false }
        
        do {
            try imageData.write(to: imageURL)
            
            // Crear configuración
            let configuration = SavedImageConfiguration(
                imageName: imageName,
                opacity: opacity,
                scale: scale,
                rotation: rotation,
                offsetX: offsetX,
                offsetY: offsetY
            )
            
            // Agregar a la lista
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
        // Eliminar imagen del disco
        let imageURL = documentsDirectory.appendingPathComponent(configuration.imageName)
        try? FileManager.default.removeItem(at: imageURL)
        
        // Eliminar de la lista
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
