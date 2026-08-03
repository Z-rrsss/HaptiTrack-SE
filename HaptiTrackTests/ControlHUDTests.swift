import AppKit
import XCTest
@testable import HaptiTrack

/// Finding the notch, and saying what the HUD says.
final class ControlHUDTests: XCTestCase {

    // MARK: - Finding the notch

    /// The machine these tests were written on: a 14" MacBook Pro, 1728 points
    /// wide, 771 and 772 points of menu bar either side of the housing, 32
    /// points of safe area.
    func testARealNotchIsMeasuredBetweenTheMenuBarAreas() {
        let notch = NotchGeometry.make(
            screenWidth: 1728,
            safeAreaTop: 32,
            auxiliaryLeftWidth: 771,
            auxiliaryRightWidth: 772
        )

        XCTAssertTrue(notch.isPhysical)
        XCTAssertEqual(notch.size.width, 185, accuracy: 0.0001)
        XCTAssertEqual(notch.size.height, 32, accuracy: 0.0001)
    }

    func testADifferentMacIsMeasuredDifferently() {
        // The width is never assumed from another machine's numbers: a screen
        // of a different width, or menu bar strips of a different size, give a
        // different notch.
        let narrower = NotchGeometry.make(
            screenWidth: 1512,
            safeAreaTop: 32,
            auxiliaryLeftWidth: 668,
            auxiliaryRightWidth: 669
        )

        XCTAssertTrue(narrower.isPhysical)
        XCTAssertEqual(narrower.size.width, 175, accuracy: 0.0001)
        XCTAssertNotEqual(narrower.size.width, NotchGeometry.standard.width)
    }

    func testNoSafeAreaMeansNoNotch() {
        // An external display, a Mac mini, or any notebook made before 2021.
        let notch = NotchGeometry.make(
            screenWidth: 2560,
            safeAreaTop: 0,
            auxiliaryLeftWidth: nil,
            auxiliaryRightWidth: nil
        )

        XCTAssertFalse(notch.isPhysical)
        XCTAssertEqual(notch.size, NotchGeometry.standard)
    }

    func testMissingMenuBarAreasMeanNoNotch() {
        let notch = NotchGeometry.make(
            screenWidth: 1728,
            safeAreaTop: 34,
            auxiliaryLeftWidth: nil,
            auxiliaryRightWidth: nil
        )

        XCTAssertFalse(notch.isPhysical, "Nothing to measure the gap between")
        XCTAssertEqual(notch.size, NotchGeometry.standard)
    }

    func testEmptyMenuBarAreasMeanNoNotch() {
        let notch = NotchGeometry.make(
            screenWidth: 1728,
            safeAreaTop: 32,
            auxiliaryLeftWidth: 0,
            auxiliaryRightWidth: 0
        )

        XCTAssertFalse(notch.isPhysical, "Menu bar strips of no width are not either side of anything")
        XCTAssertEqual(notch.size, NotchGeometry.standard)
    }

    func testOneEmptyMenuBarAreaMeansNoNotch() {
        let notch = NotchGeometry.make(
            screenWidth: 1728,
            safeAreaTop: 32,
            auxiliaryLeftWidth: 771,
            auxiliaryRightWidth: 0
        )

        XCTAssertFalse(notch.isPhysical)
        XCTAssertEqual(notch.size, NotchGeometry.standard)
    }

    func testMenuBarAreasWiderThanTheScreenFallBackRatherThanInvertTheNotch() {
        let notch = NotchGeometry.make(
            screenWidth: 1728,
            safeAreaTop: 32,
            auxiliaryLeftWidth: 900,
            auxiliaryRightWidth: 900
        )

        XCTAssertFalse(notch.isPhysical)
        XCTAssertEqual(notch.size, NotchGeometry.standard)
        XCTAssertGreaterThan(notch.size.width, 0)
    }

    func testTheScreenTheTestsAreRunningOnIsReadWithoutCrashing() {
        let notch = NotchGeometry.forScreen(NSScreen.main)

        XCTAssertGreaterThan(notch.size.width, 0)
        XCTAssertGreaterThan(notch.size.height, 0)
    }

    // MARK: - Where the HUD sits

    private let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    func testTheHUDHangsFromTheTopOfTheScreenAndIsCentred() {
        let notch = NotchGeometry(size: CGSize(width: 185, height: 32), isPhysical: true)
        let frame = notch.hudFrame(in: screenFrame, contentHeight: 46)

        XCTAssertEqual(frame.midX, screenFrame.midX, accuracy: 0.0001)
        XCTAssertEqual(frame.maxY, screenFrame.maxY, accuracy: 0.0001, "Flush with the top edge")
        XCTAssertEqual(frame.height, 78, accuracy: 0.0001, "The notch plus what hangs below it")
    }

    func testTheHUDIsExactlyAsWideAsTheNotchItGrowsOutOf() {
        for width in [140.0, 175.0, 185.0, 220.0] {
            let notch = NotchGeometry(size: CGSize(width: width, height: 32), isPhysical: true)

            XCTAssertEqual(
                notch.hudFrame(in: screenFrame, contentHeight: 46).width,
                width,
                accuracy: 0.0001,
                "A HUD wider than the notch is a black bar over the menu bar"
            )
        }
    }

    func testTheHUDTakesItsWidthFromTheMeasuredNotch() {
        // End to end: menu bar strips in, HUD frame out, no fixed width in
        // between.
        let notch = NotchGeometry.make(
            screenWidth: 1728,
            safeAreaTop: 32,
            auxiliaryLeftWidth: 771,
            auxiliaryRightWidth: 772
        )
        let frame = notch.hudFrame(in: screenFrame, contentHeight: 46)

        XCTAssertEqual(frame.width, 185, accuracy: 0.0001)
    }

    func testTheHUDIsTheSameShapeWithAndWithoutANotch() {
        // The whole point of the invented notch: identical behaviour on
        // hardware that has none.
        let physical = NotchGeometry(size: NotchGeometry.standard, isPhysical: true)
        let invented = NotchGeometry(size: NotchGeometry.standard, isPhysical: false)

        XCTAssertEqual(
            physical.hudFrame(in: screenFrame, contentHeight: 46),
            invented.hudFrame(in: screenFrame, contentHeight: 46)
        )
    }

    func testTheHUDFollowsTheScreenItIsShownOn() {
        let notch = NotchGeometry(size: NotchGeometry.standard, isPhysical: false)
        // An external display sitting to the right of and above the built-in.
        let external = CGRect(x: 1728, y: 200, width: 2560, height: 1440)
        let frame = notch.hudFrame(in: external, contentHeight: 46)

        XCTAssertEqual(frame.midX, external.midX, accuracy: 0.0001)
        XCTAssertEqual(frame.maxY, external.maxY, accuracy: 0.0001)
    }

    func testThisMachinesNotchIsMeasuredNotAssumed() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let notch = NotchGeometry.forScreen(screen)
        try XCTSkipUnless(notch.isPhysical, "This Mac has no notch to measure")

        let left = try XCTUnwrap(screen.auxiliaryTopLeftArea?.width)
        let right = try XCTUnwrap(screen.auxiliaryTopRightArea?.width)

        XCTAssertEqual(notch.size.width, screen.frame.width - left - right, accuracy: 0.0001)
        XCTAssertEqual(notch.size.height, screen.safeAreaInsets.top, accuracy: 0.0001)
    }

    // MARK: - What the HUD says

    func testThePercentageIsWhatTheUserWouldSay() {
        XCTAssertEqual(presentation(0).percentageText, "0%")
        XCTAssertEqual(presentation(1).percentageText, "100%")
        XCTAssertEqual(presentation(0.5).percentageText, "50%")
        XCTAssertEqual(presentation(1.0 / 16.0).percentageText, "6%")
    }

    func testThePercentageIsRoundedRatherThanTruncated() {
        XCTAssertEqual(presentation(0.615).percentageText, "62%")
        XCTAssertEqual(presentation(0.614).percentageText, "61%")
    }

    func testAValueOutsideTheRangeSitsAtTheEnd() {
        XCTAssertEqual(presentation(-0.4).value, 0)
        XCTAssertEqual(presentation(1.7).value, 1)
        XCTAssertEqual(presentation(1.7).percentageText, "100%")
    }

    func testNonsenseReadsAsZeroRatherThanDrawingNonsense() {
        XCTAssertEqual(presentation(.nan).value, 0)
        XCTAssertEqual(presentation(.infinity).value, 0)
    }

    func testAnAdjustmentBecomesWhatTheHUDShows() {
        let adjustment = ControlAdjustment(
            identifier: .brightness,
            displayName: "Brightness",
            value: 0.62
        )
        let presentation = ControlHUDPresentation(adjustment)

        XCTAssertEqual(presentation.title, "Brightness")
        XCTAssertEqual(presentation.percentageText, "62%")
        XCTAssertEqual(presentation.symbolName, ControlIdentifier.brightness.symbolName)
    }

    func testEveryControlHasAnIconThatExists() {
        for identifier in ControlIdentifier.allCases {
            XCTAssertNotNil(
                NSImage(systemSymbolName: identifier.symbolName, accessibilityDescription: nil),
                "\(identifier.displayName) has no symbol called \(identifier.symbolName)"
            )
        }
    }

    private func presentation(_ value: Double) -> ControlHUDPresentation {
        ControlHUDPresentation(title: "Brightness", symbolName: "sun.max.fill", value: value)
    }
}
