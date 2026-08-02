import XCTest
@testable import HaptiTrack

/// The intro's schedule. It is a flourish, and the tests are here to keep it
/// one: two beats, both while the overlay is up, all over in a moment.
final class LaunchAnimationTimelineTests: XCTestCase {

    private let timeline = LaunchAnimationTimeline()

    func testItPulsesTwice() {
        XCTAssertEqual(timeline.pulseCount, 2)
        XCTAssertEqual(timeline.pulseTimes.count, 2)
    }

    func testTheWholeThingIsOverInUnderTwoSeconds() {
        XCTAssertLessThanOrEqual(timeline.total, 2)
    }

    func testPulsesAreOrderedAndSpacedApart() {
        let times = timeline.pulseTimes

        XCTAssertEqual(times, times.sorted())
        for (first, second) in zip(times, times.dropFirst()) {
            // Two pulses closer together than the swell and the settle would
            // read as one long buzz rather than as two beats.
            XCTAssertGreaterThan(second - first, timeline.pulseRise)
        }
    }

    func testEveryPulseLandsWhileTheOverlayIsUp() {
        for (index, time) in timeline.pulseTimes.enumerated() {
            XCTAssertGreaterThanOrEqual(time, timeline.fadeIn, "pulse \(index) fires before the name is legible")
            XCTAssertLessThan(time, timeline.fadeOutStart, "pulse \(index) fires as the overlay is leaving")
        }
    }

    func testTheFadeOutOnlyStartsOnceTheLastPulseHasSettled() {
        let lastPulseEnds = timeline.pulseTime(timeline.pulseCount - 1)
            + timeline.pulseRise
            + timeline.pulseFall

        XCTAssertGreaterThanOrEqual(timeline.fadeOutStart, lastPulseEnds)
        XCTAssertEqual(timeline.total, timeline.fadeOutStart + timeline.fadeOut, accuracy: 0.0001)
    }

    func testPulseTimesFollowTheInterval() {
        var timeline = LaunchAnimationTimeline()
        timeline.firstPulse = 0.5
        timeline.pulseInterval = 0.25
        timeline.pulseCount = 3

        XCTAssertEqual(timeline.pulseTimes, [0.5, 0.75, 1.0])
    }

    func testASilentTimelineStillHasADuration() {
        var timeline = LaunchAnimationTimeline()
        timeline.pulseCount = 0

        XCTAssertTrue(timeline.pulseTimes.isEmpty)
        XCTAssertGreaterThan(timeline.total, 0)
    }
}
