import Foundation
import Testing
import UIKit
@testable import Tracey

struct PlacementModelTests {

    @Test func placementAppliesAndUndoes() throws {
        let viewModel = CameraViewModel()
        viewModel.selectedImageFromGallery = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 40)).image { _ in }
        viewModel.imageRotation = 15
        let undo = viewModel.applyPlacement(offset: CGSize(width: 12, height: -8), scale: 0.6, rotation: 352)
        #expect(viewModel.imageOffset == CGSize(width: 12, height: -8))
        #expect(abs(viewModel.imageScale - 0.6) < 0.0001)
        #expect(abs(viewModel.imageRotation - 352) < 0.0001)

        viewModel.undoPlacement(undo)
        #expect(viewModel.imageOffset == .zero)
        #expect(abs(viewModel.imageScale - 1) < 0.0001)
        #expect(abs(viewModel.imageRotation - 15) < 0.0001)
    }

    @Test func undoIsIgnoredForAnotherImage() {
        let viewModel = CameraViewModel()
        viewModel.selectedImageFromGallery = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 40)).image { _ in }
        let undo = viewModel.applyPlacement(offset: CGSize(width: 12, height: -8), scale: 0.6, rotation: 10)
        viewModel.selectedImageFromGallery = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 40)).image { _ in }
        viewModel.undoPlacement(undo)
        #expect(viewModel.imageOffset == .zero)
        #expect(abs(viewModel.imageScale - 1) < 0.0001)
    }
}
