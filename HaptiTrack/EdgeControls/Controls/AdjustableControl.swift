import Foundation

/// Stable identifier for a control, used to persist an edge's assignment.
///
/// The raw values are written to `UserDefaults`, so they must not change once
/// shipped. Adding a case is enough to make a new control assignable — nothing
/// in `EdgeGestureEngine` or the settings UI enumerates controls by hand.
enum ControlIdentifier: String, CaseIterable, Identifiable, Codable {
    case none
    case volume
    case brightness
    case whitePoint
    case keyboardBacklight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        case .whitePoint: return "White Point"
        case .keyboardBacklight: return "Keyboard Backlight"
        }
    }
}

/// Something with a single continuous value that an edge gesture can drive.
///
/// The whole point of this protocol is that an edge is just a knob: it knows
/// how far the finger travelled and nothing at all about audio, displays or
/// colour temperature. Anything that can express itself as a `0...1` value can
/// be assigned to an edge without touching the gesture code.
protocol AdjustableControl: AnyObject {

    var identifier: ControlIdentifier { get }

    var displayName: String { get }

    /// Whether the control can be read and written on this machine right now.
    /// A control that is unavailable is skipped rather than driven blindly.
    var isAvailable: Bool { get }

    /// Whether this Mac has the underlying hardware or service at all.
    ///
    /// Distinct from `isAvailable`, which comes and goes with whatever is
    /// plugged in: an external display can take brightness away and give it
    /// back, so that control stays in the picker with a note explaining itself.
    /// A Mac with no backlit keyboard, on the other hand, will never grow one,
    /// and offering a knob that could never do anything is worse than not
    /// offering it.
    var isSupported: Bool { get }

    /// The natural increment of the underlying control, as a fraction of the
    /// full range — `1/16` for anything that follows the macOS keyboard steps.
    ///
    /// Edge gestures quantise to this so the value lands on the same notches
    /// the system itself uses, and fire one haptic tick per notch crossed.
    var quantum: Double { get }

    /// The current value, always clamped to `0...1`.
    var value: Double { get set }
}

extension AdjustableControl {
    var quantum: Double { 1.0 / 16.0 }

    /// Most controls are a property of the Mac rather than of what is attached
    /// to it, so they are always on offer; only their availability moves.
    var isSupported: Bool { true }
}
