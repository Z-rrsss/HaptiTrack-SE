import CoreGraphics
import Foundation

/// Turns raw touch frames into control adjustments and haptic ticks.
///
/// The engine owns the whole decision: which edge the required contact or
/// contacts started in, whether they are still there, how far their centre has
/// travelled, where that puts the control and when a tick is due. It knows
/// nothing about audio, displays or the trackpad
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

    /// Called when a control has actually been moved, so that something else
    /// can show what happened. Not called for a finger resting on an edge, nor
    /// for movement too small to change the value — a HUD that appeared because
    /// a thumb brushed the trackpad would be worse than no HUD.
    typealias AdjustmentHandler = (ControlAdjustment) -> Void

    private struct ActiveGesture {
        var touchIdentifiers: Set<Int32>
        var zone: EdgeZoneConfiguration
        var control: AdjustableControl
        var lastCentroid: CGPoint
        /// Continuous position in `0...1`, kept apart from the control's own
        /// value so the quantised steps never accumulate rounding drift.
        var value: Double
        var appliedValue: Double
        var accumulator: TickAccumulator
    }

    /// Once a gesture is under way the strip is treated as this much deeper, so
    /// either finger can drift a couple of millimetres inward while sliding
    /// without dropping the gesture. Starting still needs the real margin.
    private static let holdSlack: Double = 6

    /// Speed, in millimetres per second, past which ticks soften. A deliberate
    /// sweep along an edge runs at roughly 50–150 mm/s; beyond that the user is
    /// throwing the value across its range rather than aiming at a step.
    private static let attenuationVelocity: Double = 160

    var zones: [EdgeZoneConfiguration]
    var isEnabled: Bool = true
    var requiresTwoFingers: Bool {
        didSet {
            if requiresTwoFingers != oldValue { reset() }
        }
    }

    private let controlProvider: ControlProvider
    private let onTick: TickHandler
    private let onAdjust: AdjustmentHandler
    private var gesture: ActiveGesture?

    init(
        zones: [EdgeZoneConfiguration] = EdgeZoneConfiguration.defaults(),
        requiresTwoFingers: Bool = false,
        controlProvider: @escaping ControlProvider,
        onTick: @escaping TickHandler,
        onAdjust: @escaping AdjustmentHandler = { _ in }
    ) {
        self.zones = zones
        self.requiresTwoFingers = requiresTwoFingers
        self.controlProvider = controlProvider
        self.onTick = onTick
        self.onAdjust = onAdjust
    }

    /// Whether a gesture is currently driving a control.
    var isTracking: Bool { gesture != nil }

    /// The edge currently being driven, for the settings panel to highlight.
    var trackedEdge: TrackpadEdge? { gesture?.zone.edge }

    func reset() {
        gesture?.control.endAdjustment()
        gesture = nil
    }

    // MARK: - Frame handling

    func consume(_ frame: TrackpadTouchFrame) {
        guard isEnabled else {
            reset()
            return
        }

        let contacts = frame.touches.filter(\.isInContact)

        // Safety mode requires exactly two fingers; compatibility mode keeps
        // the original one-finger gesture. Any other contact count cancels the
        // adjustment, leaving system three- and four-finger gestures alone.
        let requiredContactCount = requiresTwoFingers ? 2 : 1
        guard contacts.count == requiredContactCount else {
            reset()
            return
        }

        let identifiers = Set(contacts.map(\.identifier))
        guard identifiers.count == requiredContactCount else {
            reset()
            return
        }

        if let current = gesture, current.touchIdentifiers == identifiers {
            advance(current, with: contacts, frame: frame)
        } else {
            reset()
            begin(with: contacts, frame: frame)
        }
    }

    // MARK: - Gesture lifecycle

    private func begin(with touches: [TrackpadTouch], frame: TrackpadTouchFrame) {
        guard let zone = zones.first(where: { zone in
            zone.isEnabled && touches.allSatisfy { touch in
                zone.contains(touch.position, surface: frame.surface)
            }
        }) else { return }

        guard let control = controlProvider(zone.control) else { return }

        control.beginAdjustment()
        let accumulator = TickAccumulator(configuration: configuration(for: zone, control: control))

        let value = control.value.clamped(to: 0...1)
        gesture = ActiveGesture(
            touchIdentifiers: Set(touches.map(\.identifier)),
            zone: zone,
            control: control,
            lastCentroid: centroid(of: touches),
            value: value,
            appliedValue: value,
            accumulator: accumulator
        )
    }

    private func advance(
        _ current: ActiveGesture,
        with touches: [TrackpadTouch],
        frame: TrackpadTouchFrame
    ) {
        // If either finger leaves the strip towards the middle of the
        // trackpad, the user is no longer deliberately holding the edge.
        guard touches.allSatisfy({
            current.zone.contains($0.position, surface: frame.surface, slack: Self.holdSlack)
        }) else {
            reset()
            return
        }

        var updated = current
        let currentCentroid = centroid(of: touches)
        let travel = current.zone.travel(
            from: current.lastCentroid,
            to: currentCentroid,
            surface: frame.surface
        )
        updated.lastCentroid = currentCentroid

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
            onAdjust(ControlAdjustment(
                identifier: updated.control.identifier,
                displayName: updated.control.displayName,
                value: quantised,
                displayID: updated.control.adjustmentDisplayID
            ))
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

    private func centroid(of touches: [TrackpadTouch]) -> CGPoint {
        let count = CGFloat(touches.count)
        let sum = touches.reduce(into: CGPoint.zero) { partial, touch in
            partial.x += touch.position.x
            partial.y += touch.position.y
        }
        return CGPoint(x: sum.x / count, y: sum.y / count)
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
