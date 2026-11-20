//
//  OrientationLock.swift
//  Tracey
//
//  Freezes the interface orientation while the reference is locked, so turning the device
//  can't re-lay out the screen and break the alignment with the paper. iPhone is portrait-only
//  (Info.plist); this matters on iPad, which supports every orientation.
//

import UIKit

enum OrientationLock {
    /// Orientations the app allows right now (read by the app delegate).
    private(set) static var mask: UIInterfaceOrientationMask = infoPlistMask

    /// What Info.plist declares for this device (portrait-only on iPhone). The app delegate's
    /// answer overrides Info.plist, so the unfrozen mask has to come from there.
    private static let infoPlistMask: UIInterfaceOrientationMask = {
        let suffix = UIDevice.current.userInterfaceIdiom == .pad ? "~ipad" : "~iphone"
        let info = Bundle.main.infoDictionary ?? [:]
        let names = (info["UISupportedInterfaceOrientations" + suffix] ?? info["UISupportedInterfaceOrientations"]) as? [String] ?? []
        var mask: UIInterfaceOrientationMask = []
        for name in names {
            switch name {
            case "UIInterfaceOrientationPortrait": mask.insert(.portrait)
            case "UIInterfaceOrientationPortraitUpsideDown": mask.insert(.portraitUpsideDown)
            case "UIInterfaceOrientationLandscapeLeft": mask.insert(.landscapeLeft)
            case "UIInterfaceOrientationLandscapeRight": mask.insert(.landscapeRight)
            default: break
            }
        }
        return mask.isEmpty ? .portrait : mask
    }()

    /// Locks to the current interface orientation, or releases the lock.
    static func freeze(_ frozen: Bool) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ??
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        if frozen, let orientation = scene?.interfaceOrientation,
           let current = Self.mask(for: orientation), infoPlistMask.contains(current) {
            mask = current
        } else {
            mask = infoPlistMask
        }
        for window in scene?.windows ?? [] {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    private static func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask? {
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return nil
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
