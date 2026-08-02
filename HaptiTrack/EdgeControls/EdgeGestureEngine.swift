import CoreGraphics
import Foundation

/// Turns raw touch frames into control adjustments and haptic ticks.
///
/// The engine owns the whole decision: which edge a finger started in, whether
/// it is still there, how far it has travelled, where that puts the control and
/// when a tick is due. It knows nothing about audio, displays or the trackpad
/// framework — touches come in as values and the control is an
/// `AdjustableControl`, which is what lets the whole thing be tested against a
/// mock without any hardware.
///
/// Movement is fed to the same `TickAccumulator` the scroll module uses, with
/// millimetres of finger travel in place of points of scroll, so a fast sweep
/// spreads its ticks out exactly the way a fast scroll does.
///
/// Not thread-safe: drive it from one thread, which in practice is the main one.
final class EdgeGestureEngine {

    /// Resolves an assignment to something drivable, or `nil` if the control is
    /// unavailable on this machine.
    typealias ControlProvider = (ControlIdentifier) -> AdjustableControl?

    /// Called when a notch is crossed, with the intensity it should be felt at.
    typealias TickHandler = (HapticIntensity) -> Void

    private struct ActiveGesture {
        var touchIdentifier: Int32
        var zone: EdgeZoneConfiguration
        var control: AdjustableControl
        var lastPosition: CGPoint
        /// Continuous position in `0...1`, kept apart from the control's own
        /// value so the quantised steps never accumulate rounding drift.
        var value: Double
        var appliedValue: Double
        var accumulator: TickAccumulator
    }

    /// Once a gesture is under way the strip is treated as this much deeper, so
    /// a finger that drifts a couple of millimetres inward while sliding does
    /// not drop the gesture. Starting one still needs the real margin.
    private static let holdSlack: Double = 6

    /// Speed, in millimetres per second, past which ticks soften. A deliberate
    /// sweep along an edge runs at roughly 50–150 mm/s; beyond that the user is
    /// throwing the value across its range rather than aiming at a step.
    private static let attenuationVelocity: Double = 160

    var zones: [EdgeZoneConfiguration]
    var isEnabled: Bool = true

    private let controlProvider: ControlProvider
    private let onTick: TickHandler
    private var gesture: ActiveGesture?

    init(
        zones: [EdgeZoneConfiguration] = EdgeZoneConfiguration.defaults(),
        controlProvider: @escaping ControlProvider,
        onTick: @escaping TickHandler
    ) {
        self.zones = zones
        self.controlProvider = controlProvider
        self.onTick = onTick
    }

    /// Whether a gesture is currently driving a control.
    var isTracking: Bool { gesture != nil }

    /// The edge currently being driven, for the settings panel to highlight.
    var trackedEdge: TrackpadEdge? { gesture?.zone.edge }

    func reset() {
        gesture = nil
    }

    // MARK: - Frame handling

    func consume(_ frame: TrackpadTouchFrame) {
        guard isEnabled else {
            reset()
            return
        }

        let contacts = frame.touches.filter(\.isInContact)

        // An edge gesture is a one-finger gesture, full stop. Two fingers is a
        // scroll, three or four is a Mission Control swipe, and none of those
        // should be moving the volume as a side effect. Requiring exactly one
        // contact is what keeps edge controls out of the way of everything the
        // trackpad already does.
        guard contacts.count == 1, let touch = contacts.first else {
            reset()
            return
        }

        if let current = gesture, current.touchIdentifier == touch.identifier {
            advance(current, with: touch, frame: frame)
        } else {
            reset()
            begin(with: touch, frame: frame)
        }
    }

    // MARK: - Gesture lifecycle

    private func begin(with touch: TrackpadTouch, frame: TrackpadTouchFrame) {
        guard let zone = zones.first(where: {
            $0.isEnabled && $0.contains(touch.position, surface: frame.surface)
        }) else { return }

        guard let control = controlProvider(zone.control) else { return }

        let accumulator = TickAccumulator(configuration: configuration(for: zone, control: control))

        let value = control.value.clamped(to: 0...1)
        gesture = ActiveGesture(
            touchIdentifier: touch.identifier,
            zone: zone,
            control: control,
            lastPosition: touch.position,
            value: value,
            appliedValue: value,
            accumulator: accumulator
        )
    }

    private func advance(_ current: ActiveGesture, with touch: TrackpadTouch, frame: TrackpadTouchFrame) {
        // Leaving the strip towards the middle of the trackpad ends the
        // gesture: the user has stopped adjusting and started pointing.
        guard current.zone.contains(touch.position, surface: frame.surface, slack: Self.holdSlack) else {
            reset()
            return
        }

        var updated = current
        let travel = current.zone.travel(
            from: current.lastPosition,
            to: touch.position,
            surface: frame.surface
        )
        updated.lastPosition = touch.position

        guard travel != 0 else {
            gesture = updated
            return
        }

        updated.value = (updated.value + travel / current.zone.travelForFullRange)
            .clamped(to: 0...1)

        // Snap to the control's own notches so an edge sweep lands on the same
        // values the keyboard keys would produce.
        let step = quantum(for: current.zone, control: current.control)
        let quantised = ((updated.value / step).rounded() * step).clamped(to: 0...1)
        if quantised != updated.appliedValue {
            updated.control.value = quantised
            updated.appliedValue = quantised
        }

        let outcome = updated.accumulator.consume(
            delta: travel,
            timestamp: frame.timestamp,
            phase: .active
        )
        if outcome.count > 0 {
            onTick(outcome.isAttenuated ? .light : .medium)
        }

        gesture = updated
    }

    // MARK: - Tuning

    /// Working notch size: the control's natural step, optionally halved.
    private func quantum(for zone: EdgeZoneConfiguration, control: AdjustableControl) -> Double {
        max(control.quantum * zone.tickDensity.quantumMultiplier, 0.001)
    }

    private func configuration(for zone: EdgeZoneConfiguration, control: AdjustableControl) -> TickConfiguration {
        var configuration = TickConfiguration.default
        // One tick per notch, expressed as the finger travel a notch costs.
        configuration.stepSize = zone.travelForFullRange * quantum(for: zone, control: control)
        configuration.attenuationVelocity = Self.attenuationVelocity
        return configuration
    }
}
