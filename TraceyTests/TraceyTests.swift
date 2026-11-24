import Testing
import UIKit
@testable import Tracey

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
