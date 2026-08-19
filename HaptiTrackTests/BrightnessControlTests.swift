import CoreGraphics
import XCTest
@testable import HaptiTrack

private final class StubHardwareBrightness: HardwareBrightnessServicing {
    var readings: [CGDirectDisplayID: Double] = [:]
    var writeSucceeds = true
    var reads: [CGDirectDisplayID] = []
    var writes: [(CGDirectDisplayID, Double)] = []

    func readBrightness(for displayID: CGDirectDisplayID) -> Double? {
        reads.append(displayID)
        return readings[displayID]
    }

    func writeBrightness(_ value: Double, for displayID: CGDirectDisplayID) -> Bool {
        writes.append((displayID, value))
        return writeSucceeds
    }
}

private final class StubSoftwareDimming: SoftwareDimmingServicing {
    var availableDisplays: Set<CGDirectDisplayID> = []
    var values: [CGDirectDisplayID: Double] = [:]
    var writes: [(CGDirectDisplayID, Double)] = []
    var clears: [CGDirectDisplayID] = []

    func isAvailable(for displayID: CGDirectDisplayID) -> Bool {
        availableDisplays.contains(displayID)
    }

    func readBrightness(for displayID: CGDirectDisplayID) -> Double {
        values[displayID] ?? 1
    }

    func writeBrightness(_ value: Double, for displayID: CGDirectDisplayID) -> Bool {
        guard isAvailable(for: displayID) else { return false }
        values[displayID] = value
        writes.append((displayID, value))
        return true
    }

    func clearDimming(for displayID: CGDirectDisplayID) {
        values[displayID] = nil
        clears.append(displayID)
    }
}

final class BrightnessControlTests: XCTestCase {

    private let firstDisplay: CGDirectDisplayID = 101
    private let secondDisplay: CGDirectDisplayID = 202

    func testNativeBrightnessHasFirstChoiceAndLocksTheDisplayForTheGesture() {
        let native = StubHardwareBrightness()
        native.readings[firstDisplay] = 0.4
        let ddc = StubHardwareBrightness()
        let software = StubSoftwareDimming()
        software.availableDisplays = [firstDisplay, secondDisplay]
        var pointerDisplay = firstDisplay
        let control = BrightnessControl(
            native: native,
            ddc: ddc,
            software: software,
            displayResolver: { pointerDisplay }
        )

        control.beginAdjustment()
        pointerDisplay = secondDisplay
        control.value = 0.75

        XCTAssertEqual(control.activeMethod, .native)
        XCTAssertEqual(control.adjustmentDisplayID, firstDisplay)
        XCTAssertEqual(native.writes.count, 1)
        XCTAssertEqual(native.writes.first?.0, firstDisplay)
        XCTAssertEqual(native.writes.first?.1 ?? 0, 0.75, accuracy: 0.0001)
        XCTAssertTrue(ddc.reads.isEmpty, "DDC is a fallback, not a second write")
        XCTAssertEqual(software.clears, [firstDisplay])
    }

    func testDDCIsUsedWhenNativeBrightnessIsUnavailable() {
        let native = StubHardwareBrightness()
        let ddc = StubHardwareBrightness()
        ddc.readings[firstDisplay] = 0.5
        let software = StubSoftwareDimming()
        software.availableDisplays = [firstDisplay]
        let control = BrightnessControl(
            native: native,
            ddc: ddc,
            software: software,
            displayResolver: { self.firstDisplay }
        )

        control.beginAdjustment()
        control.value = 0.625

        XCTAssertEqual(control.activeMethod, .ddc)
        XCTAssertEqual(ddc.writes.count, 1)
        XCTAssertEqual(ddc.writes.first?.0, firstDisplay)
        XCTAssertEqual(ddc.writes.first?.1 ?? 0, 0.625, accuracy: 0.0001)
        XCTAssertTrue(native.writes.isEmpty)
        XCTAssertEqual(software.clears, [firstDisplay])
    }

    func testSoftwareDimmingIsUsedWhenBothHardwarePathsAreUnavailable() {
        let native = StubHardwareBrightness()
        let ddc = StubHardwareBrightness()
        let software = StubSoftwareDimming()
        software.availableDisplays = [firstDisplay]
        software.values[firstDisplay] = 0.8
        let control = BrightnessControl(
            native: native,
            ddc: ddc,
            software: software,
            displayResolver: { self.firstDisplay }
        )

        control.beginAdjustment()
        XCTAssertEqual(control.activeMethod, .software)
        XCTAssertEqual(control.value, 0.8, accuracy: 0.0001)

        control.value = 0.25

        XCTAssertEqual(software.writes.count, 1)
        XCTAssertEqual(software.writes.first?.0, firstDisplay)
        XCTAssertEqual(software.writes.first?.1 ?? 0, 0.25, accuracy: 0.0001)
    }

    func testFailedDDCWriteFallsBackToSoftwareWithoutEndingTheGesture() {
        let native = StubHardwareBrightness()
        let ddc = StubHardwareBrightness()
        ddc.readings[firstDisplay] = 0.5
        ddc.writeSucceeds = false
        let software = StubSoftwareDimming()
        software.availableDisplays = [firstDisplay]
        let control = BrightnessControl(
            native: native,
            ddc: ddc,
            software: software,
            displayResolver: { self.firstDisplay }
        )

        control.beginAdjustment()
        control.value = 0.375

        XCTAssertEqual(control.activeMethod, .software)
        XCTAssertEqual(control.value, 0.375, accuracy: 0.0001)
        XCTAssertEqual(software.writes.count, 1)
    }

    func testFailedNativeWriteTriesDDCBeforeSoftware() {
        let native = StubHardwareBrightness()
        native.readings[firstDisplay] = 0.5
        native.writeSucceeds = false
        let ddc = StubHardwareBrightness()
        ddc.readings[firstDisplay] = 0.5
        let software = StubSoftwareDimming()
        software.availableDisplays = [firstDisplay]
        let control = BrightnessControl(
            native: native,
            ddc: ddc,
            software: software,
            displayResolver: { self.firstDisplay }
        )

        control.beginAdjustment()
        control.value = 0.625

        XCTAssertEqual(control.activeMethod, .ddc)
        XCTAssertEqual(ddc.writes.count, 1)
        XCTAssertTrue(software.writes.isEmpty)
    }

    func testLiftingTheFingersLetsTheNextGestureChooseAnotherDisplayAndMethod() {
        let native = StubHardwareBrightness()
        native.readings[firstDisplay] = 0.5
        let ddc = StubHardwareBrightness()
        ddc.readings[secondDisplay] = 0.6
        let software = StubSoftwareDimming()
        software.availableDisplays = [firstDisplay, secondDisplay]
        var pointerDisplay = firstDisplay
        let control = BrightnessControl(
            native: native,
            ddc: ddc,
            software: software,
            displayResolver: { pointerDisplay }
        )

        control.beginAdjustment()
        XCTAssertEqual(control.activeMethod, .native)
        control.endAdjustment()

        pointerDisplay = secondDisplay
        control.beginAdjustment()

        XCTAssertEqual(control.activeMethod, .ddc)
        XCTAssertEqual(control.adjustmentDisplayID, secondDisplay)
    }

    func testBrightnessRemainsAvailableWhenOnlySoftwareDimmingCanWork() {
        let software = StubSoftwareDimming()
        software.availableDisplays = [firstDisplay]
        let control = BrightnessControl(
            native: StubHardwareBrightness(),
            ddc: StubHardwareBrightness(),
            software: software,
            displayResolver: { self.firstDisplay }
        )

        XCTAssertTrue(control.isAvailable)
    }
}
