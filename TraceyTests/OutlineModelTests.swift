import Foundation
import Testing
import UIKit
@testable import Tracey

/// Touches the shared preferred-color default, so its tests don't run in parallel
@Suite(.serialized)
struct OutlineModelTests {

    private static func sampleImage(_ color: UIColor = .gray) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
    }

    private func withPreferred(_ color: OutlineColor, _ body: () throws -> Void) rethrows {
        let previous = OutlineColor.preferred
        OutlineColor.preferred = color
        defer { OutlineColor.preferred = previous }
        try body()
    }

    @Test func newImageStartsWithPreferredColorAndMiddleDetail() {
        withPreferred(.red) {
            let viewModel = CameraViewModel()
            viewModel.setOutlineDetail(0.9)
            viewModel.selectedImageFromGallery = Self.sampleImage()
            #expect(viewModel.outlineStyle == OutlineStyle(detail: 0.5, color: .red))
        }
    }

    @Test func choosingAColorMakesItThePreferredOne() {
        withPreferred(.blue) {
            let viewModel = CameraViewModel()
            viewModel.selectedImageFromGallery = Self.sampleImage()
            viewModel.setOutlineColor(.green)
            #expect(viewModel.outlineStyle.color == .green)
            #expect(OutlineColor.preferred == .green)
        }
    }

    @Test func libraryEntryOpensWithItsOwnColorAndKeepsThePreference() throws {
        try withPreferred(.green) {
            let viewModel = CameraViewModel()
            let storage = viewModel.imageStorage
            #expect(storage.saveImageConfiguration(image: Self.sampleImage(), opacity: 0.5, scale: 1, rotation: 0,
                                                   outlineStyle: OutlineStyle(detail: 0.2, color: .red)))
            let saved = try #require(storage.savedConfigurations.last)
            defer { storage.deleteConfiguration(saved) }

            viewModel.loadConfiguration(saved)
            #expect(viewModel.outlineStyle == OutlineStyle(detail: 0.2, color: .red))
            #expect(OutlineColor.preferred == .green)
        }
    }

    @Test func undoRemoveBringsTheOutlineBack() throws {
        withPreferred(.blue) {
            let viewModel = CameraViewModel()
            viewModel.selectedImageFromGallery = Self.sampleImage()
            viewModel.setOutlineDetail(0.8)
            viewModel.setOutlineColor(.purple)
            let removed = viewModel.removeOverlayImage()
            #expect(removed != nil)
            viewModel.restore(removed!)
            #expect(viewModel.outlineStyle == OutlineStyle(detail: 0.8, color: .purple))
        }
    }

    @Test func savingStoresTheCurrentOutline() throws {
        withPreferred(.blue) {
            let viewModel = CameraViewModel()
            viewModel.selectedImageFromGallery = Self.sampleImage()
            viewModel.setOutlineDetail(0.7)
            viewModel.setOutlineColor(.black)
            #expect(viewModel.saveCurrentConfiguration(cameraZoom: 1))
            let saved = viewModel.imageStorage.savedConfigurations.last
            #expect(saved?.outlineStyle == OutlineStyle(detail: 0.7, color: .black))
            if let saved { viewModel.imageStorage.deleteConfiguration(saved) }
        }
    }
}
