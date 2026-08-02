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

    // MARK: - Edge controls

    func testEdgeZonesStartAtTheDefaults() {
        let settings = SettingsStore(defaults: defaults)

        XCTAssertTrue(settings.areEdgeControlsEnabled)
        XCTAssertEqual(settings.edgeZones, EdgeZoneConfiguration.defaults())
    }

    func testEdgeZoneChangesSurviveARestart() {
        let settings = SettingsStore(defaults: defaults)
        var zone = settings.zone(for: .top)
        zone.control = .whitePoint
        zone.margin = 18
        zone.isInverted = true
        settings.updateZone(zone)

        let reloaded = SettingsStore(defaults: defaults)
        let restored = reloaded.zone(for: .top)

        XCTAssertEqual(restored.control, .whitePoint)
        XCTAssertEqual(restored.margin, 18)
        XCTAssertTrue(restored.isInverted)
    }

    func testUpdatingOneEdgeLeavesTheOthersAlone() {
        let settings = SettingsStore(defaults: defaults)
        var zone = settings.zone(for: .right)
        zone.control = .none
        settings.updateZone(zone)

        XCTAssertEqual(settings.zone(for: .right).control, ControlIdentifier.none)
        XCTAssertEqual(settings.zone(for: .left).control, .brightness)
        XCTAssertEqual(settings.edgeZones.count, TrackpadEdge.allCases.count)
    }

    func testAPartiallyStoredEdgeListIsCompleted() {
        // Only one edge on disk, as if written by an older version.
        let stored = [EdgeZoneConfiguration(edge: .bottom, control: .volume, margin: 12)]
        defaults.set(try! JSONEncoder().encode(stored), forKey: "edgeControls.zones")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.edgeZones.count, TrackpadEdge.allCases.count)
        XCTAssertEqual(settings.edgeZones.map(\.edge), TrackpadEdge.allCases.map { $0 })
        XCTAssertEqual(settings.zone(for: .bottom).margin, 12)
        XCTAssertEqual(settings.zone(for: .right).control, .volume)
    }

    func testCorruptEdgeDataFallsBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: "edgeControls.zones")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.edgeZones, EdgeZoneConfiguration.defaults())
    }

    func testStoredEdgeValuesAreClampedOnLoad() {
        let stored = [EdgeZoneConfiguration(edge: .right, control: .volume, margin: 9_999, travelForFullRange: -5)]
        defaults.set(try! JSONEncoder().encode(stored), forKey: "edgeControls.zones")

        let settings = SettingsStore(defaults: defaults)
        let zone = settings.zone(for: .right)

        XCTAssertEqual(zone.margin, EdgeZoneConfiguration.marginRange.upperBound)
        XCTAssertEqual(zone.travelForFullRange, EdgeZoneConfiguration.travelRange.lowerBound)
    }

    func testRestoreDefaultsAlsoResetsEdges() {
        let settings = SettingsStore(defaults: defaults)
        var zone = settings.zone(for: .right)
        zone.control = .none
        settings.updateZone(zone)

        settings.resetToDefaults()

        XCTAssertEqual(settings.edgeZones, EdgeZoneConfiguration.defaults())
    }

    func testAttenuationIsOneStepSofter() {
        XCTAssertEqual(HapticIntensity.strong.attenuated, .medium)
        XCTAssertEqual(HapticIntensity.medium.attenuated, .light)
        XCTAssertEqual(HapticIntensity.light.attenuated, .light)
    }
}
