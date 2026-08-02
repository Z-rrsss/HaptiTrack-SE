import AppKit
import XCTest
@testable import HaptiTrack

/// Drives the real controller — real overlay window and all — on a timeline
/// compressed to a few hundredths of a second, with the haptics mocked and the
/// sound pointed at a name that does not exist so the test bench stays quiet.
@MainActor
final class LaunchAnimationControllerTests: XCTestCase {

    private final class MockHaptics: HapticEngine {
        var isAvailable = true
        var pulses: [HapticIntensity] = []
        var prepareCount = 0
        var teardownCount = 0

        func prepare() { prepareCount += 1 }
        func perform(_ intensity: HapticIntensity) { pulses.append(intensity) }
        func teardown() { teardownCount += 1 }
    }

    private var haptics: MockHaptics!

    override func setUp() {
        super.setUp()
        haptics = MockHaptics()
    }

    /// Everything an intro does in a moment, done in a fiftieth of one.
    private var fastTimeline: LaunchAnimationTimeline {
        var timeline = LaunchAnimationTimeline()
        timeline.fadeIn = 0.01
        timeline.firstPulse = 0.01
        timeline.pulseInterval = 0.02
        timeline.pulseRise = 0.005
        timeline.pulseFall = 0.005
        timeline.hold = 0
        timeline.fadeOut = 0.01
        return timeline
    }

    private func makeController(
        timeline: LaunchAnimationTimeline? = nil
    ) -> LaunchAnimationController {
        LaunchAnimationController(
            timeline: timeline ?? fastTimeline,
            haptics: haptics,
            // A name no sound set contains, so the test bench stays silent.
            sound: ClickSound(named: "HaptiTrackTestsSilence"),
            intensity: .strong
        )
    }

    private func play(_ controller: LaunchAnimationController) async {
        await withCheckedContinuation { continuation in
            controller.play { continuation.resume() }
        }
    }

    // MARK: - Tests

    func testOnePulsePerBeat() async throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let controller = makeController()

        await play(controller)

        XCTAssertEqual(haptics.pulses.count, fastTimeline.pulseCount)
        XCTAssertEqual(haptics.pulses, [.strong, .strong])
    }

    func testItTakesItselfDownWhenItIsDone() async throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let controller = makeController()

        await play(controller)

        XCTAssertFalse(controller.isPlaying, "The overlay has to close itself; nothing dismisses it")
        XCTAssertEqual(haptics.prepareCount, 1)
        XCTAssertEqual(haptics.teardownCount, 1)
        XCTAssertTrue(
            NSApp.windows.allSatisfy { !$0.isVisible || $0.level != .screenSaver },
            "No overlay window should still be on screen"
        )
    }

    func testPlayingTwiceOverDoesNotStackTwoOverlays() async throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let controller = makeController()

        // The second call is ignored outright rather than queued behind the
        // first, so it is deliberately *not* awaited: nothing will call back.
        await withCheckedContinuation { continuation in
            controller.play { continuation.resume() }
            controller.play()
        }

        XCTAssertEqual(haptics.pulses.count, fastTimeline.pulseCount)
        XCTAssertEqual(haptics.prepareCount, 1, "The refused call must not have set anything up")
    }

    func testCancellingStopsItEarly() async throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        var timeline = fastTimeline
        timeline.firstPulse = 5   // Long enough that nothing can fire in time.
        let controller = makeController(timeline: timeline)

        controller.play()
        controller.cancel()

        XCTAssertFalse(controller.isPlaying)
        XCTAssertTrue(haptics.pulses.isEmpty)
        XCTAssertEqual(haptics.teardownCount, 1)
    }

    func testTheClickSoundIsOnEveryMac() {
        // The intro plays a system sound rather than a bundled asset. If macOS
        // ever stops shipping it the intro goes silent rather than breaking,
        // but that is worth being told about.
        XCTAssertTrue(ClickSound().isAvailable, "Tink is missing from this system's sound set")
        XCTAssertFalse(ClickSound(named: "HaptiTrackTestsSilence").isAvailable)
    }
}
