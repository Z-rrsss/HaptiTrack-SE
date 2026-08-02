import AppKit

/// Owns the app-wide objects and wires the menu bar item to the feature modules.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let settings = SettingsStore.shared
    private var scrollHaptics: ScrollHapticsController?
    private var edgeControls: EdgeControlsController?
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private let launchAnimation = LaunchAnimationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit test bundle uses the app as its test host, so `main.swift`
        // runs before the tests do. Nothing here is needed to exercise the
        // logic under test, and creating the menu bar item would leave stray UI
        // behind, so the whole launch sequence is skipped under XCTest.
        guard !isRunningUnitTests else { return }

        let scrollHaptics = ScrollHapticsController(settings: settings)
        let edgeControls = EdgeControlsController(settings: settings)
        let settingsWindowController = SettingsWindowController(
            settings: settings,
            scrollHaptics: scrollHaptics,
            edgeControls: edgeControls
        )

        statusItemController = StatusItemController(
            settings: settings,
            scrollHaptics: scrollHaptics,
            edgeControls: edgeControls,
            openSettings: { settingsWindowController.show() }
        )
        self.scrollHaptics = scrollHaptics
        self.edgeControls = edgeControls
        self.settingsWindowController = settingsWindowController

        // The menu bar item is up by now, so the app is already usable. The
        // intro is deliberately in front of the rest of the sequence rather
        // than alongside it: it covers the whole screen, and a permission alert
        // put up behind it would spend two seconds hidden under a vignette.
        launchAnimation.play { [weak self] in
            self?.startModules()
        }
    }

    /// Everything that needs a permission, and the modules that ask for them.
    private func startModules() {
        // Asking on first launch explains the permission in context, next to
        // the reason the app was just installed. On later launches the system
        // alert is suppressed and this is a no-op.
        if settings.isScrollHapticsEnabled, !AccessibilityAuthorization.isTrusted {
            AccessibilityAuthorization.requestIfNeeded()
        }

        scrollHaptics?.applySettings()
        edgeControls?.applySettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        launchAnimation.cancel()
        scrollHaptics?.stop()
        edgeControls?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}
