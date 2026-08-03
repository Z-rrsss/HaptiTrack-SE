import XCTest
@testable import HaptiTrack

/// The trackpad diagram's geometry: how deep each strip is drawn, and which
/// edge a click on it selects.
final class TrackpadDiagramTests: XCTestCase {

    /// 200 mm × 100 mm, so the two axes cannot be confused for each other.
    private let surface = TrackpadSurfaceSize(width: 200, height: 100)

    /// Drawn at 400 × 200 points, i.e. two points per millimetre, which keeps
    /// the arithmetic in the tests readable.
    private let size = CGSize(width: 400, height: 200)

    private func layout(
        left: Double = 20,
        right: Double = 20,
        top: Double = 20,
        bottom: Double = 20
    ) -> TrackpadDiagramLayout {
        TrackpadDiagramLayout(
            zones: [
                EdgeZoneConfiguration(edge: .left, control: .brightness, margin: left),
                EdgeZoneConfiguration(edge: .right, control: .volume, margin: right),
                EdgeZoneConfiguration(edge: .top, control: .none, margin: top),
                EdgeZoneConfiguration(edge: .bottom, control: .none, margin: bottom),
            ],
            surface: surface,
            size: size
        )
    }

    // MARK: - Clicking an edge

    func testClickingNearEachBorderSelectsThatEdge() {
        let layout = layout()

        XCTAssertEqual(layout.edge(at: CGPoint(x: 5, y: 100)), .left)
        XCTAssertEqual(layout.edge(at: CGPoint(x: 395, y: 100)), .right)
        XCTAssertEqual(layout.edge(at: CGPoint(x: 200, y: 5)), .top)
        XCTAssertEqual(layout.edge(at: CGPoint(x: 200, y: 195)), .bottom)
    }

    func testClickingTheMiddleSelectsNothing() {
        XCTAssertNil(layout().edge(at: CGPoint(x: 200, y: 100)))
    }

    func testClickingOutsideTheDiagramSelectsNothing() {
        let layout = layout()

        XCTAssertNil(layout.edge(at: CGPoint(x: -1, y: 100)))
        XCTAssertNil(layout.edge(at: CGPoint(x: 401, y: 100)))
        XCTAssertNil(layout.edge(at: CGPoint(x: 200, y: -1)))
        XCTAssertNil(layout.edge(at: CGPoint(x: 200, y: 201)))
    }

    func testAClickLandsOnTheEdgeItLooksLikeItLandedOn() {
        // 20 mm of a 200 mm width is 40 points at this scale, so a click at 39
        // is on the drawn strip and one at 41 is past it.
        let layout = layout(left: 20)

        XCTAssertEqual(layout.stripFrame(for: .left).width, 40, accuracy: 0.0001)
        XCTAssertEqual(layout.edge(at: CGPoint(x: 39, y: 100)), .left)
        XCTAssertNil(layout.edge(at: CGPoint(x: 41, y: 100)))
    }

    func testCornersBelongToTheVerticalEdges() {
        let layout = layout()

        // The left and right strips run the full height, so the corners are
        // theirs — the same way they are drawn.
        XCTAssertEqual(layout.edge(at: CGPoint(x: 2, y: 2)), .left)
        XCTAssertEqual(layout.edge(at: CGPoint(x: 2, y: 198)), .left)
        XCTAssertEqual(layout.edge(at: CGPoint(x: 398, y: 2)), .right)
        XCTAssertEqual(layout.edge(at: CGPoint(x: 398, y: 198)), .right)
    }

    func testAStripTooThinToHitIsStillClickable() {
        // 3 mm is 6 points at this scale: visible, but nothing anyone could
        // reliably click. The target grows; the drawing does not.
        let layout = layout(left: 3)

        XCTAssertEqual(layout.stripFrame(for: .left).width, 6, accuracy: 0.0001)
        XCTAssertEqual(
            layout.edge(at: CGPoint(x: 15, y: 100)),
            .left,
            "A sliver of a strip still has to be selectable"
        )
    }

    func testAClickInsideTheDiagramNeverTraps() {
        let layout = layout()

        for x in stride(from: 0.0, through: 400, by: 7) {
            for y in stride(from: 0.0, through: 200, by: 7) {
                _ = layout.edge(at: CGPoint(x: x, y: y))
            }
        }
    }

    // MARK: - Drawn strips

    func testStripsAreDrawnAgainstTheDimensionTheyEatInto() {
        let layout = layout(left: 20, top: 10)

        // The left strip takes a bite out of the width: 20 mm of 200 mm.
        XCTAssertEqual(layout.stripFrame(for: .left).width, 40, accuracy: 0.0001)
        XCTAssertEqual(layout.stripFrame(for: .left).height, 200, accuracy: 0.0001)

        // The top strip takes one out of the height: 10 mm of 100 mm.
        XCTAssertEqual(layout.stripFrame(for: .top).height, 20, accuracy: 0.0001)
        XCTAssertEqual(layout.stripFrame(for: .top).width, 400, accuracy: 0.0001)
    }

    func testStripsSitAgainstTheirOwnBorder() {
        let layout = layout()

        XCTAssertEqual(layout.stripFrame(for: .left).minX, 0, accuracy: 0.0001)
        XCTAssertEqual(layout.stripFrame(for: .right).maxX, 400, accuracy: 0.0001)
        XCTAssertEqual(layout.stripFrame(for: .top).minY, 0, accuracy: 0.0001)
        XCTAssertEqual(layout.stripFrame(for: .bottom).maxY, 200, accuracy: 0.0001)
    }

    func testAVeryThinStripIsStillDrawnWideEnoughToSee() {
        // The narrowest margin the settings allow is 3 mm; on a small diagram
        // that rounds to well under a point.
        let layout = TrackpadDiagramLayout(
            zones: [EdgeZoneConfiguration(edge: .left, control: .volume, margin: 3)],
            surface: surface,
            size: CGSize(width: 60, height: 30)
        )

        XCTAssertEqual(
            layout.stripFrame(for: .left).width,
            TrackpadDiagramLayout.minimumDrawnDepth,
            accuracy: 0.0001
        )
    }

    func testTheDiagramCarriesTheTrackpadsProportions() {
        XCTAssertEqual(layout().aspectRatio, 2, accuracy: 0.0001)
    }

    // MARK: - Always a trackpad shape

    /// Every surface the app could be handed, including ones that are not a
    /// trackpad at all.
    private var surfacesToDrawAt: [(name: String, surface: TrackpadSurfaceSize)] {
        [
            ("built-in trackpad", TrackpadSurfaceSize(width: 157.8, height: 97.8)),
            ("Magic Trackpad", TrackpadSurfaceSize(width: 160, height: 114.9)),
            ("fallback", .fallback),
            // The one that started this: a Magic Mouse is a multitouch device
            // too, and it is taller than it is wide.
            ("Magic Mouse", TrackpadSurfaceSize(width: 51.52, height: 90.56)),
            // Neither of these is a trackpad shape at all, so both fall back
            // to the one this app is for.
            ("square", TrackpadSurfaceSize(width: 100, height: 100)),
            ("nonsense", TrackpadSurfaceSize(width: 0, height: 0)),
        ]
    }

    func testTheDiagramIsAlwaysWiderThanItIsTall() {
        for (name, surface) in surfacesToDrawAt {
            let height = TrackpadDiagramLayout.height(forWidth: 190, surface: surface)

            XCTAssertGreaterThan(190, height, "The diagram came out portrait on the \(name)")
            XCTAssertGreaterThan(height, 0, "The diagram came out with no height on the \(name)")
        }
    }

    func testTheAspectRatioIsNeverPortrait() {
        for (name, surface) in surfacesToDrawAt {
            let layout = TrackpadDiagramLayout(zones: [], surface: surface, size: .zero)

            XCTAssertGreaterThanOrEqual(layout.aspectRatio, 1, "\(name) stood the trackpad on end")
        }
    }

    func testAPortraitSurfaceKeepsItsElongationButNotItsOrientation() {
        // 51.52 × 90.56 is 1.76 times as long as it is wide. Drawn on its side
        // it stays 1.76 times as long, rather than being squashed to a square.
        let mouse = TrackpadSurfaceSize(width: 51.52, height: 90.56)
        let layout = TrackpadDiagramLayout(zones: [], surface: mouse, size: .zero)

        XCTAssertEqual(layout.aspectRatio, 90.56 / 51.52, accuracy: 0.0001)
    }

    func testTheHeightFollowsTheWidthItIsAskedFor() {
        let surface = TrackpadSurfaceSize(width: 200, height: 100)

        XCTAssertEqual(TrackpadDiagramLayout.height(forWidth: 190, surface: surface), 95, accuracy: 0.0001)
        XCTAssertEqual(TrackpadDiagramLayout.height(forWidth: 300, surface: surface), 150, accuracy: 0.0001)
    }

    func testAnAbsurdSurfaceFallsBackToAKnownShape() {
        let layout = TrackpadDiagramLayout(
            zones: [],
            surface: TrackpadSurfaceSize(width: 0, height: 0),
            size: size
        )
        let fallback = TrackpadSurfaceSize.fallback

        XCTAssertEqual(layout.aspectRatio, fallback.width / fallback.height, accuracy: 0.0001)
    }

    func testAnUnconfiguredEdgeFallsBackToADefaultZone() {
        let layout = TrackpadDiagramLayout(zones: [], surface: surface, size: size)

        // Nothing configured at all still draws four strips rather than
        // trapping on a missing entry.
        XCTAssertEqual(layout.zone(for: .top).edge, .top)
        XCTAssertFalse(layout.zone(for: .top).isEnabled)
    }

    // MARK: - Strip depth against the real geometry

    func testStripFractionMatchesWhatTheZoneActuallyCatches() {
        let zone = EdgeZoneConfiguration(edge: .left, control: .volume, margin: 30)
        let fraction = zone.stripFraction(surface: surface)

        // A point just inside the drawn strip is inside the real one, and a
        // point just outside it is outside — the drawing does not lie.
        XCTAssertTrue(zone.contains(CGPoint(x: fraction - 0.01, y: 0.5), surface: surface))
        XCTAssertFalse(zone.contains(CGPoint(x: fraction + 0.01, y: 0.5), surface: surface))
    }

    func testVerticalEdgeStripsAreMeasuredAgainstTheWidth() {
        let zone = EdgeZoneConfiguration(edge: .right, control: .volume, margin: 20)

        XCTAssertEqual(zone.stripFraction(surface: surface), 0.1, accuracy: 0.0001)
    }

    func testHorizontalEdgeStripsAreMeasuredAgainstTheHeight() {
        let zone = EdgeZoneConfiguration(edge: .top, control: .volume, margin: 20)

        // The same 20 mm is a fifth of a 100 mm height.
        XCTAssertEqual(zone.stripFraction(surface: surface), 0.2, accuracy: 0.0001)
    }

    func testStripFractionStaysInRangeForAnAbsurdSurface() {
        let zone = EdgeZoneConfiguration(edge: .right, control: .volume, margin: 30)

        XCTAssertEqual(zone.stripFraction(surface: TrackpadSurfaceSize(width: 0, height: 0)), 0)
        XCTAssertEqual(
            zone.stripFraction(surface: TrackpadSurfaceSize(width: 10, height: 10)),
            1,
            "A margin deeper than the trackpad still cannot draw past its edge"
        )
    }
}
