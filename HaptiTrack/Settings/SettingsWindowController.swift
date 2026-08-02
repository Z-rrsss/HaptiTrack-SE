import AppKit
import SwiftUI

/// Hosts `SettingsView` in a plain utility window.
///
/// An agent app has no `Settings` scene to fall back on, so the window is built
/// by hand and kept around after it is closed: reopening it should restore what
/// the user was looking at rather than rebuild it.
@MainActor
final class SettingsWindowController {

    private let settings: SettingsStore
    private let scrollHaptics: ScrollHapticsController
    private let edgeControls: EdgeControlsController
    private var window: NSWindow?

    init(
        settings: SettingsStore,
        scrollHaptics: ScrollHapticsController,
        edgeControls: EdgeControlsController
    ) {
        self.settings = settings
        self.scrollHaptics = scrollHaptics
        self.edgeControls = edgeControls
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window

        // Without this an agent app can order the window front but never get
        // keyboard focus for it.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                scrollHaptics: scrollHaptics,
                edgeControls: edgeControls
            )
        )
        let window = NSWindow(contentViewController: controller)
        window.title = "\(AppInfo.name) Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
