import Foundation

/// The set of controls an edge can be assigned to.
///
/// Instances are created once and shared: `BrightnessControl` and
/// `NightShiftControl` each open a private framework or an Objective-C class on
/// init, and there is no reason to pay for that per gesture.
///
/// Registering a new control is a two-line change here plus a case in
/// `ControlIdentifier`. Nothing else in the app needs to learn about it — the
/// settings picker is built from `assignableControls`, and the gesture engine
/// only ever sees `AdjustableControl`.
final class ControlRegistry {

    static let shared = ControlRegistry()

    private let controls: [ControlIdentifier: AdjustableControl]

    init(
        controls: [AdjustableControl] = [
            VolumeControl(),
            BrightnessControl(),
            NightShiftControl(),
            KeyboardBacklightControl(),
        ]
    ) {
        self.controls = Dictionary(
            controls.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The control assigned to an identifier, or `nil` for `.none` and for
    /// anything this machine cannot drive.
    func control(for identifier: ControlIdentifier) -> AdjustableControl? {
        guard identifier != .none, let control = controls[identifier] else { return nil }
        return control.isAvailable ? control : nil
    }

    /// Whether a control exists and works here, for greying out the picker.
    func isAvailable(_ identifier: ControlIdentifier) -> Bool {
        identifier == .none || control(for: identifier) != nil
    }

    /// Everything the user may assign to an edge: `.none`, plus every control
    /// this Mac actually has, in canonical order.
    ///
    /// - Parameter current: What the edge is set to now. It stays in the list
    ///   even when this machine does not support it, so an assignment made on
    ///   another Mac — or on this one with different hardware attached — shows
    ///   what it is rather than appearing to have silently reassigned itself.
    func assignableControls(including current: ControlIdentifier = .none) -> [ControlIdentifier] {
        ControlIdentifier.allCases.filter { identifier in
            identifier == .none
                || identifier == current
                || controls[identifier]?.isSupported == true
        }
    }
}
