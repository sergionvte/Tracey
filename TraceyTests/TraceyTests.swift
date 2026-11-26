import Foundation
import Testing
import UIKit
@testable import Tracey

@Test func newReferencesStartHalfTransparent() {
    #expect(CameraViewModel.defaultOpacity == 0.5)
}

struct SavedConfigurationMirrorTests {

    @Test func referencesSavedBeforeVerticalMirrorLoadUnmirrored() throws {
        // A save from before the vertical mirror existed: no isFlippedVertically key
        let json = """
        {"id":"9A0B6B32-3C3F-4C7E-9B7B-2D6A4B2F1E11","imageName":"a.jpg","opacity":0.6,"scale":1,
         "rotation":0,"offsetX":0,"offsetY":0,"isFlipped":true,"dateCreated":0,"cameraZoom":1}
        """
        let config = try JSONDecoder().decode(SavedImageConfiguration.self, from: Data(json.utf8))
        #expect(config.isFlipped)
        #expect(config.isFlippedVertically == false)
    }

    @Test func verticalMirrorSurvivesSaving() throws {
        let saved = SavedImageConfiguration(imageName: "a.jpg", opacity: 0.6, scale: 1, rotation: 0,
                                            isFlipped: false, isFlippedVertically: true)
        let data = try JSONEncoder().encode(saved)
        let loaded = try JSONDecoder().decode(SavedImageConfiguration.self, from: data)
        #expect(loaded.isFlippedVertically)
        #expect(!loaded.isFlipped)
    }
}

struct AppIconChoiceTests {

    /// Alternate icons the build actually ships (iPhone and iPad keys)
    private var shippedAlternateIcons: Set<String> {
        let info = Bundle.main.infoDictionary ?? [:]
        var names = Set<String>()
        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            let icons = info[key] as? [String: Any]
            let alternates = icons?["CFBundleAlternateIcons"] as? [String: Any] ?? [:]
            names.formUnion(alternates.keys)
        }
        return names
    }

    @Test func primaryIconIsTheDefault() {
        #expect(AppIconChoice.amber.alternateName == nil)
        #expect(AppIconChoice(alternateName: nil) == .amber)
    }

    @Test(arguments: AppIconChoice.allCases.filter { $0 != .amber })
    func everyAlternateIconShipsInTheApp(_ choice: AppIconChoice) throws {
        let name = try #require(choice.alternateName)
        #expect(shippedAlternateIcons.contains(name), "\(name) is missing from the built app")
        #expect(AppIconChoice(alternateName: name) == choice)
    }

    @Test(arguments: AppIconChoice.allCases)
    func everyChoiceHasAPreviewImage(_ choice: AppIconChoice) {
        #expect(UIImage(named: choice.previewImageName) != nil)
    }

    @Test func onlyTheNotebookIsASpecialEdition() {
        #expect(AppIconChoice.allCases.filter(\.isSpecialEdition) == [.notebook])
    }

    @Test func unknownIconNameFallsBackToThePrimaryIcon() {
        #expect(AppIconChoice(alternateName: "AppIcon-Removed") == .amber)
    }
}

struct RotationSliderTests {
    @Test func halfTurnStaysOnTheEndItWasDraggedTo() {
        #expect(AdjustPanel.signedRotation(180, halfTurnIsNegative: true) == -180)
        #expect(AdjustPanel.signedRotation(180, halfTurnIsNegative: false) == 180)
    }

    @Test func otherAnglesAreSignedAroundZero() {
        #expect(AdjustPanel.signedRotation(0, halfTurnIsNegative: true) == 0)
        #expect(AdjustPanel.signedRotation(90, halfTurnIsNegative: true) == 90)
        #expect(AdjustPanel.signedRotation(270, halfTurnIsNegative: false) == -90)
        #expect(AdjustPanel.signedRotation(.nan, halfTurnIsNegative: false) == 0)
    }
}
