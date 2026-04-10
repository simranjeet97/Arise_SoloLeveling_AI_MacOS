import SwiftUI
import AppKit

// MARK: - App Entry Point

@main
struct ARISEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No primary WindowGroup — ARISE lives entirely in the menu bar.
        // The Settings scene gives us a programmatic "open window" handle for
        // the main Dashboard, which AppDelegate opens on demand.
        Settings {
            EmptyView()
        }
    }
}
