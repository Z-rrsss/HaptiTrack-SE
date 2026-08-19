import CoreGraphics
import XCTest
@testable import HaptiTrack

final class DisplayTargetTests: XCTestCase {

    private let displays = [
        DisplayTarget.Geometry(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
        DisplayTarget.Geometry(id: 2, frame: CGRect(x: -200, y: 800, width: 1200, height: 900)),
    ]

    func testSelectsTheDisplayContainingThePointer() {
        XCTAssertEqual(
            DisplayTarget.displayID(
                at: CGPoint(x: 500, y: 400),
                in: displays,
                fallback: 99
            ),
            1
        )
        XCTAssertEqual(
            DisplayTarget.displayID(
                at: CGPoint(x: 400, y: 1200),
                in: displays,
                fallback: 99
            ),
            2
        )
    }

    func testFallsBackWhenThePointerIsOutsideEveryDisplay() {
        XCTAssertEqual(
            DisplayTarget.displayID(
                at: CGPoint(x: 5000, y: 5000),
                in: displays,
                fallback: 99
            ),
            99
        )
    }
}
