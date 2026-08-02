import XCTest
@testable import HaptiTrack

final class ScrollDetentEngineTests: XCTestCase {

    // MARK: - Accumulation

    func testShortScrollDoesNotFireADetent() {
        let engine = TickAccumulator()
        let outcome = engine.consume(delta: 5, timestamp: 0, phase: .active)
        XCTAssertEqual(outcome.count, 0)
    }

    func testCrossingTheStepFiresOneDetent() {
        var configuration = TickConfiguration.default
        configuration.stepSize = 12

        let engine = TickAccumulator(configuration: configuration)
        let outcome = engine.consume(delta: 12, timestamp: 0, phase: .active)

        XCTAssertEqual(outcome.count, 1)
        XCTAssertFalse(outcome.isAttenuated)
    }

    func testDistanceAccumulatesAcrossEvents() {
        let engine = TickAccumulator(configuration: .default)

        XCTAssertEqual(engine.consume(delta: 6, timestamp: 0, phase: .active).count, 0)
        XCTAssertEqual(engine.consume(delta: 6, timestamp: 0.05, phase: .active).count, 1)
    }

    func testDirectionChangeRestartsTheCount() {
        var configuration = TickConfiguration.default
        configuration.stepSize = 12

        let engine = TickAccumulator(configuration: configuration)
        XCTAssertEqual(engine.consume(delta: 11, timestamp: 0, phase: .active).count, 0)

        // A full step in the opposite direction must earn its own detent
        // instead of being cancelled out by the credit built up going the
        // other way.
        XCTAssertEqual(engine.consume(delta: -12, timestamp: 0.05, phase: .active).count, 1)
    }

    func testAPauseDropsAccumulatedDistance() {
        let engine = TickAccumulator(configuration: .default)
        XCTAssertEqual(engine.consume(delta: 11, timestamp: 0, phase: .active).count, 0)

        let afterPause = engine.consume(delta: 11, timestamp: 5, phase: .active)
        XCTAssertEqual(afterPause.count, 0, "Distance from before the pause should not carry over")
    }

    func testEndOfGestureResetsTheEngine() {
        let engine = TickAccumulator(configuration: .default)
        XCTAssertEqual(engine.consume(delta: 11, timestamp: 0, phase: .active).count, 0)
        XCTAssertEqual(engine.consume(delta: 0, timestamp: 0.01, phase: .ended).count, 0)
        XCTAssertEqual(engine.consume(delta: 11, timestamp: 0.02, phase: .active).count, 0)
    }

    func testSingleEventNeverPaysOutMoreThanTheCap() {
        var configuration = TickConfiguration.default
        configuration.stepSize = 10
        configuration.maximumTicksPerSample = 2

        let engine = TickAccumulator(configuration: configuration)
        let outcome = engine.consume(delta: 500, timestamp: 0, phase: .active)

        XCTAssertEqual(outcome.count, 2)
    }

    // MARK: - Sensitivity

    func testSmallerStepProducesMoreDetentsOverTheSameDistance() {
        func detentCount(stepSize: Double) -> Int {
            var configuration = TickConfiguration.default
            configuration.stepSize = stepSize
            let engine = TickAccumulator(configuration: configuration)

            var total = 0
            // 2 points every 40 ms: slow enough that the rate limiters never
            // come into play, so only the step size matters.
            for index in 0..<100 {
                total += engine.consume(
                    delta: 2,
                    timestamp: Double(index) * 0.04,
                    phase: .active
                ).count
            }
            return total
        }

        XCTAssertGreaterThan(detentCount(stepSize: 6), detentCount(stepSize: 24))
    }

    // MARK: - Speed adaptation

    func testFastScrollingFiresFewerDetentsPerPointThanSlowScrolling() {
        func detentsPerPoint(deltaPerEvent: Double) -> Double {
            let engine = TickAccumulator(configuration: .default)
            var total = 0
            for index in 0..<200 {
                total += engine.consume(
                    delta: deltaPerEvent,
                    timestamp: Double(index) * 0.016,
                    phase: .active
                ).count
            }
            return Double(total) / (deltaPerEvent * 200)
        }

        let slow = detentsPerPoint(deltaPerEvent: 1.5)   // ~94 pt/s
        let fast = detentsPerPoint(deltaPerEvent: 30)    // ~1875 pt/s

        XCTAssertGreaterThan(slow, 0)
        XCTAssertLessThan(fast, slow / 2, "Notches should spread out as the scroll speeds up")
    }

    func testDetentRateStaysBoundedDuringAFastFlick() {
        let configuration = TickConfiguration.default
        let engine = TickAccumulator(configuration: configuration)

        let eventCount = 200
        let interval = 0.016
        var total = 0
        for index in 0..<eventCount {
            total += engine.consume(
                delta: 40,
                timestamp: Double(index) * interval,
                phase: .active
            ).count
        }

        let duration = Double(eventCount) * interval
        let rate = Double(total) / duration

        // The smoothed velocity lags the start of the flick by a few events, so
        // allow modest headroom over the configured ceiling.
        XCTAssertLessThan(rate, configuration.maximumTickRate * 1.5)
    }

    func testFastScrollingUsesTheAttenuatedIntensity() {
        let engine = TickAccumulator(configuration: .default)
        var lastFiring: TickOutcome?

        for index in 0..<20 {
            let outcome = engine.consume(
                delta: 30,
                timestamp: Double(index) * 0.01,   // 3000 pt/s
                phase: .active
            )
            if outcome.count > 0 { lastFiring = outcome }
        }

        XCTAssertEqual(lastFiring?.isAttenuated, true)
    }

    func testSlowScrollingUsesTheFullIntensity() {
        let engine = TickAccumulator(configuration: .default)
        var lastFiring: TickOutcome?

        for index in 0..<40 {
            let outcome = engine.consume(
                delta: 3,
                timestamp: Double(index) * 0.05,   // 60 pt/s
                phase: .active
            )
            if outcome.count > 0 { lastFiring = outcome }
        }

        XCTAssertEqual(lastFiring?.isAttenuated, false)
    }

    // MARK: - Momentum

    func testMomentumWidensTheStepAndSoftensThePulse() {
        var configuration = TickConfiguration.default
        configuration.stepSize = 12
        configuration.coastingStepMultiplier = 2
        configuration.maximumTicksPerSample = 4

        let active = TickAccumulator(configuration: configuration)
        let coasting = TickAccumulator(configuration: configuration)

        let activeOutcome = active.consume(delta: 24, timestamp: 0, phase: .active)
        let coastingOutcome = coasting.consume(delta: 24, timestamp: 0, phase: .coasting)

        XCTAssertEqual(activeOutcome.count, 2)
        XCTAssertEqual(coastingOutcome.count, 1)
        XCTAssertTrue(coastingOutcome.isAttenuated)
    }

    // MARK: - Rate limiting

    func testPulsesAreNeverCloserThanTheMinimumInterval() {
        var configuration = TickConfiguration.default
        configuration.stepSize = 12
        // Freezing the velocity estimate isolates the interval limiter from the
        // step widening, which would otherwise absorb the second event.
        configuration.velocitySmoothing = 0

        let engine = TickAccumulator(configuration: configuration)
        XCTAssertEqual(engine.consume(delta: 12, timestamp: 0, phase: .active).count, 1)

        let tooSoon = configuration.minimumTickInterval / 2
        XCTAssertEqual(engine.consume(delta: 12, timestamp: tooSoon, phase: .active).count, 0)

        let lateEnough = configuration.minimumTickInterval * 1.5
        XCTAssertEqual(engine.consume(delta: 1, timestamp: lateEnough, phase: .active).count, 1)
    }

    func testHeldBackDistanceDoesNotBecomeABacklog() {
        var configuration = TickConfiguration.default
        configuration.stepSize = 12
        configuration.velocitySmoothing = 0

        let engine = TickAccumulator(configuration: configuration)
        _ = engine.consume(delta: 12, timestamp: 0, phase: .active)

        // A burst of distance arriving while the limiter is closed must not be
        // paid out all at once when it opens again.
        for index in 1...5 {
            _ = engine.consume(delta: 60, timestamp: Double(index) * 0.001, phase: .active)
        }

        let afterTheWait = engine.consume(
            delta: 1,
            timestamp: configuration.minimumTickInterval * 2,
            phase: .active
        )
        XCTAssertEqual(afterTheWait.count, 1)
    }
}
