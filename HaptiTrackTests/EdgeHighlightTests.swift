import XCTest
@testable import HaptiTrack

/// The rule the trackpad diagram follows when deciding which side to light up,
/// and the geometry it draws the lit strip with.
final class EdgeHighlightTests: XCTestCase {

    // MARK: - Which edge is active

    func testSelectionLightsUpWhenNothingIsHovered() {
        let highlight = EdgeHighlight(selected: .bottom)

        XCTAssertEqual(highlight.edge, .bottom)
        XCTAssertTrue(highlight.isHighlighted(.bottom))
        XCTAssertFalse(highlight.isHighlighted(.top))
    }

    func testHoverWinsOverSelection() {
        let highlight = EdgeHighlight(selected: .right, hovered: .left)

        XCTAssertEqual(highlight.edge, .left)
        XCTAssertFalse(highlight.isHighlighted(.right))
    }

    func testLettingGoOfTheHoverFallsBackToTheSelection() {
        var highlight = EdgeHighlight(selected: .right, hovered: .top)
        highlight.hovered = nil

        XCTAssertEqual(highlight.edge, .right)
    }

    func testExactlyOneEdgeIsEverHighlighted() {
        for selected in TrackpadEdge.allCases {
            for hovered in TrackpadEdge.allCases.map(Optional.init) + [nil] {
                let highlight = EdgeHighlight(selected: selected, hovered: hovered)
                let lit = TrackpadEdge.allCases.filter(highlight.isHighlighted)
                XCTAssertEqual(lit.count, 1, "selected \(selected), hovered \(String(describing: hovered))")
            }
        }
    }

    // MARK: - Strip geometry

    /// 200 mm × 100 mm, so the two axes cannot be confused for each other.
    private let surface = TrackpadSurfaceSize(width: 200, height: 100)

    func testVerticalEdgeStripsAreMeasuredAgainstTheWidth() {
        let zone = EdgeZoneConfiguration(edge: .right, control: .volume, margin: 20)

        XCTAssertEqual(zone.stripFraction(surface: surface), 0.1, accuracy: 0.0001)
    }

    func testHorizontalEdgeStripsAreMeasuredAgainstTheHeight() {
        let zone = EdgeZoneConfiguration(edge: .top, control: .volume, margin: 20)

        // The same 20 mm is a fifth of a 100 mm height.
        XCTAssertEqual(zone.stripFraction(surface: surface), 0.2, accuracy: 0.0001)
    }

    func testStripFractionMatchesWhatTheZoneActuallyCatches() {
        let zone = EdgeZoneConfiguration(edge: .left, control: .volume, margin: 30)
        let fraction = zone.stripFraction(surface: surface)

        // A point just inside the drawn strip is inside the real one, and a
        // point just outside it is outside — the drawing does not lie.
        XCTAssertTrue(zone.contains(CGPoint(x: fraction - 0.01, y: 0.5), surface: surface))
        XCTAssertFalse(zone.contains(CGPoint(x: fraction + 0.01, y: 0.5), surface: surface))
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
