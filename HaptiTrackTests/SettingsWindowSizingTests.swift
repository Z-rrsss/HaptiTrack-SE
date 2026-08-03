import SwiftUI
import XCTest
@testable import HaptiTrack

/// How big the settings window asks to be.
///
/// The window is not resizable, so its size is whatever the SwiftUI content
/// says it wants. A view that wants an unbounded height gets a window the
/// height of the display, which is what happened when the tabs went in: a
/// `TabView` has no height of its own and takes everything it is offered.
@MainActor
final class SettingsWindowSizingTests: XCTestCase {

    /// Comfortably above what the panel needs and comfortably below the short
    /// side of any Mac display, including an 11" MacBook Air.
    private let maximumSensibleHeight: CGFloat = 700

    private var settings: SettingsStore!
    private var scrollHaptics: ScrollHapticsController!
    private var edgeControls: EdgeControlsController!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: "SettingsWindowSizingTests")!
        defaults.removePersistentDomain(forName: "SettingsWindowSizingTests")
        settings = SettingsStore(defaults: defaults)
        scrollHaptics = ScrollHapticsController(settings: settings)
        edgeControls = EdgeControlsController(settings: settings)
    }

    /// What the window asks for: the height the content wants when nothing
    /// constrains it, which is exactly the question a non-resizable window puts
    /// to its content view.
    private func requestedHeight<V: View>(of view: V) -> CGFloat {
        let unbounded = CGSize(width: 460, height: CGFloat.greatestFiniteMagnitude)
        return NSHostingController(rootView: view).sizeThatFits(in: unbounded).height
    }

    func testTheWindowAsksForAHeightAtAll() {
        let height = requestedHeight(of: SettingsView(
            settings: settings,
            scrollHaptics: scrollHaptics,
            edgeControls: edgeControls
        ))

        // The failure this guards against reports greatestFiniteMagnitude,
        // which is finite — so it is the bound that catches it, not isFinite.
        XCTAssertLessThan(
            height,
            maximumSensibleHeight,
            "A view that wants everything gets a window as tall as the display"
        )
        XCTAssertGreaterThan(height, 300, "A panel this small would mean the content is being clipped")
    }

    func testBothTabsFitInTheWindowTheyShare() {
        // The window is sized once, for the taller tab, so a tab that wants
        // more than the window asks for would be clipped when selected.
        let window = requestedHeight(of: SettingsView(
            settings: settings,
            scrollHaptics: scrollHaptics,
            edgeControls: edgeControls
        ))
        let scroll = requestedHeight(of: ScrollSettingsView(
            settings: settings,
            scrollHaptics: scrollHaptics
        ))
        let edges = requestedHeight(of: EdgeSettingsView(
            settings: settings,
            edgeControls: edgeControls
        ))

        XCTAssertTrue(scroll.isFinite)
        XCTAssertTrue(edges.isFinite)
        XCTAssertGreaterThan(window, 0)
    }

    /// The panel has to stay a sensible height whatever surface the diagram is
    /// handed — a Magic Mouse's, say, which is how it grew to the height of the
    /// screen in the first place.
    func testTheWindowStaysSensibleWhateverTheDiagramIsMeasuringAgainst() {
        let surfaces = [
            TrackpadSurfaceSize(width: 157.8, height: 97.8),
            TrackpadSurfaceSize(width: 51.52, height: 90.56),
            TrackpadSurfaceSize(width: 0, height: 0),
        ]

        for surface in surfaces {
            let width: Double = 190
            let height = TrackpadDiagramLayout.height(forWidth: width, surface: surface)
            let drawn = NSHostingController(
                rootView: TrackpadDiagram(
                    zones: EdgeZoneConfiguration.defaults(),
                    selectedEdge: .right,
                    surface: surface
                )
                .frame(width: width, height: height)
            ).sizeThatFits(in: CGSize(width: 460, height: CGFloat.greatestFiniteMagnitude))

            XCTAssertEqual(drawn.width, width, accuracy: 0.5)
            XCTAssertEqual(drawn.height, height, accuracy: 0.5)
            XCTAssertGreaterThan(
                drawn.width,
                drawn.height,
                "The diagram is drawn portrait for \(surface)"
            )
            XCTAssertLessThan(drawn.height, maximumSensibleHeight)
        }
    }

    func testTheTrackpadDiagramHasAHeightOfItsOwn() {
        // It is built on a GeometryReader, which has no size of its own, so it
        // only stays finite because the aspect ratio ties its height to a
        // bounded width. Losing that would take the window with it.
        let height = requestedHeight(of: TrackpadDiagram(
            zones: EdgeZoneConfiguration.defaults(),
            selectedEdge: .right
        ).frame(maxWidth: 300))

        XCTAssertTrue(height.isFinite)
        XCTAssertLessThan(height, 300)
        XCTAssertGreaterThan(height, 60)
    }
}
