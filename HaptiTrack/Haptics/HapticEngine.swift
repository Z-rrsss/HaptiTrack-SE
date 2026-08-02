import Foundation

/// How strong a single haptic pulse should feel, expressed in app terms rather
/// than in terms of any particular backend's vocabulary.
enum HapticIntensity: String, CaseIterable, Identifiable {
    case light
    case medium
    case strong

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }

    /// One step softer. Used for detents fired during fast scrolling and
    /// momentum, where pulses arrive close enough together that full strength
    /// stops reading as separate notches and starts reading as a buzz.
    var attenuated: HapticIntensity {
        switch self {
        case .light, .medium: return .light
        case .strong: return .medium
        }
    }
}

/// Anything capable of producing a discrete haptic pulse.
///
/// The shipping implementation is `SystemHapticEngine`, built on the public
/// `NSHapticFeedbackManager` API. This protocol is the seam that lets a second
/// backend — one with finer control over actuation intensity and timing — be
/// added later without touching the scroll engine, the settings or the UI.
protocol HapticEngine: AnyObject {

    /// Whether this engine can actually actuate on the current machine.
    var isAvailable: Bool { get }

    /// Called before haptics start, so a backend can open devices or warm up.
    func prepare()

    /// Fires a single pulse. Called on the main thread.
    func perform(_ intensity: HapticIntensity)

    /// Called when haptics stop, so a backend can release what it opened.
    func teardown()
}

extension HapticEngine {
    func prepare() {}
    func teardown() {}
}
