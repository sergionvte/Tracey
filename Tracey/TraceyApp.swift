//
//  TraceyApp.swift
//  Tracey
//
//  Created by Sergio Navarrete on 31/05/25.
//

import SwiftUI

@main
struct TraceyApp: App {
    // Only used to freeze the interface orientation while the reference is locked (iPad)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
