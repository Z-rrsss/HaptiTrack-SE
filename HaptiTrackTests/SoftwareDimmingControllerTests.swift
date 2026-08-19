import XCTest
@testable import HaptiTrack

final class SoftwareDimmingControllerTests: XCTestCase {

    func testFullBrightnessHasNoOverlay() {
        XCTAssertEqual(SoftwareDimmingController.opacity(forBrightness: 1), 0, accuracy: 0.0001)
    }

    func testZeroBrightnessKeepsARecoverableAmountVisible() {
        XCTAssertEqual(
            SoftwareDimmingController.opacity(forBrightness: 0),
            SoftwareDimmingController.maximumOpacity,
            accuracy: 0.0001
        )
        XCTAssertLessThan(SoftwareDimmingController.maximumOpacity, 1)
    }

    func testSoftwareOpacityClampsInvalidRangeEndpoints() {
        XCTAssertEqual(
            SoftwareDimmingController.opacity(forBrightness: -2),
            SoftwareDimmingController.maximumOpacity,
            accuracy: 0.0001
        )
        XCTAssertEqual(SoftwareDimmingController.opacity(forBrightness: 2), 0, accuracy: 0.0001)
    }
}
