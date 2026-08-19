import CoreGraphics
import XCTest
@testable import HaptiTrack

/// A stand-in for a real control: records everything written to it and touches
/// no hardware, so the gesture logic can be exercised without a trackpad, an
/// audio device or a display.
private final class MockControl: AdjustableControl {
    let identifier: ControlIdentifier
    let displayName = "Mock"
    var isAvailable = true
    var quantum: Double
    var writes: [Double] = []
    var beginAdjustmentCount = 0
    var endAdjustmentCount = 0

    var value: Double {
        get { storedValue }
        set {
            storedValue = newValue
            writes.append(newValue)
        }
    }

    private var storedValue: Double

    init(identifier: ControlIdentifier = .volume, value: Double = 0.5, quantum: Double = 1.0 / 16.0) {
        self.identifier = identifier
        self.storedValue = value
        self.quantum = quantum
    }

    func beginAdjustment() {
        beginAdjustmentCount += 1
    }

    func endAdjustment() {
        endAdjustmentCount += 1
    }
}

final class EdgeGestureEngineTests: XCTestCase {

    /// A trackpad 100 mm × 100 mm, which makes normalised coordinates and
    /// millimetres line up one to one and keeps the arithmetic in the tests
    /// readable.
    private let surface = TrackpadSurfaceSize(width: 100, height: 100)

    private var control: MockControl!
    private var tickCount = 0
    private var tickIntensities: [HapticIntensity] = []
    private var adjustments: [ControlAdjustment] = []

    override func setUp() {
        super.setUp()
        control = MockControl()
        tickCount = 0
        tickIntensities = []
        adjustments = []
    }

    // MARK: - Helpers

    private func makeEngine(
        zones: [EdgeZoneConfiguration] = [
            EdgeZoneConfiguration(edge: .right, control: .volume, margin: 10, travelForFullRange: 50)
        ],
        requiresTwoFingers: Bool = false
    ) -> EdgeGestureEngine {
        EdgeGestureEngine(
            zones: zones,
            requiresTwoFingers: requiresTwoFingers,
            controlProvider: { [control] identifier in
                identifier == control?.identifier ? control : nil
            },
            onTick: { [weak self] intensity in
                self?.tickCount += 1
                self?.tickIntensities.append(intensity)
            },
            onAdjust: { [weak self] adjustment in
                self?.adjustments.append(adjustment)
            }
        )
    }

    private func twoTouches(
        _ x: Double,
        _ y: Double,
        identifiers: (Int32, Int32) = (1, 2)
    ) -> [TrackpadTouch] {
        [
            touch(x, y, identifier: identifiers.0),
            touch(x - 0.01, y + 0.02, identifier: identifiers.1),
        ]
    }

    private func slideTwoFingers(
        _ engine: EdgeGestureEngine,
        from start: CGPoint,
        to end: CGPoint,
        steps: Int = 20,
        interval: TimeInterval = 0.02
    ) {
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let x = Double(start.x) + (Double(end.x) - Double(start.x)) * progress
            let y = Double(start.y) + (Double(end.y) - Double(start.y)) * progress
            engine.consume(frame(twoTouches(x, y), at: Double(step) * interval))
        }
    }

    private func frame(
        _ touches: [TrackpadTouch],
        at timestamp: TimeInterval
    ) -> TrackpadTouchFrame {
        TrackpadTouchFrame(touches: touches, timestamp: timestamp, surface: surface)
    }

    private func touch(
        _ x: Double,
        _ y: Double,
        identifier: Int32 = 1,
        inContact: Bool = true
    ) -> TrackpadTouch {
        TrackpadTouch(
            identifier: identifier,
            position: CGPoint(x: x, y: y),
            isInContact: inContact
        )
    }

    /// Slides one finger from `start` to `end` in `steps` frames.
    private func slide(
        _ engine: EdgeGestureEngine,
        from start: CGPoint,
        to end: CGPoint,
        steps: Int = 20,
        interval: TimeInterval = 0.02,
        startingAt timestamp: TimeInterval = 0
    ) {
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            engine.consume(frame(
                [touch(
                    Double(start.x) + (Double(end.x) - Double(start.x)) * progress,
                    Double(start.y) + (Double(end.y) - Double(start.y)) * progress
                )],
                at: timestamp + Double(step) * interval
            ))
        }
    }

    // MARK: - Starting a gesture

    func testTouchInTheMiddleDoesNothing() {
        let engine = makeEngine()
        slide(engine, from: CGPoint(x: 0.5, y: 0.2), to: CGPoint(x: 0.5, y: 0.8))

        XCTAssertFalse(engine.isTracking)
        XCTAssertTrue(control.writes.isEmpty)
        XCTAssertEqual(tickCount, 0)
    }

    func testTouchOnTheRightEdgeStartsTracking() {
        let engine = makeEngine()
        engine.consume(frame([touch(0.95, 0.5)], at: 0))

        XCTAssertTrue(engine.isTracking)
        XCTAssertEqual(engine.trackedEdge, .right)
        XCTAssertEqual(control.beginAdjustmentCount, 1)
    }

    func testPreventionRejectsOneFinger() {
        let engine = makeEngine(requiresTwoFingers: true)

        engine.consume(frame([touch(0.95, 0.5)], at: 0))

        XCTAssertFalse(engine.isTracking)
        XCTAssertEqual(control.beginAdjustmentCount, 0)
    }

    func testPreventionRequiresBothFingersInTheSameEdgeStrip() {
        let engine = makeEngine(requiresTwoFingers: true)

        engine.consume(frame([
            touch(0.95, 0.5, identifier: 1),
            touch(0.50, 0.5, identifier: 2),
        ], at: 0))

        XCTAssertFalse(engine.isTracking)
    }

    func testPreventionStartsWithTwoFingersOnTheEdge() {
        let engine = makeEngine(requiresTwoFingers: true)

        engine.consume(frame(twoTouches(0.95, 0.5), at: 0))

        XCTAssertTrue(engine.isTracking)
        XCTAssertEqual(engine.trackedEdge, .right)
        XCTAssertEqual(control.beginAdjustmentCount, 1)
    }

    func testPreventionUsesTwoFingerCentroidToAdjust() {
        let engine = makeEngine(requiresTwoFingers: true)
        control.value = 0.5
        control.writes = []

        slideTwoFingers(
            engine,
            from: CGPoint(x: 0.95, y: 0.3),
            to: CGPoint(x: 0.95, y: 0.7)
        )

        XCTAssertGreaterThan(control.value, 0.5)
        XCTAssertFalse(control.writes.isEmpty)
    }

    func testChangingPreventionModeCancelsTheCurrentGesture() {
        let engine = makeEngine()
        engine.consume(frame([touch(0.95, 0.5)], at: 0))
        XCTAssertTrue(engine.isTracking)

        engine.requiresTwoFingers = true

        XCTAssertFalse(engine.isTracking)
        XCTAssertEqual(control.endAdjustmentCount, 1)
    }

    func testUnassignedEdgeIsIgnored() {
        let engine = makeEngine(zones: [
            EdgeZoneConfiguration(edge: .right, control: .none, margin: 10)
        ])
        slide(engine, from: CGPoint(x: 0.95, y: 0.2), to: CGPoint(x: 0.95, y: 0.8))

        XCTAssertFalse(engine.isTracking)
        XCTAssertTrue(control.writes.isEmpty)
    }

    func testUnavailableControlIsIgnored() {
        let engine = makeEngine(zones: [
            EdgeZoneConfiguration(edge: .right, control: .brightness, margin: 10)
        ])
        slide(engine, from: CGPoint(x: 0.95, y: 0.2), to: CGPoint(x: 0.95, y: 0.8))

        XCTAssertFalse(engine.isTracking)
        XCTAssertTrue(control.writes.isEmpty)
    }

    func testDisabledEngineIgnoresEverything() {
        let engine = makeEngine()
        engine.isEnabled = false
        slide(engine, from: CGPoint(x: 0.95, y: 0.2), to: CGPoint(x: 0.95, y: 0.8))

        XCTAssertFalse(engine.isTracking)
        XCTAssertTrue(control.writes.isEmpty)
    }

    // MARK: - Driving the control

    func testSlidingUpTheRightEdgeRaisesTheValue() {
        let engine = makeEngine()
        control.value = 0.5
        control.writes = []

        slide(engine, from: CGPoint(x: 0.95, y: 0.3), to: CGPoint(x: 0.95, y: 0.7))

        XCTAssertGreaterThan(control.value, 0.5)
        XCTAssertGreaterThan(tickCount, 0)
    }

    func testSlidingDownLowersTheValue() {
        let engine = makeEngine()
        control.value = 0.5
        control.writes = []

        slide(engine, from: CGPoint(x: 0.95, y: 0.7), to: CGPoint(x: 0.95, y: 0.3))

        XCTAssertLessThan(control.value, 0.5)
    }

    func testInvertedEdgeReversesTheDirection() {
        let engine = makeEngine(zones: [
            EdgeZoneConfiguration(
                edge: .right,
                control: .volume,
                margin: 10,
                travelForFullRange: 50,
                isInverted: true
            )
        ])
        control.value = 0.5
        control.writes = []

        slide(engine, from: CGPoint(x: 0.95, y: 0.3), to: CGPoint(x: 0.95, y: 0.7))

        XCTAssertLessThan(control.value, 0.5)
    }

    func testFullSweepTravelCoversTheWholeRange() {
        // 50 mm of travel is configured as the full range, and the surface is
        // 100 mm tall, so half its height should go from silent to maximum.
        let engine = makeEngine()
        control.value = 0
        control.writes = []

        slide(engine, from: CGPoint(x: 0.95, y: 0.25), to: CGPoint(x: 0.95, y: 0.75), steps: 50)

        XCTAssertEqual(control.value, 1, accuracy: 0.001)
    }

    func testValueIsQuantisedToTheControlSteps() {
        let engine = makeEngine()
        control.value = 0
        control.writes = []

        slide(engine, from: CGPoint(x: 0.95, y: 0.3), to: CGPoint(x: 0.95, y: 0.6), steps: 40)

        XCTAssertFalse(control.writes.isEmpty)
        for write in control.writes {
            let steps = write / control.quantum
            XCTAssertEqual(steps, steps.rounded(), accuracy: 0.0001,
                           "\(write) is not a multiple of \(control.quantum)")
        }
    }

    func testValueNeverLeavesTheUnitRange() {
        let engine = makeEngine()
        control.value = 0.9
        control.writes = []

        slide(engine, from: CGPoint(x: 0.95, y: 0.1), to: CGPoint(x: 0.95, y: 0.95), steps: 60)

        XCTAssertTrue(control.writes.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertEqual(control.value, 1, accuracy: 0.001)
    }

    func testHorizontalEdgeTracksTheHorizontalAxis() {
        let engine = makeEngine(zones: [
            EdgeZoneConfiguration(edge: .bottom, control: .volume, margin: 10, travelForFullRange: 50)
        ])
        control.value = 0.5
        control.writes = []

        slide(engine, from: CGPoint(x: 0.3, y: 0.05), to: CGPoint(x: 0.7, y: 0.05))

        XCTAssertEqual(engine.trackedEdge, .bottom)
        XCTAssertGreaterThan(control.value, 0.5)
    }

    // MARK: - Giving the gesture up

    func testTwoFingersCancelTheGesture() {
        let engine = makeEngine()
        engine.consume(frame([touch(0.95, 0.3)], at: 0))
        XCTAssertTrue(engine.isTracking)

        engine.consume(frame([touch(0.95, 0.35), touch(0.80, 0.35, identifier: 2)], at: 0.02))

        XCTAssertFalse(engine.isTracking, "Two fingers is a scroll, not an edge gesture")
    }

    func testPreventionCancelsWhenAThirdFingerTouches() {
        let engine = makeEngine(requiresTwoFingers: true)
        engine.consume(frame(twoTouches(0.95, 0.3), at: 0))
        XCTAssertTrue(engine.isTracking)

        engine.consume(frame(twoTouches(0.95, 0.35) + [
            touch(0.75, 0.35, identifier: 3),
        ], at: 0.02))

        XCTAssertFalse(engine.isTracking)
    }

    func testPreventionKeepsTrackingIfContactOrderChanges() {
        let engine = makeEngine(requiresTwoFingers: true)
        engine.consume(frame(twoTouches(0.95, 0.3), at: 0))

        let reordered = twoTouches(0.95, 0.35).reversed()
        engine.consume(frame(Array(reordered), at: 0.02))

        XCTAssertTrue(engine.isTracking)
        XCTAssertEqual(control.beginAdjustmentCount, 1)
    }

    func testLiftingTheFingerEndsTheGesture() {
        let engine = makeEngine()
        engine.consume(frame([touch(0.95, 0.3)], at: 0))
        engine.consume(frame([touch(0.95, 0.32, inContact: false)], at: 0.02))

        XCTAssertFalse(engine.isTracking)
    }

    func testMovingTowardsTheCentreEndsTheGesture() {
        let engine = makeEngine()
        engine.consume(frame([touch(0.95, 0.3)], at: 0))
        XCTAssertTrue(engine.isTracking)

        // Well past the 10 mm strip plus the 6 mm of hold slack.
        engine.consume(frame([touch(0.5, 0.4)], at: 0.02))

        XCTAssertFalse(engine.isTracking)
    }

    func testSmallInwardDriftKeepsTheGesture() {
        let engine = makeEngine()
        engine.consume(frame([touch(0.95, 0.3)], at: 0))

        // 12 mm in from the edge: outside the strip, inside the slack.
        engine.consume(frame([touch(0.88, 0.35)], at: 0.02))

        XCTAssertTrue(engine.isTracking, "A slight wander should not drop the gesture")
    }

    func testANewFingerStartsANewGesture() {
        let engine = makeEngine()
        engine.consume(frame([touch(0.95, 0.3, identifier: 1)], at: 0))
        engine.consume(frame([touch(0.02, 0.3, identifier: 7)], at: 0.02))

        XCTAssertFalse(engine.isTracking, "The left edge is unassigned in this fixture")
    }

    func testResetStopsTracking() {
        let engine = makeEngine()
        engine.consume(frame([touch(0.95, 0.3)], at: 0))
        engine.reset()

        XCTAssertFalse(engine.isTracking)
        XCTAssertEqual(control.endAdjustmentCount, 1)
    }

    // MARK: - Reporting what moved

    func testEveryMoveIsReported() {
        let engine = makeEngine()
        control.value = 0.5
        control.writes = []

        slide(engine, from: CGPoint(x: 0.95, y: 0.3), to: CGPoint(x: 0.95, y: 0.7))

        XCTAssertEqual(adjustments.map(\.value), control.writes,
                       "One report per change, carrying the value that was written")
        XCTAssertTrue(adjustments.allSatisfy { $0.identifier == .volume })
        XCTAssertTrue(adjustments.allSatisfy { $0.displayName == "Mock" })
    }

    func testAFingerRestingOnAnEdgeReportsNothing() {
        let engine = makeEngine()

        // Down, and then held still for a while.
        for step in 0...10 {
            engine.consume(frame([touch(0.95, 0.5)], at: Double(step) * 0.02))
        }

        XCTAssertTrue(engine.isTracking)
        XCTAssertTrue(adjustments.isEmpty, "Nothing moved, so there is nothing to show")
    }

    func testMovementTooSmallToChangeTheValueReportsNothing() {
        let engine = makeEngine()

        // A fraction of a millimetre: not enough to cross a notch.
        engine.consume(frame([touch(0.95, 0.500)], at: 0))
        engine.consume(frame([touch(0.95, 0.501)], at: 0.02))

        XCTAssertTrue(adjustments.isEmpty)
    }

    // MARK: - Haptics

    func testTicksAreRateLimitedDuringAFastSweep() {
        let engine = makeEngine()
        control.value = 0
        control.writes = []

        let duration: TimeInterval = 0.4
        slide(
            engine,
            from: CGPoint(x: 0.95, y: 0.05),
            to: CGPoint(x: 0.95, y: 0.95),
            steps: 40,
            interval: duration / 40
        )

        let rate = Double(tickCount) / duration
        XCTAssertGreaterThan(tickCount, 0)
        XCTAssertLessThan(rate, TickConfiguration.default.maximumTickRate * 1.5)
    }

    func testFastSweepSoftensTheTicks() {
        let engine = makeEngine()
        slide(
            engine,
            from: CGPoint(x: 0.95, y: 0.05),
            to: CGPoint(x: 0.95, y: 0.95),
            steps: 30,
            interval: 0.004   // ~7500 mm/s, far past the attenuation threshold
        )

        XCTAssertTrue(tickIntensities.contains(.light))
    }

    func testHalfStepDensityTicksMoreOften() {
        func ticks(for density: TickDensity) -> Int {
            control = MockControl()
            tickCount = 0
            let engine = makeEngine(zones: [
                EdgeZoneConfiguration(
                    edge: .right,
                    control: .volume,
                    margin: 10,
                    travelForFullRange: 50,
                    tickDensity: density
                )
            ])
            // Slowly, so the rate limiter never trims the count.
            slide(
                engine,
                from: CGPoint(x: 0.95, y: 0.3),
                to: CGPoint(x: 0.95, y: 0.7),
                steps: 40,
                interval: 0.06
            )
            return tickCount
        }

        XCTAssertGreaterThan(ticks(for: .halfStep), ticks(for: .fullStep))
    }
}
