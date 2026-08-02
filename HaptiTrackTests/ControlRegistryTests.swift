import XCTest
@testable import HaptiTrack

/// A control that is whatever the test needs it to be, touching no hardware.
private final class StubControl: AdjustableControl {
    let identifier: ControlIdentifier
    let displayName = "Stub"
    var isAvailable: Bool
    var isSupported: Bool
    var value: Double = 0.5

    init(_ identifier: ControlIdentifier, isSupported: Bool = true, isAvailable: Bool = true) {
        self.identifier = identifier
        self.isSupported = isSupported
        self.isAvailable = isAvailable
    }
}

/// Which controls the assignment picker offers, and which it withholds.
final class ControlRegistryTests: XCTestCase {

    // MARK: - Offering controls

    func testEverySupportedControlIsOffered() {
        let registry = ControlRegistry(controls: [
            StubControl(.volume),
            StubControl(.brightness),
            StubControl(.keyboardBacklight),
        ])

        let offered = registry.assignableControls()

        XCTAssertTrue(offered.contains(.none), "Unassigning an edge is always an option")
        XCTAssertTrue(offered.contains(.volume))
        XCTAssertTrue(offered.contains(.keyboardBacklight))
    }

    func testAControlTheMacDoesNotHaveIsNotOffered() {
        // A desktop, or a notebook driving a keyboard with no backlight.
        let registry = ControlRegistry(controls: [
            StubControl(.volume),
            StubControl(.keyboardBacklight, isSupported: false, isAvailable: false),
        ])

        let offered = registry.assignableControls()

        XCTAssertFalse(
            offered.contains(.keyboardBacklight),
            "A knob that could never do anything should not be in the list at all"
        )
        XCTAssertTrue(offered.contains(.volume))
        XCTAssertTrue(offered.contains(.none))
    }

    func testAnUnsupportedControlStaysOfferedWhileAnEdgeIsSetToIt() {
        let registry = ControlRegistry(controls: [
            StubControl(.volume),
            StubControl(.keyboardBacklight, isSupported: false, isAvailable: false),
        ])

        let offered = registry.assignableControls(including: .keyboardBacklight)

        XCTAssertTrue(
            offered.contains(.keyboardBacklight),
            "Settings carried over from another Mac should show what they are, not vanish"
        )
    }

    func testAControlThatIsMerelyUnavailableIsStillOffered() {
        // An external display can take brightness away and give it back, so it
        // stays in the list with a note rather than disappearing from it.
        let registry = ControlRegistry(controls: [
            StubControl(.brightness, isSupported: true, isAvailable: false)
        ])

        XCTAssertTrue(registry.assignableControls().contains(.brightness))
        XCTAssertFalse(registry.isAvailable(.brightness))
    }

    func testTheOfferedListKeepsTheCanonicalOrder() {
        let registry = ControlRegistry(controls: ControlIdentifier.allCases
            .filter { $0 != .none }
            .map { StubControl($0) })

        XCTAssertEqual(registry.assignableControls(), ControlIdentifier.allCases)
    }

    // MARK: - Driving controls

    func testAnUnavailableControlIsNotHandedToTheGestureEngine() {
        let registry = ControlRegistry(controls: [
            StubControl(.volume, isSupported: true, isAvailable: false)
        ])

        XCTAssertNil(registry.control(for: .volume))
        XCTAssertNil(registry.control(for: .none))
        XCTAssertTrue(registry.isAvailable(.none), "An edge assigned to nothing is not a problem")
    }

    func testAnAvailableControlIsHandedOver() {
        let control = StubControl(.volume)
        let registry = ControlRegistry(controls: [control])

        XCTAssertTrue(registry.control(for: .volume) === control)
    }

    // MARK: - The real keyboard backlight

    func testTheKeyboardBacklightAgreesWithItself() {
        let control = KeyboardBacklightControl()

        // Whether this Mac has a backlit keyboard depends on the Mac, so the
        // test asserts what must hold either way: the two answers agree, and
        // reading the level never returns nonsense or touches the hardware.
        XCTAssertEqual(control.isSupported, control.isAvailable)
        XCTAssertEqual(control.identifier, .keyboardBacklight)
        XCTAssertTrue((0...1).contains(control.value))

        if !control.isSupported {
            XCTAssertEqual(control.value, 0, "An absent backlight reads as nothing, not as garbage")
        }
    }

    func testTheKeyboardBacklightMatchesTheKeyboardBrightnessKeys() {
        XCTAssertEqual(KeyboardBacklightControl().quantum, 1.0 / 16.0, accuracy: 0.0001)
    }

    // MARK: - The real Night Shift

    func testNightShiftAgreesWithItself() {
        let control = NightShiftControl()

        // Reads only: a test that tinted the screen of whoever ran it would be
        // a rude test.
        XCTAssertEqual(control.identifier, .nightShift)
        XCTAssertEqual(control.displayName, "Night Shift")
        XCTAssertEqual(control.isSupported, control.isAvailable)
        XCTAssertTrue((0...1).contains(control.value))
    }
}
