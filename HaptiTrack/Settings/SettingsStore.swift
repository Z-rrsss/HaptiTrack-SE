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
    static let detentRateRange: ClosedRange<Double> = 8...40

    private enum Key {
        static let isEnabled = "scrollHaptics.enabled"
        static let stepSize = "scrollHaptics.stepSize"
        static let intensity = "scrollHaptics.intensity"
        static let maximumDetentRate = "scrollHaptics.maximumDetentRate"
        static let isMomentumEnabled = "scrollHaptics.momentumEnabled"
        static let respondsToMouseWheel = "scrollHaptics.respondsToMouseWheel"
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
    @Published var maximumDetentRate: Double {
        didSet {
            let clamped = maximumDetentRate.clamped(to: Self.detentRateRange)
            guard clamped == maximumDetentRate else {
                maximumDetentRate = clamped
                return
            }
            defaults.set(maximumDetentRate, forKey: Key.maximumDetentRate)
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.stepSize: DetentConfiguration.default.stepSize,
            Key.intensity: HapticIntensity.medium.rawValue,
            Key.maximumDetentRate: DetentConfiguration.default.maximumDetentRate,
            Key.isMomentumEnabled: true,
            Key.respondsToMouseWheel: false,
        ])

        isScrollHapticsEnabled = defaults.bool(forKey: Key.isEnabled)
        stepSize = defaults.double(forKey: Key.stepSize).clamped(to: Self.stepSizeRange)
        intensity = defaults.string(forKey: Key.intensity)
            .flatMap(HapticIntensity.init(rawValue:)) ?? .medium
        maximumDetentRate = defaults.double(forKey: Key.maximumDetentRate)
            .clamped(to: Self.detentRateRange)
        isMomentumHapticsEnabled = defaults.bool(forKey: Key.isMomentumEnabled)
        respondsToMouseWheel = defaults.bool(forKey: Key.respondsToMouseWheel)
    }

    /// The current preferences, expressed the way the detent engine wants them.
    var detentConfiguration: DetentConfiguration {
        var configuration = DetentConfiguration.default
        configuration.stepSize = stepSize
        configuration.maximumDetentRate = maximumDetentRate
        return configuration
    }

    /// Restores the shipping defaults.
    func resetToDefaults() {
        isScrollHapticsEnabled = true
        stepSize = DetentConfiguration.default.stepSize
        intensity = .medium
        maximumDetentRate = DetentConfiguration.default.maximumDetentRate
        isMomentumHapticsEnabled = true
        respondsToMouseWheel = false
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
