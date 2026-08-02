import AppKit

/// The default haptic backend, driving the Taptic Engine through the public
/// `NSHapticFeedbackManager` API.
///
/// The API exposes named patterns rather than an intensity value, so the three
/// app-level intensities are mapped onto the three system patterns. The mapping
/// is empirical: `.levelChange` reads as the lightest tick, `.alignment` as the
/// most pronounced one, `.generic` sits in between.
final class SystemHapticEngine: HapticEngine {

    private let performer: NSHapticFeedbackPerformer

    init(performer: NSHapticFeedbackPerformer = NSHapticFeedbackManager.defaultPerformer) {
        self.performer = performer
    }

    /// There is no public API that reports whether the current trackpad has an
    /// actuator. On hardware without one, `perform` is simply a no-op, so the
    /// engine reports itself as available and lets the system decide.
    var isAvailable: Bool { true }

    func perform(_ intensity: HapticIntensity) {
        // `.now` rather than `.default`: a scroll detent should land with the
        // finger movement that earned it, not be deferred to the next screen
        // update the way an alignment guide would be.
        performer.perform(pattern(for: intensity), performanceTime: .now)
    }

    private func pattern(for intensity: HapticIntensity) -> NSHapticFeedbackManager.FeedbackPattern {
        switch intensity {
        case .light: return .levelChange
        case .medium: return .generic
        case .strong: return .alignment
        }
    }
}
