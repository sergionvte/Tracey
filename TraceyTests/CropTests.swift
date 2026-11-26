import Foundation
import Testing
import UIKit
@testable import Tracey

/// A `width`×`height` image, left half red and right half blue (in pixel order).
private func halves(width: Int, height: Int, orientation: UIImage.Orientation = .up) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let raw = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        UIColor.blue.setFill()
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    }
    return UIImage(cgImage: raw.cgImage!, scale: 1, orientation: orientation)
}

private func isRed(_ p: TestPixels.Pixel) -> Bool { p.r > 0.9 && p.g < 0.1 && p.b < 0.1 }
private func isBlue(_ p: TestPixels.Pixel) -> Bool { p.b > 0.9 && p.r < 0.1 && p.g < 0.1 }

struct ImageCroppingTests {

    @Test func cropTakesTheRightPixels() throws {
        let image = halves(width: 40, height: 20)
        let cropped = try #require(ImageCropping.crop(image, to: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)))
        let pixels = try #require(TestPixels(cropped))
        #expect(pixels.width == 20 && pixels.height == 20)
        #expect(pixels.all.allSatisfy(isBlue))
    }

    @Test func fullRectKeepsTheImage() throws {
        let image = halves(width: 40, height: 20)
        let cropped = try #require(ImageCropping.crop(image, to: ImageCropping.unitRect))
        #expect(cropped.size == image.size)
    }

    @Test func cropRespectsExifOrientation() throws {
        // Raw 40×20 (red left, blue right) shown rotated 90° clockwise: 20×40, red on top
        let rotated = halves(width: 40, height: 20, orientation: .right)
        let upright = ImageCropping.normalizedUp(rotated)
        #expect(upright.imageOrientation == .up)
        #expect(upright.size == CGSize(width: 20, height: 40))
        let top = try #require(ImageCropping.crop(upright, to: CGRect(x: 0, y: 0, width: 1, height: 0.5)))
        let pixels = try #require(TestPixels(top))
        #expect(pixels.all.allSatisfy(isRed))
    }

    @Test func cropKeepsRemainingPartInPlace() {
        // 400×400 source fills a 400×800 layout at scale 1 (1 pt per pixel). Keeping the right
        // half: 200×400 would fit at 2 pt/px, so scale halves to keep 1 pt/px, and the image
        // center moves 100 pt right, where that half already was.
        let result = ImageCropping.placementAfterCrop(
            sourceSize: CGSize(width: 400, height: 400), oldCrop: ImageCropping.unitRect,
            newCrop: CGRect(x: 0.5, y: 0, width: 0.5, height: 1), layoutSize: CGSize(width: 400, height: 800),
            scale: 1, offset: .zero, rotation: 0, isFlipped: false, isFlippedVertically: false)
        #expect(abs(result.scale - 0.5) < 0.0001)
        #expect(abs(result.offset.width - 100) < 0.01)
        #expect(abs(result.offset.height) < 0.01)
    }

    @Test func cropShiftFollowsRotationAndMirror() {
        let rotated = ImageCropping.placementAfterCrop(
            sourceSize: CGSize(width: 400, height: 400), oldCrop: ImageCropping.unitRect,
            newCrop: CGRect(x: 0.5, y: 0, width: 0.5, height: 1), layoutSize: CGSize(width: 400, height: 800),
            scale: 1, offset: CGSize(width: 10, height: 20), rotation: 90, isFlipped: false, isFlippedVertically: false)
        #expect(abs(rotated.offset.width - 10) < 0.01)
        #expect(abs(rotated.offset.height - 120) < 0.01)

        let mirrored = ImageCropping.placementAfterCrop(
            sourceSize: CGSize(width: 400, height: 400), oldCrop: ImageCropping.unitRect,
            newCrop: CGRect(x: 0.5, y: 0, width: 0.5, height: 1), layoutSize: CGSize(width: 400, height: 800),
            scale: 1, offset: .zero, rotation: 0, isFlipped: true, isFlippedVertically: false)
        #expect(abs(mirrored.offset.width + 100) < 0.01)
    }

    @Test func recropFromAnEarlierCropKeepsScaleConsistent() {
        // Going back from the right half to the full image restores the original placement
        let back = ImageCropping.placementAfterCrop(
            sourceSize: CGSize(width: 400, height: 400), oldCrop: CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
            newCrop: ImageCropping.unitRect, layoutSize: CGSize(width: 400, height: 800),
            scale: 0.5, offset: CGSize(width: 100, height: 0), rotation: 0, isFlipped: false, isFlippedVertically: false)
        #expect(abs(back.scale - 1) < 0.0001)
        #expect(abs(back.offset.width) < 0.01)
    }

    @Test func aspectRatios() {
        let source = CGSize(width: 300, height: 200)
        #expect(CropAspect.free.ratio(sourceSize: source, landscape: false) == nil)
        #expect(CropAspect.original.ratio(sourceSize: source, landscape: false) == 1.5)
        #expect(abs(CropAspect.letter.ratio(sourceSize: source, landscape: false)! - 8.5 / 11) < 0.0001)
        #expect(abs(CropAspect.a4.ratio(sourceSize: source, landscape: true)! - 297 / 210) < 0.0001)
        #expect(CropAspect.square.ratio(sourceSize: source, landscape: true) == 1)
    }
}

/// Uses the app's Library on the test device, so it doesn't run in parallel
@Suite(.serialized)
struct CropModelTests {

    @Test func newImageStartsUncropped() {
        let viewModel = CameraViewModel()
        viewModel.selectedImageFromGallery = halves(width: 40, height: 20)
        #expect(viewModel.cropRect == ImageCropping.unitRect)
        #expect(viewModel.sourceImage?.size == CGSize(width: 40, height: 20))
        #expect(viewModel.overlayImage?.size == CGSize(width: 40, height: 20))
    }

    @Test func cropKeepsTheOriginalAndUndoes() throws {
        let viewModel = CameraViewModel()
        viewModel.selectedImageFromGallery = halves(width: 40, height: 20)
        let undo = try #require(viewModel.applyCrop(CGRect(x: 0.5, y: 0, width: 0.5, height: 1), layoutSize: CGSize(width: 400, height: 800)))
        #expect(viewModel.overlayImage?.size == CGSize(width: 20, height: 20))
        #expect(viewModel.sourceImage?.size == CGSize(width: 40, height: 20))
        viewModel.undoCrop(undo)
        #expect(viewModel.cropRect == ImageCropping.unitRect)
        #expect(viewModel.overlayImage?.size == CGSize(width: 40, height: 20))
        #expect(abs(viewModel.imageScale - 1) < 0.0001)
    }

    @Test func cropRectSurvivesSavingAndLoading() throws {
        let viewModel = CameraViewModel()
        viewModel.selectedImageFromGallery = halves(width: 40, height: 20)
        let rect = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        _ = viewModel.applyCrop(rect, layoutSize: CGSize(width: 400, height: 800))
        #expect(viewModel.saveCurrentConfiguration(cameraZoom: 1))
        let saved = try #require(viewModel.imageStorage.savedConfigurations.last)
        defer { viewModel.imageStorage.deleteConfiguration(saved) }
        #expect(saved.cropRect == rect)

        let fresh = CameraViewModel()
        fresh.loadConfiguration(saved)
        #expect(fresh.cropRect == rect)
        #expect(fresh.sourceImage?.size == CGSize(width: 40, height: 20))
        let shown = try #require(fresh.overlayImage)
        #expect(shown.size == CGSize(width: 20, height: 20))
        // The saved file is the full photo: the crop is applied when loading
        #expect(viewModel.imageStorage.loadImage(named: saved.imageName)?.size == CGSize(width: 40, height: 20))
    }

    @Test func oldSavesLoadUncropped() throws {
        let json = """
        {"id":"9A0B6B32-3C3F-4C7E-9B7B-2D6A4B2F1E11","imageName":"a.jpg","opacity":0.6,"scale":1,
         "rotation":0,"offsetX":0,"offsetY":0,"isFlipped":false,"dateCreated":0,"cameraZoom":1}
        """
        let config = try JSONDecoder().decode(SavedImageConfiguration.self, from: Data(json.utf8))
        #expect(config.cropRect == nil)
    }

    @Test func undoRemoveBringsTheCropBack() throws {
        let viewModel = CameraViewModel()
        viewModel.selectedImageFromGallery = halves(width: 40, height: 20)
        let rect = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        _ = viewModel.applyCrop(rect, layoutSize: CGSize(width: 400, height: 800))
        let removed = try #require(viewModel.removeOverlayImage())
        viewModel.restore(removed)
        #expect(viewModel.cropRect == rect)
        #expect(viewModel.sourceImage?.size == CGSize(width: 40, height: 20))
        #expect(viewModel.overlayImage?.size == CGSize(width: 20, height: 20))
    }
}
