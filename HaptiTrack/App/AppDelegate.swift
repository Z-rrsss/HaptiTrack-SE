import AppKit

/// Owns the app-wide objects and wires the menu bar item to the feature modules.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit test bundle uses the app as its test host, so `main.swift`
        // runs before the tests do. Nothing here is needed to exercise the
        // logic under test, and creating the menu bar item would leave stray UI
        // behind, so the whole launch sequence is skipped under XCTest.
        guard !isRunningUnitTests else { return }

        statusItemController = StatusItemController()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}
