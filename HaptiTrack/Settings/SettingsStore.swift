import Combine
import Foundation

/// User preferences, persisted in `UserDefaults` and observable by the UI and
/// by the scroll engine.
@MainActor
final class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    // Ranges the UI binds its sliders to, and which incoming values are clamped
    // to so a hand-edited defaults entry cannot produce a nonsensical feel.
    static let stepSizeRange: ClosedRange<Double> = 4...48
    static let tickRateRange: ClosedRange<Double> = 8...40

    private enum Key {
        static let isEnabled = "scrollHaptics.enabled"
        static let stepSize = "scrollHaptics.stepSize"
        static let intensity = "scrollHaptics.intensity"
        static let maximumTickRate = "scrollHaptics.maximumTickRate"
        static let isMomentumEnabled = "scrollHaptics.momentumEnabled"
        static let respondsToMouseWheel = "scrollHaptics.respondsToMouseWheel"
        static let areEdgeControlsEnabled = "edgeControls.enabled"
        static let requiresTwoFingers = "edgeControls.requiresTwoFingers"
        static let edgeZones = "edgeControls.zones"
    }

    private let defaults: UserDefaults

    /// Master switch for the scroll haptics module.
    @Published var isScrollHapticsEnabled: Bool {
        didSet { defaults.set(isScrollHapticsEnabled, forKey: Key.isEnabled) }
    }

    /// Distance in points between two notches at low speed. Lower is denser.
    ///
    /// Assigning inside `didSet` re-enters the setter when the property is
    /// `@Published`, unlike a plain stored property, so the clamp writes back
    /// only when it actually changes something. Clamping is idempotent, so the
    /// re-entry stops one level deep.
    @Published var stepSize: Double {
        didSet {
            let clamped = stepSize.clamped(to: Self.stepSizeRange)
            guard clamped == stepSize else {
                stepSize = clamped
                return
            }
            defaults.set(stepSize, forKey: Key.stepSize)
        }
    }

    /// Strength of a single pulse.
    @Published var intensity: HapticIntensity {
        didSet { defaults.set(intensity.rawValue, forKey: Key.intensity) }
    }

    /// Ceiling on pulses per second during fast scrolling.
    @Published var maximumTickRate: Double {
        didSet {
            let clamped = maximumTickRate.clamped(to: Self.tickRateRange)
            guard clamped == maximumTickRate else {
                maximumTickRate = clamped
                return
            }
            defaults.set(maximumTickRate, forKey: Key.maximumTickRate)
        }
    }

    /// Whether notches keep firing while macOS coasts the scroll after the
    /// fingers have lifted.
    @Published var isMomentumHapticsEnabled: Bool {
        didSet { defaults.set(isMomentumHapticsEnabled, forKey: Key.isMomentumEnabled) }
    }

    /// Whether a classic notched mouse wheel should also produce haptics. Off
    /// by default: such a wheel has detents of its own, and doubling them tends
    /// to feel like an echo rather than an improvement.
    @Published var respondsToMouseWheel: Bool {
        didSet { defaults.set(respondsToMouseWheel, forKey: Key.respondsToMouseWheel) }
    }

    /// Master switch for the edge control module.
    @Published var areEdgeControlsEnabled: Bool {
        didSet { defaults.set(areEdgeControlsEnabled, forKey: Key.areEdgeControlsEnabled) }
    }

    /// Safety switch for edge controls. When enabled, both fingers must begin
    /// inside the same edge strip; ordinary one-finger pointing cannot trigger
    /// an adjustment.
    @Published var requiresTwoFingersForEdgeControls: Bool {
        didSet { defaults.set(requiresTwoFingersForEdgeControls, forKey: Key.requiresTwoFingers) }
    }

    /// One entry per edge, always all four and always in `TrackpadEdge.allCases`
    /// order. Stored as JSON rather than as a flat pile of keys so that adding
    /// a knob to `EdgeZoneConfiguration` does not mean inventing four more
    /// `UserDefaults` keys and a migration.
    @Published var edgeZones: [EdgeZoneConfiguration] {
        didSet {
            guard let data = try? JSONEncoder().encode(edgeZones) else { return }
            defaults.set(data, forKey: Key.edgeZones)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.stepSize: TickConfiguration.default.stepSize,
            Key.intensity: HapticIntensity.medium.rawValue,
            Key.maximumTickRate: TickConfiguration.default.maximumTickRate,
            Key.isMomentumEnabled: true,
            Key.respondsToMouseWheel: false,
            Key.areEdgeControlsEnabled: true,
            Key.requiresTwoFingers: true,
        ])

        isScrollHapticsEnabled = defaults.bool(forKey: Key.isEnabled)
        stepSize = defaults.double(forKey: Key.stepSize).clamped(to: Self.stepSizeRange)
        intensity = defaults.string(forKey: Key.intensity)
            .flatMap(HapticIntensity.init(rawValue:)) ?? .medium
        maximumTickRate = defaults.double(forKey: Key.maximumTickRate)
            .clamped(to: Self.tickRateRange)
        isMomentumHapticsEnabled = defaults.bool(forKey: Key.isMomentumEnabled)
        respondsToMouseWheel = defaults.bool(forKey: Key.respondsToMouseWheel)
        areEdgeControlsEnabled = defaults.bool(forKey: Key.areEdgeControlsEnabled)
        requiresTwoFingersForEdgeControls = defaults.bool(forKey: Key.requiresTwoFingers)
        edgeZones = Self.decodeZones(from: defaults.data(forKey: Key.edgeZones))
    }

    /// Reads the stored zones back, repairing anything unexpected.
    ///
    /// The engine indexes edges by identity rather than by position, so a
    /// stored list that is short, reordered, or missing an edge added in a
    /// later version has to come back complete: stored entries win, defaults
    /// fill the gaps, and the order is always canonical.
    private static func decodeZones(from data: Data?) -> [EdgeZoneConfiguration] {
        let stored = data
            .flatMap { try? JSONDecoder().decode([EdgeZoneConfiguration].self, from: $0) } ?? []
        let byEdge = Dictionary(stored.map { ($0.edge, $0) }, uniquingKeysWith: { first, _ in first })

        return EdgeZoneConfiguration.defaults().map { fallback in
            guard var zone = byEdge[fallback.edge] else { return fallback }
            zone.margin = zone.margin.clamped(to: EdgeZoneConfiguration.marginRange)
            zone.travelForFullRange = zone.travelForFullRange
                .clamped(to: EdgeZoneConfiguration.travelRange)
            return zone
        }
    }

    /// The configuration for one edge.
    func zone(for edge: TrackpadEdge) -> EdgeZoneConfiguration {
        edgeZones.first { $0.edge == edge } ?? EdgeZoneConfiguration(edge: edge)
    }

    /// Replaces one edge's configuration, leaving the other three alone.
    func updateZone(_ zone: EdgeZoneConfiguration) {
        guard let index = edgeZones.firstIndex(where: { $0.edge == zone.edge }) else {
            edgeZones.append(zone)
            return
        }
        guard edgeZones[index] != zone else { return }
        edgeZones[index] = zone
    }

    /// The current preferences, expressed the way the tick accumulator wants them.
    var scrollTickConfiguration: TickConfiguration {
        var configuration = TickConfiguration.default
        configuration.stepSize = stepSize
        configuration.maximumTickRate = maximumTickRate
        return configuration
    }

    /// Restores the shipping defaults.
    func resetToDefaults() {
        isScrollHapticsEnabled = true
        stepSize = TickConfiguration.default.stepSize
        intensity = .medium
        maximumTickRate = TickConfiguration.default.maximumTickRate
        isMomentumHapticsEnabled = true
        respondsToMouseWheel = false
        areEdgeControlsEnabled = true
        requiresTwoFingersForEdgeControls = true
        edgeZones = EdgeZoneConfiguration.defaults()
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
