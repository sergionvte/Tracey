//
//  LayoutScreenshotTests.swift
//  TraceyUITests
//
//  Walks the main screens in portrait and landscape and attaches a screenshot of each, to
//  check the layout on iPad (and iPhone) without driving the simulator by hand.
//  The image part starts with a sample reference (a Debug-only launch argument), so it doesn't
//  depend on the simulator's photo library.
//

import XCTest

final class LayoutScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(es)", "-AppleLocale", "es_MX"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testMainScreensInBothOrientations() throws {
        let skip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Omitir'")).firstMatch
        if skip.waitForExistence(timeout: 20) { skip.tap() }

        let choose = app.buttons["Elegir imagen"].firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 10), "Empty state didn't appear")
        snapshot("1 vacio vertical")
        rotate(.landscapeLeft)
        snapshot("2 vacio horizontal")
        rotate(.portrait)

        // Settings: icon picker, special edition, help and privacy
        app.buttons["Configuración"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Configuración"].waitForExistence(timeout: 5), "Settings didn't open")
        XCTAssertTrue(app.buttons["Política de privacidad"].exists || app.links["Política de privacidad"].exists,
                      "Privacy policy missing from Settings")
        settle()
        snapshot("3 configuracion vertical")
        app.buttons["Listo"].firstMatch.tap()

        // Relaunch with a sample reference loaded
        app.terminate()
        app.launchArguments += ["-TraceySampleReference"]
        app.launch()
        let more = app.buttons["Más"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 20), "The sample reference didn't load")
        let adjust = app.buttons["Ajustar imagen"].firstMatch
        settle()
        snapshot("4 imagen vertical")

        rotate(.landscapeLeft)
        snapshot("5 imagen horizontal")

        adjust.tap()
        settle()
        snapshot("6 ajustar horizontal")
        adjust.tap()
        settle()

        more.tap()
        settle()
        snapshot("7 menu horizontal")
        XCTAssertTrue(app.buttons["Configuración"].exists, "Settings missing from the ⋯ menu")
    }

    /// Picks another icon in Settings, checks iOS confirms the change, shows the home screen,
    /// then puts the primary icon back
    @MainActor
    func testChangingTheAppIcon() throws {
        let skip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Omitir'")).firstMatch
        if skip.waitForExistence(timeout: 20) { skip.tap() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        app.buttons["Configuración"].firstMatch.tap()
        let indigo = app.buttons["Índigo"].firstMatch
        XCTAssertTrue(indigo.waitForExistence(timeout: 5), "Icon picker missing")
        indigo.tap()

        // iOS confirms every icon change with its own alert
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "iOS didn't confirm the icon change")
        snapshot("icono cambiado aviso")
        alert.buttons.firstMatch.tap()
        XCTAssertTrue(indigo.isSelected, "Índigo isn't shown as selected")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        snapshot("icono cambiado inicio")

        app.activate()
        let amber = app.buttons["Ámbar"].firstMatch
        XCTAssertTrue(amber.waitForExistence(timeout: 5))
        amber.tap()
        if alert.waitForExistence(timeout: 10) { alert.buttons.firstMatch.tap() }
    }

    private func rotate(_ orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        settle()
    }

    /// Lets springs and glass transitions finish before a screenshot
    private func settle() {
        _ = app.wait(for: .runningForeground, timeout: 1.5)
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
