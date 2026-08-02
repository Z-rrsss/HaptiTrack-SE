import XCTest
@testable import HaptiTrack

/// Smoke test: proves the test target links against the app target.
/// Feature-level tests live next to the module they cover.
final class HaptiTrackTests: XCTestCase {

    func testAppBundleIsAnAgent() {
        let bundle = Bundle(for: AppDelegate.self)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
    }
}
