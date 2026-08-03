import XCTest
@testable import HaptiTrack

/// A stand-in for `CBBlueLightClient` that behaves the way the real one was
/// measured to behave on macOS 26.5.
///
/// The important detail is the status struct: **byte 0 is always 1**, in every
/// state, exactly as the real class reports it. Reading that byte instead of
/// byte 1 is the bug these tests exist to keep out, and a fake that reported a
/// helpful byte 0 would let it straight back in.
private final class FakeBlueLightClient: NSObject, NightShiftControl.BlueLightClient {

    private(set) var strength: Float = 0
    private(set) var isEnabled = false

    /// Every call in order, so a test can talk about what happened and when.
    private(set) var calls: [String] = []

    /// Set up the state the machine is in before a sweep starts.
    func park(enabled: Bool, strength: Float) {
        isEnabled = enabled
        self.strength = strength
        calls = []
    }

    var enableCalls: [Bool] {
        calls.compactMap { call in
            switch call {
            case "enable(true)": return true
            case "enable(false)": return false
            default: return nil
            }
        }
    }

    var strengthWrites: [Float] {
        calls.compactMap { call in
            call.hasPrefix("strength(") ? Float(call.dropFirst(9).dropLast()) : nil
        }
    }

    func setStrength(_ strength: Float, commit: Bool) -> Bool {
        self.strength = strength
        calls.append("strength(\(strength))")
        return true
    }

    func getStrength(_ strength: UnsafeMutablePointer<Float>) -> Bool {
        strength.pointee = self.strength
        return true
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        isEnabled = enabled
        calls.append("enable(\(enabled))")
        return true
    }

    func getBlueLightStatus(_ status: UnsafeMutableRawPointer) -> Bool {
        status.storeBytes(of: UInt8(1), toByteOffset: 0, as: UInt8.self)
        status.storeBytes(of: isEnabled ? 1 : 0, toByteOffset: 1, as: UInt8.self)
        status.storeBytes(of: UInt8(1), toByteOffset: 2, as: UInt8.self)
        return true
    }
}

/// Night Shift as an edge control: what a sweep reads when it starts, and what
/// it writes on the way up and on the way down.
final class NightShiftControlTests: XCTestCase {

    private var client: FakeBlueLightClient!
    private var control: NightShiftControl!

    /// The twelve notches of a full sweep, which is this control's quantum.
    private let ticks: [Double] = (1...12).map { Double($0) / 12 }

    override func setUp() {
        super.setUp()
        client = FakeBlueLightClient()
        control = NightShiftControl(client: client)
    }

    /// Drives the control the way the gesture engine does: read once at the
    /// start, then write each notch crossed.
    @discardableResult
    private func sweep(_ values: [Double]) -> Double {
        let start = control.value
        for value in values {
            control.value = value
        }
        return start
    }

    // MARK: - What a sweep starts from

    func testAnUntintedScreenReadsAsZeroHoweverStrongItWasLastTime() {
        client.park(enabled: false, strength: 0.9)

        XCTAssertEqual(control.value, 0, "A screen that is not tinted is not tinted by 90%")
    }

    func testATintedScreenReadsAsItsStrength() {
        client.park(enabled: true, strength: 0.6)

        XCTAssertEqual(control.value, 0.6, accuracy: 0.0001)
    }

    // MARK: - Up from off

    func testSweepingUpFromOffSwitchesNightShiftOnAtTheFirstNotch() {
        client.park(enabled: false, strength: 0.9)

        sweep(ticks)

        XCTAssertEqual(client.enableCalls, [true], "Switched on once, not once per notch")
        XCTAssertTrue(client.isEnabled)
    }

    func testSweepingUpFromOffNeverShowsTheStrengthLeftOverFromLastTime() {
        // The screen was last tinted at 90%. A sweep starting from nothing must
        // not flash through 90% on its way to 8%.
        client.park(enabled: false, strength: 0.9)

        sweep(ticks)

        let writesWhileClimbing = client.strengthWrites.prefix(while: { $0 < 0.9 })
        XCTAssertFalse(writesWhileClimbing.isEmpty)
        for (index, write) in writesWhileClimbing.enumerated() {
            XCTAssertLessThanOrEqual(
                Double(write),
                ticks[min(index, ticks.count - 1)] + 0.0001,
                "Write \(index) jumped past the notch the finger had reached"
            )
        }
    }

    func testTheRampUpIsMonotonicAndReachesTheTop() {
        client.park(enabled: false, strength: 0.9)

        sweep(ticks)

        let writes = client.strengthWrites.map(Double.init)
        XCTAssertEqual(writes, writes.sorted(), "Each notch is warmer than the last")
        XCTAssertEqual(client.strength, 1, accuracy: 0.0001)
        XCTAssertTrue(client.isEnabled)
    }

    func testEveryNotchOnTheWayUpIsWritten() {
        client.park(enabled: false, strength: 0)

        sweep(ticks)

        for tick in ticks {
            XCTAssertTrue(
                client.strengthWrites.contains { abs(Double($0) - tick) < 0.0001 },
                "The screen never passed through \(tick)"
            )
        }
    }

    // MARK: - Down from on

    func testSweepingDownFromOnEndsSwitchedOff() {
        client.park(enabled: true, strength: 1)

        sweep(ticks.reversed() + [0])

        XCTAssertEqual(client.enableCalls, [false], "Switched off once, at the bottom")
        XCTAssertFalse(client.isEnabled)
        XCTAssertEqual(client.strength, 0, accuracy: 0.0001)
    }

    func testTheRampDownIsMonotonic() {
        client.park(enabled: true, strength: 1)

        sweep(ticks.reversed() + [0])

        let writes = client.strengthWrites.map(Double.init)
        XCTAssertEqual(writes, writes.sorted(by: >), "Each notch is cooler than the last")
    }

    func testSweepingDownFromOnNeverSwitchesNightShiftOnAgain() {
        client.park(enabled: true, strength: 1)

        sweep(ticks.reversed())

        XCTAssertFalse(client.enableCalls.contains(true))
    }

    // MARK: - Symmetry

    func testTheTwoDirectionsPassThroughTheSameLevelsInOppositeOrder() {
        client.park(enabled: false, strength: 0)
        sweep(ticks)
        let up = levelsReached(client.strengthWrites)

        client.park(enabled: true, strength: 1)
        sweep(ticks.reversed())
        let down = levelsReached(client.strengthWrites)

        XCTAssertEqual(up, down.reversed(), "One direction fades and the other jumps")
    }

    func testSwitchingOnWritesTheFirstNotchTwiceOnPurpose() {
        // Deliberate: the strength is written before Night Shift is switched
        // on, so switching on cannot tint the screen at the level left over
        // from last time, and again afterwards for a machine where a write
        // made while switched off does not land. Both write the value the
        // finger asked for, so the screen never shows anything else.
        client.park(enabled: false, strength: 0.9)

        control.value = 1.0 / 12

        XCTAssertEqual(client.calls, ["strength(0.083333336)", "enable(true)", "strength(0.083333336)"])
    }

    /// The distinct levels a sweep passed through, with a repeat of the level
    /// already showing collapsed away.
    private func levelsReached(_ writes: [Float]) -> [Float] {
        writes.reduce(into: [Float]()) { levels, write in
            if levels.last != write { levels.append(write) }
        }
    }

    func testGoingUpAndStraightBackDownLeavesTheScreenAsItWasFound() {
        client.park(enabled: false, strength: 0)

        sweep(ticks)
        sweep(ticks.reversed() + [0])

        XCTAssertFalse(client.isEnabled)
        XCTAssertEqual(client.strength, 0, accuracy: 0.0001)
    }

    // MARK: - Degrading

    func testWithoutTheClientNothingHappensAndNothingCrashes() {
        let control = NightShiftControl(client: nil)

        control.value = 0.5

        XCTAssertEqual(control.value, 0)
        XCTAssertFalse(control.isSupported)
    }

    func testAMacThatCannotReduceBlueLightDoesNotOfferTheControl() {
        let control = NightShiftControl(client: client, isReductionSupported: false)

        XCTAssertFalse(control.isSupported)
        XCTAssertFalse(control.isAvailable)
    }

    func testWithoutAReadableStatusASweepStillSwitchesNightShiftOn() {
        // If the status cannot be read the control assumes the screen is not
        // tinted: switching on something already on is harmless, where
        // assuming it is on means a sweep that does nothing at all.
        let control = NightShiftControl(client: client, canReadStatus: false)
        client.park(enabled: false, strength: 0)

        control.value = 0.25

        XCTAssertTrue(client.isEnabled)
        XCTAssertEqual(client.strength, 0.25, accuracy: 0.0001)
    }
}
