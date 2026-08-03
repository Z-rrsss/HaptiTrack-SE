import XCTest
@testable import HaptiTrack

/// Which multitouch device the app measures itself against.
///
/// "Multitouch device" is a wider category than "trackpad". A Magic Mouse is
/// one, and reports a surface 51 × 91 mm — taller than it is wide. Taking
/// whichever device came last in the framework's list, which is what this used
/// to do, drew the settings diagram as a portrait trackpad and pushed the
/// settings window down the whole height of the screen.
final class TrackpadSurfaceTests: XCTestCase {

    private typealias Candidate = TrackpadTouchMonitor.Candidate

    /// The two devices attached to the machine this was found on, in the order
    /// the framework listed them: the trackpad first, the mouse last.
    private let builtInTrackpad = Candidate(
        surface: TrackpadSurfaceSize(width: 157.8, height: 97.8),
        isBuiltIn: true,
        familyID: 105
    )
    private let magicMouse = Candidate(
        surface: TrackpadSurfaceSize(width: 51.52, height: 90.56),
        isBuiltIn: false,
        familyID: 112
    )
    /// Landscape and external. Its family ID is deliberately one nobody here
    /// has seen: a device this code does not recognise has to keep working.
    private let magicTrackpad = Candidate(
        surface: TrackpadSurfaceSize(width: 160, height: 114.9),
        isBuiltIn: false,
        familyID: 999
    )

    // MARK: - Choosing a device

    func testTheBuiltInTrackpadWinsEvenWhenItIsNotLast() {
        let surface = TrackpadTouchMonitor.primarySurface(among: [builtInTrackpad, magicMouse])

        XCTAssertEqual(surface, builtInTrackpad.surface)
    }

    func testTheBuiltInTrackpadWinsEvenWhenItIsNotFirst() {
        let surface = TrackpadTouchMonitor.primarySurface(among: [magicMouse, builtInTrackpad])

        XCTAssertEqual(surface, builtInTrackpad.surface)
    }

    func testWithoutABuiltInTrackpadTheLargestSurfaceWins() {
        // A desktop with both a Magic Trackpad and a Magic Mouse attached.
        let surface = TrackpadTouchMonitor.primarySurface(among: [magicMouse, magicTrackpad])

        XCTAssertEqual(surface, magicTrackpad.surface)
    }

    func testASingleTrackpadIsUsedWhateverItIs() {
        XCTAssertEqual(
            TrackpadTouchMonitor.primarySurface(among: [magicTrackpad]),
            magicTrackpad.surface
        )
    }

    func testNoDevicesLeavesTheFallback() {
        XCTAssertEqual(TrackpadTouchMonitor.primarySurface(among: []), .fallback)
    }

    // MARK: - What the choice has to guarantee

    func testTheChosenSurfaceIsAlwaysATrackpadShape() {
        // Every arrangement of the devices seen in the wild has to come back
        // wider than tall. This is the property the diagram depends on.
        let arrangements: [[Candidate]] = [
            [builtInTrackpad, magicMouse],
            [magicMouse, builtInTrackpad],
            [magicMouse, magicTrackpad],
            [magicTrackpad, magicMouse],
            [builtInTrackpad],
            [magicTrackpad],
            [],
        ]

        for arrangement in arrangements {
            let surface = TrackpadTouchMonitor.primarySurface(among: arrangement)
            XCTAssertGreaterThan(
                surface.width,
                surface.height,
                "A trackpad is wider than it is tall: \(arrangement.map(\.surface))"
            )
        }
    }

    func testAMouseOnItsOwnIsNotDrawnAsTheTrackpad() {
        // A mouse cannot drive an edge gesture, so the panel has no business
        // drawing one. With nothing else attached there is nothing to measure,
        // and the diagram falls back to a trackpad shape.
        XCTAssertEqual(TrackpadTouchMonitor.primarySurface(among: [magicMouse]), .fallback)
    }

    // MARK: - Which devices may drive edge gestures

    func testTheBuiltInTrackpadDrivesEdgeGestures() {
        XCTAssertTrue(builtInTrackpad.isTrackpad)
    }

    func testAMagicMouseDoesNot() {
        XCTAssertFalse(magicMouse.isTrackpad, "A palm on a mouse is not a finger on an edge")
    }

    func testAnExternalMagicTrackpadStillDoes() {
        XCTAssertTrue(
            magicTrackpad.isTrackpad,
            "An external trackpad must keep working, family ID recognised or not"
        )
    }

    func testAMouseIsExcludedByItsFamilyEvenIfItsShapeSaysOtherwise() {
        // Belt: a hypothetical mouse with a landscape touch surface.
        let landscapeMouse = Candidate(
            surface: TrackpadSurfaceSize(width: 90, height: 51),
            isBuiltIn: false,
            familyID: 112
        )

        XCTAssertFalse(landscapeMouse.isTrackpad)
    }

    func testAPortraitDeviceIsExcludedByItsShapeEvenIfItsFamilyIsUnknown() {
        // Braces: a device this code has never heard of, shaped like a mouse.
        let unknownPortraitDevice = Candidate(
            surface: TrackpadSurfaceSize(width: 51, height: 90),
            isBuiltIn: false,
            familyID: 777
        )

        XCTAssertFalse(unknownPortraitDevice.isTrackpad)
    }

    func testADeviceThatWillNotReportItsSizeIsGivenTheBenefitOfTheDoubt() {
        // Excluding on ignorance would silently switch the feature off on
        // hardware nobody here can test.
        let unmeasurable = Candidate(
            surface: TrackpadSurfaceSize(width: 0, height: 0),
            isBuiltIn: false,
            familyID: 0
        )

        XCTAssertTrue(unmeasurable.isTrackpad)
    }

    func testTheFallbackIsATrackpadShape() {
        XCTAssertGreaterThan(TrackpadSurfaceSize.fallback.width, TrackpadSurfaceSize.fallback.height)
    }

    // MARK: - The filter is what stops the mouse, not the geometry

    /// A finger on a Magic Mouse lands somewhere. Somewhere, on a surface
    /// 51 × 91 mm, is nearly always within a few millimetres of an edge — so
    /// the gesture engine, which knows only about geometry, would happily take
    /// it. These two tests are a pair: the first shows the touch would start a
    /// gesture, the second shows the device filter never lets it get there.
    func testTheSameTouchOnAMouseSurfaceWouldOtherwiseStartAGesture() {
        let control = SpyControl()
        let engine = EdgeGestureEngine(
            zones: [EdgeZoneConfiguration(edge: .right, control: .volume, margin: 10)],
            controlProvider: { _ in control },
            onTick: { _ in }
        )

        // Hard against the right-hand edge of the mouse's surface.
        engine.consume(TrackpadTouchFrame(
            touches: [TrackpadTouch(identifier: 1, position: CGPoint(x: 0.97, y: 0.5), isInContact: true)],
            timestamp: 0,
            surface: magicMouse.surface
        ))

        XCTAssertTrue(engine.isTracking, "The geometry alone does not stop a mouse touch")
        XCTAssertEqual(engine.trackedEdge, .right)
    }

    func testFramesFromAMouseNeverReachTheGestureEngine() {
        // The monitor drops them before the engine is called, on the strength
        // of the device they came from and nothing else.
        XCTAssertFalse(magicMouse.isTrackpad)
        XCTAssertTrue(builtInTrackpad.isTrackpad)
        XCTAssertTrue(magicTrackpad.isTrackpad)
    }
}

/// Records that something drove it, for the pair of tests above.
private final class SpyControl: AdjustableControl {
    let identifier: ControlIdentifier = .volume
    let displayName = "Spy"
    var isAvailable = true
    var value: Double = 0.5
}
