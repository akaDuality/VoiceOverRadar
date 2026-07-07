import SwiftUI
import AXCore

/// A menu-bar (agent) app that shows a live, VoiceOver-style description of the
/// currently focused element in the frontmost application.
@main
struct VoiceOverInspectorApp: App {
    @StateObject private var monitor = ScreenAccessibilityMonitor()

    var body: some Scene {
        // A normal window so the app is visible during development.
        Window("VoiceOver Inspector", id: "main") {
            ContentView(monitor: monitor)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        // The menu-bar item stays available too.
        MenuBarExtra("VoiceOver Inspector", systemImage: "text.viewfinder") {
            ContentView(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
