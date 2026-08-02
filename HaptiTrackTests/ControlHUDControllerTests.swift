import AppKit
import XCTest
@testable import HaptiTrack

/// Drives the real HUD — real overlay window and all — with the rest interval
/// wound down from most of a second to a hundredth of one.
@MainActor
final class ControlHUDControllerTests: XCTestCase {

    private let restDuration: TimeInterval = 0.01

    private func makeController() -> ControlHUDController {
        ControlHUDController(restDuration: restDuration)
    }

    private func presentation(_ value: Double) -> ControlHUDPresentation {
        ControlHUDPresentation(title: "Volume", symbolName: "speaker.wave.2.fill", value: value)
    }

    /// The roll-up is animated, so going down takes a moment after the rest
    /// interval expires.
    private func waitForDismissal() async {
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    func testShowingPutsItOnScreen() {
        let controller = makeController()

        controller.show(presentation(0.5))

        XCTAssertTrue(controller.isVisible)
        controller.tearDown()
    }

    func testItTakesItselfDownWithNoInputAtAll() async {
        let controller = makeController()

        controller.show(presentation(0.5))
        await waitForDismissal()

        XCTAssertFalse(controller.isVisible, "The HUD has to close itself; nothing dismisses it")
        controller.tearDown()
    }

    func testEachChangeKeepsItUpABitLonger() async {
        let controller = makeController()

        // Four notches in a row, each arriving before the last would have
        // expired: the HUD stays up through the whole sweep.
        for step in 1...4 {
            controller.show(presentation(Double(step) / 4))
            try? await Task.sleep(nanoseconds: 5_000_000)
            XCTAssertTrue(controller.isVisible)
        }

        await waitForDismissal()
        XCTAssertFalse(controller.isVisible)
        controller.tearDown()
    }

    func testTearingDownIsImmediateAndRepeatable() {
        let controller = makeController()

        controller.show(presentation(0.5))
        controller.tearDown()
        XCTAssertFalse(controller.isVisible)

        // Switching the module off twice must not trip over itself.
        controller.tearDown()
        XCTAssertFalse(controller.isVisible)
    }

    func testItComesBackAfterBeingTornDown() {
        let controller = makeController()

        controller.show(presentation(0.2))
        controller.tearDown()
        controller.show(presentation(0.8))

        XCTAssertTrue(controller.isVisible, "Switching the module back on has to work")
        controller.tearDown()
    }

    func testTheOverlayNeverTakesFocus() {
        let controller = makeController()
        controller.show(presentation(0.5))

        let overlay = NSApp.windows.first { $0.level == .screenSaver && $0.isVisible }
        let panel = try? XCTUnwrap(overlay)

        XCTAssertEqual(panel?.canBecomeKey, false)
        XCTAssertEqual(panel?.ignoresMouseEvents, true)
        controller.tearDown()
    }
}
