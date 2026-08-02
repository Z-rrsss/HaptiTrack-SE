import Foundation

/// The part of a gesture's lifecycle that the tick logic cares about.
enum GesturePhase: Equatable {
    /// A finger is on the trackpad and driving the movement.
    case active
    /// The finger has lifted and the movement is coasting on inertia.
    case coasting
    /// The gesture is over; accumulated state should be dropped.
    case ended
}

/// Tuning for `TickAccumulator`.
///
/// Distances are in whatever unit the caller feeds in — points of scroll for
/// the scroll module, millimetres of finger travel for the edge module — and
/// time is always in seconds. The accumulator never interprets the unit, it
/// only compares distances against `stepSize`.
struct TickConfiguration: Equatable {

    /// Distance between two ticks while moving slowly. This is the
    /// "sensitivity" knob: smaller means denser, more precise notches.
    var stepSize: Double = 12

    /// Ceiling, in ticks per second, on how fast pulses may be produced.
    /// Above roughly 25 Hz the Taptic Engine stops reading as separate notches
    /// and starts reading as a continuous buzz, which is exactly the failure
    /// mode that makes haptic feedback unpleasant during long fast movements.
    var maximumTickRate: Double = 22

    /// Extra step widening applied while the movement coasts. Inertia covers a
    /// lot of ground and is not a movement the user is actively making, so
    /// notches during coasting should be sparser than during a drag.
    var coastingStepMultiplier: Double = 2

    /// Weight given to the newest sample when smoothing velocity, in `0...1`.
    /// Low values are steadier but lag behind a sudden flick.
    var velocitySmoothing: Double = 0.3

    /// Speed, in units per second, above which ticks switch to the softer
    /// intensity.
    var attenuationVelocity: Double = 900

    /// A gap longer than this between samples is treated as a new gesture: the
    /// accumulated distance and the velocity estimate are dropped.
    var idleTimeout: TimeInterval = 0.2

    /// Upper bound on how much accumulated distance a single sample may drain.
    /// Samples sometimes arrive in bursts carrying a large delta; without a
    /// cap, one burst could pay out a long backlog of notches at once.
    var maximumTicksPerSample: Int = 2

    static let `default` = TickConfiguration()

    /// Hard floor on the spacing between two pulses.
    ///
    /// Step widening is the primary rate limiter, but it works off a smoothed
    /// velocity that lags a sudden acceleration by a few samples. This is the
    /// safety valve that covers that lag. It is deliberately looser than
    /// `1 / maximumTickRate` so that the two limiters do not fight each other
    /// and make steady movement feel stuttery.
    var minimumTickInterval: TimeInterval {
        1 / (maximumTickRate * 1.5)
    }
}

/// What a single sample produced.
struct TickOutcome: Equatable {
    /// How many ticks the accumulated distance paid for.
    var count: Int = 0
    /// Whether they should be fired at the softer intensity.
    var isAttenuated: Bool = false

    static let none = TickOutcome()
}

/// Turns a stream of continuous movement deltas into discrete ticks.
///
/// The model is a virtual wheel with notches `stepSize` apart: distance
/// accumulates, and every time the accumulator crosses a notch it pays out one
/// tick. The notch spacing is not fixed — it widens with speed so that the
/// *rate* of ticks stays bounded. At a constant speed `v` the accumulator fires
/// `v / step` times per second, so once `v` passes `stepSize * maximumTickRate`
/// the step grows in proportion to `v` and the rate flattens out instead of
/// climbing into a buzz.
///
/// The type is pure: no AppKit, no clocks of its own, no I/O. Time arrives as a
/// parameter, which is what makes the behaviour straightforward to test.
///
/// Shared by the scroll module, where the unit is points of scroll, and by the
/// edge control module, where the unit is millimetres of finger travel.
final class TickAccumulator {

    var configuration: TickConfiguration

    private var accumulator: Double = 0
    private var smoothedVelocity: Double = 0
    private var lastSampleTime: TimeInterval?
    private var lastTickTime: TimeInterval?

    init(configuration: TickConfiguration = .default) {
        self.configuration = configuration
    }

    /// Drops all accumulated state. The next sample starts a fresh gesture.
    func reset() {
        accumulator = 0
        smoothedVelocity = 0
        lastSampleTime = nil
        lastTickTime = nil
    }

    /// Feeds one movement sample to the accumulator.
    ///
    /// - Parameters:
    ///   - delta: Distance travelled since the previous sample, signed by
    ///     direction.
    ///   - timestamp: A monotonically increasing time, in seconds.
    ///   - phase: Where the sample sits in the gesture's lifecycle.
    /// - Returns: The ticks this sample earned.
    func consume(delta: Double, timestamp: TimeInterval, phase: GesturePhase) -> TickOutcome {
        guard phase != .ended else {
            reset()
            return .none
        }

        let elapsed = lastSampleTime.map { timestamp - $0 } ?? .infinity
        lastSampleTime = timestamp

        // A long pause means the previous gesture is over, whether or not an
        // end event ever arrived: start counting from zero rather than letting
        // stale distance carry into the new movement.
        if elapsed > configuration.idleTimeout {
            accumulator = 0
            smoothedVelocity = 0
            lastTickTime = nil
        }

        guard delta != 0 else { return .none }

        // Reversing direction restarts the count from the new direction, so a
        // change of mind never fires a notch it did not travel for.
        if accumulator != 0, signum(accumulator) != signum(delta) {
            accumulator = 0
        }
        accumulator += delta

        updateVelocity(delta: delta, elapsed: elapsed)

        let step = currentStep(for: phase)
        guard abs(accumulator) >= step else { return .none }

        if let lastTickTime, timestamp - lastTickTime < configuration.minimumTickInterval {
            // Too soon after the previous pulse. Keep exactly one step of
            // credit so the wait cannot build a backlog that pays out in a
            // burst once the limiter opens up again.
            accumulator = step * signum(accumulator)
            return .none
        }

        var count = 0
        while abs(accumulator) >= step, count < configuration.maximumTicksPerSample {
            accumulator -= step * signum(accumulator)
            count += 1
        }

        // Whatever is left after hitting the per-sample cap is discarded down
        // to a single step, for the same reason as above.
        if abs(accumulator) > step {
            accumulator = step * signum(accumulator)
        }

        lastTickTime = timestamp

        let isFast = smoothedVelocity >= configuration.attenuationVelocity
        return TickOutcome(count: count, isAttenuated: phase == .coasting || isFast)
    }

    // MARK: - Internals

    private func updateVelocity(delta: Double, elapsed: TimeInterval) {
        // Samples can arrive in bursts a fraction of a millisecond apart; clamp
        // the interval so one tightly packed pair does not report a velocity of
        // several thousand units per second.
        let interval = min(max(elapsed, 1.0 / 240.0), configuration.idleTimeout)
        let instantaneous = abs(delta) / interval

        if smoothedVelocity == 0 {
            smoothedVelocity = instantaneous
        } else {
            let weight = min(max(configuration.velocitySmoothing, 0), 1)
            smoothedVelocity += weight * (instantaneous - smoothedVelocity)
        }
    }

    private func currentStep(for phase: GesturePhase) -> Double {
        let rateLimitedStep = smoothedVelocity / configuration.maximumTickRate
        var step = max(configuration.stepSize, rateLimitedStep)
        if phase == .coasting {
            step *= configuration.coastingStepMultiplier
        }
        return step
    }

    /// Direction only. Zero counts as positive, which is fine because the
    /// callers have already excluded it.
    private func signum(_ value: Double) -> Double {
        value < 0 ? -1 : 1
    }
}
