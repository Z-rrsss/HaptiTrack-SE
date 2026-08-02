import CoreGraphics
import XCTest
@testable import HaptiTrack

final class EdgeZoneTests: XCTestCase {

    /// 200 mm wide, 100 mm tall, so the two axes cannot be confused with each
    /// other by accident.
    private let surface = TrackpadSurfaceSize(width: 200, height: 100)

    // MARK: - Hit testing

    func testRightEdgeStripIsMeasuredFromTheRight() {
        let zone = EdgeZoneConfiguration(edge: .right, control: .volume, margin: 20)

        // 20 mm of a 200 mm surface is the last tenth.
        XCTAssertTrue(zone.contains(CGPoint(x: 0.95, y: 0.5), surface: surface))
        XCTAssertTrue(zone.contains(CGPoint(x: 0.90, y: 0.5), surface: surface))
        XCTAssertFalse(zone.contains(CGPoint(x: 0.85, y: 0.5), surface: surface))
        XCTAssertFalse(zone.contains(CGPoint(x: 0.05, y: 0.5), surface: surface))
    }

    func testLeftEdgeStripIsMeasuredFromTheLeft() {
        let zone = EdgeZoneConfiguration(edge: .left, control: .volume, margin: 20)

        XCTAssertTrue(zone.contains(CGPoint(x: 0.05, y: 0.5), surface: surface))
        XCTAssertFalse(zone.contains(CGPoint(x: 0.15, y: 0.5), surface: surface))
    }

    func testTopAndBottomStripsUseTheHeight() {
        let top = EdgeZoneConfiguration(edge: .top, control: .volume, margin: 20)
        let bottom = EdgeZoneConfiguration(edge: .bottom, control: .volume, margin: 20)

        // 20 mm of a 100 mm surface is the last fifth.
        XCTAssertTrue(top.contains(CGPoint(x: 0.5, y: 0.9), surface: surface))
        XCTAssertFalse(top.contains(CGPoint(x: 0.5, y: 0.7), surface: surface))
        XCTAssertTrue(bottom.contains(CGPoint(x: 0.5, y: 0.1), surface: surface))
        XCTAssertFalse(bottom.contains(CGPoint(x: 0.5, y: 0.3), surface: surface))
    }

    func testSlackWidensTheStrip() {
        let zone = EdgeZoneConfiguration(edge: .right, control: .volume, margin: 10)

        XCTAssertFalse(zone.contains(CGPoint(x: 0.90, y: 0.5), surface: surface))
        XCTAssertTrue(zone.contains(CGPoint(x: 0.90, y: 0.5), surface: surface, slack: 15))
    }

    func testAWiderMarginCatchesMore() {
        let narrow = EdgeZoneConfiguration(edge: .right, control: .volume, margin: 5)
        let wide = EdgeZoneConfiguration(edge: .right, control: .volume, margin: 30)
        let position = CGPoint(x: 0.93, y: 0.5)

        XCTAssertFalse(narrow.contains(position, surface: surface))
        XCTAssertTrue(wide.contains(position, surface: surface))
    }

    // MARK: - Travel

    func testVerticalTravelIsMeasuredInMillimetres() {
        let zone = EdgeZoneConfiguration(edge: .right, control: .volume)
        let travel = zone.travel(
            from: CGPoint(x: 0.95, y: 0.2),
            to: CGPoint(x: 0.95, y: 0.7),
            surface: surface
        )

        // Half of a 100 mm height.
        XCTAssertEqual(travel, 50, accuracy: 0.0001)
    }

    func testHorizontalTravelIsMeasuredInMillimetres() {
        let zone = EdgeZoneConfiguration(edge: .bottom, control: .volume)
        let travel = zone.travel(
            from: CGPoint(x: 0.2, y: 0.05),
            to: CGPoint(x: 0.7, y: 0.05),
            surface: surface
        )

        // Half of a 200 mm width.
        XCTAssertEqual(travel, 100, accuracy: 0.0001)
    }

    func testVerticalEdgesIgnoreHorizontalMovement() {
        let zone = EdgeZoneConfiguration(edge: .right, control: .volume)
        let travel = zone.travel(
            from: CGPoint(x: 0.95, y: 0.5),
            to: CGPoint(x: 0.60, y: 0.5),
            surface: surface
        )

        XCTAssertEqual(travel, 0, accuracy: 0.0001)
    }

    func testInvertingFlipsTheSign() {
        var zone = EdgeZoneConfiguration(edge: .right, control: .volume)
        zone.isInverted = true

        let travel = zone.travel(
            from: CGPoint(x: 0.95, y: 0.2),
            to: CGPoint(x: 0.95, y: 0.7),
            surface: surface
        )

        XCTAssertEqual(travel, -50, accuracy: 0.0001)
    }

    // MARK: - Configuration

    func testDefaultsCoverEveryEdgeExactlyOnce() {
        let defaults = EdgeZoneConfiguration.defaults()

        XCTAssertEqual(defaults.count, TrackpadEdge.allCases.count)
        XCTAssertEqual(Set(defaults.map(\.edge)), Set(TrackpadEdge.allCases))
    }

    func testDefaultAssignments() {
        let byEdge = Dictionary(
            uniqueKeysWithValues: EdgeZoneConfiguration.defaults().map { ($0.edge, $0.control) }
        )

        XCTAssertEqual(byEdge[.right], .volume)
        XCTAssertEqual(byEdge[.left], .brightness)
        XCTAssertEqual(byEdge[.top], ControlIdentifier.none)
        XCTAssertEqual(byEdge[.bottom], ControlIdentifier.none)
    }

    func testAnEdgeAssignedToNothingIsDisabled() {
        XCTAssertFalse(EdgeZoneConfiguration(edge: .top, control: .none).isEnabled)
        XCTAssertTrue(EdgeZoneConfiguration(edge: .top, control: .volume).isEnabled)
    }

    func testEdgeAxes() {
        XCTAssertEqual(TrackpadEdge.left.axis, .vertical)
        XCTAssertEqual(TrackpadEdge.right.axis, .vertical)
        XCTAssertEqual(TrackpadEdge.top.axis, .horizontal)
        XCTAssertEqual(TrackpadEdge.bottom.axis, .horizontal)
    }
}
