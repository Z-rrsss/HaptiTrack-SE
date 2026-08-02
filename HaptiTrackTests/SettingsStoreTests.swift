import XCTest
@testable import HaptiTrack

@MainActor
final class SettingsStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "HaptiTrackTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFreshInstallStartsEnabledWithTheDefaultFeel() {
        let settings = SettingsStore(defaults: defaults)

        XCTAssertTrue(settings.isScrollHapticsEnabled)
        XCTAssertEqual(settings.stepSize, TickConfiguration.default.stepSize)
        XCTAssertEqual(settings.intensity, .medium)
        XCTAssertFalse(settings.respondsToMouseWheel)
    }

    func testChangesSurviveARestart() {
        let settings = SettingsStore(defaults: defaults)
        settings.isScrollHapticsEnabled = false
        settings.stepSize = 30
        settings.intensity = .strong

        let reloaded = SettingsStore(defaults: defaults)

        XCTAssertFalse(reloaded.isScrollHapticsEnabled)
        XCTAssertEqual(reloaded.stepSize, 30)
        XCTAssertEqual(reloaded.intensity, .strong)
    }

    func testOutOfRangeValuesAreClamped() {
        let settings = SettingsStore(defaults: defaults)

        settings.stepSize = 1000
        XCTAssertEqual(settings.stepSize, SettingsStore.stepSizeRange.upperBound)

        settings.maximumTickRate = -5
        XCTAssertEqual(settings.maximumTickRate, SettingsStore.tickRateRange.lowerBound)
    }

    func testHandEditedDefaultsAreClampedOnLoad() {
        defaults.set(9_999.0, forKey: "scrollHaptics.stepSize")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.stepSize, SettingsStore.stepSizeRange.upperBound)
    }

    func testUnknownIntensityFallsBackToMedium() {
        defaults.set("earthquake", forKey: "scrollHaptics.intensity")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.intensity, .medium)
    }

    func testDetentConfigurationReflectsTheSettings() {
        let settings = SettingsStore(defaults: defaults)
        settings.stepSize = 20
        settings.maximumTickRate = 15

        let configuration = settings.scrollTickConfiguration

        XCTAssertEqual(configuration.stepSize, 20)
        XCTAssertEqual(configuration.maximumTickRate, 15)
    }

    func testRestoreDefaults() {
        let settings = SettingsStore(defaults: defaults)
        settings.isScrollHapticsEnabled = false
        settings.stepSize = 42
        settings.respondsToMouseWheel = true

        settings.resetToDefaults()

        XCTAssertTrue(settings.isScrollHapticsEnabled)
        XCTAssertEqual(settings.stepSize, TickConfiguration.default.stepSize)
        XCTAssertFalse(settings.respondsToMouseWheel)
    }

    func testAttenuationIsOneStepSofter() {
        XCTAssertEqual(HapticIntensity.strong.attenuated, .medium)
        XCTAssertEqual(HapticIntensity.medium.attenuated, .light)
        XCTAssertEqual(HapticIntensity.light.attenuated, .light)
    }
}
