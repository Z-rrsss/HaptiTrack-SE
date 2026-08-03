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
        isBuiltIn: true
    )
    private let magicMouse = Candidate(
        surface: TrackpadSurfaceSize(width: 51.52, height: 90.56),
        isBuiltIn: false
    )
    private let magicTrackpad = Candidate(
        surface: TrackpadSurfaceSize(width: 160, height: 114.9),
        isBuiltIn: false
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

    func testASingleDeviceIsUsedWhateverItIs() {
        XCTAssertEqual(TrackpadTouchMonitor.primarySurface(among: [magicMouse]), magicMouse.surface)
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

    func testAMouseOnItsOwnIsNotSilentlyReshaped() {
        // The one arrangement that is genuinely portrait is reported as it is
        // rather than massaged: the fix belongs in which device is chosen, not
        // in pretending a mouse is a trackpad.
        let surface = TrackpadTouchMonitor.primarySurface(among: [magicMouse])

        XCTAssertLessThan(surface.width, surface.height)
    }

    func testTheFallbackIsATrackpadShape() {
        XCTAssertGreaterThan(TrackpadSurfaceSize.fallback.width, TrackpadSurfaceSize.fallback.height)
    }
}
