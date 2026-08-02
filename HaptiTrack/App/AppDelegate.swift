import AppKit

/// Owns the app-wide objects and wires the menu bar item to the feature modules.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let settings = SettingsStore.shared
    private var scrollHaptics: ScrollHapticsController?
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit test bundle uses the app as its test host, so `main.swift`
        // runs before the tests do. Nothing here is needed to exercise the
        // logic under test, and creating the menu bar item would leave stray UI
        // behind, so the whole launch sequence is skipped under XCTest.
        guard !isRunningUnitTests else { return }

        let scrollHaptics = ScrollHapticsController(settings: settings)
        let settingsWindowController = SettingsWindowController(
            settings: settings,
            scrollHaptics: scrollHaptics
        )

        statusItemController = StatusItemController(
            settings: settings,
            scrollHaptics: scrollHaptics,
            openSettings: { settingsWindowController.show() }
        )
        self.scrollHaptics = scrollHaptics
        self.settingsWindowController = settingsWindowController

        // Asking on first launch explains the permission in context, next to
        // the reason the app was just installed. On later launches the system
        // alert is suppressed and this is a no-op.
        if settings.isScrollHapticsEnabled, !AccessibilityAuthorization.isTrusted {
            AccessibilityAuthorization.requestIfNeeded()
        }

        scrollHaptics.applySettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scrollHaptics?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}
