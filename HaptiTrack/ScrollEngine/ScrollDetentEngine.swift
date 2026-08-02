import Foundation

/// The part of a scroll gesture's lifecycle that the detent logic cares about.
enum ScrollPhase: Equatable {
    /// A finger is on the trackpad and driving the scroll.
    case active
    /// The finger has lifted and macOS is coasting the scroll on inertia.
    case momentum
    /// The gesture is over; accumulated state should be dropped.
    case ended
}

/// Tuning for `ScrollDetentEngine`. Everything is expressed in points of scroll
/// distance and seconds, so the values mean the same thing regardless of where
/// the events came from.
struct DetentConfiguration: Equatable {

    /// Scroll distance, in points, between two detents while scrolling slowly.
    /// This is the "sensitivity" knob exposed in Settings: smaller means denser,
    /// more precise notches.
    var stepSize: Double = 12

    /// Ceiling, in detents per second, on how fast pulses may be produced.
    /// Above roughly 25 Hz the Taptic Engine stops reading as separate notches
    /// and starts reading as a continuous buzz, which is exactly the failure
    /// mode that makes haptic scrolling unpleasant during long fast flicks.
    var maximumDetentRate: Double = 22

    /// Extra step widening applied while macOS coasts the scroll. Inertia can
    /// cover thousands of points, and it is not a movement the user is actively
    /// making, so notches during coasting should be sparser than during a drag.
    var momentumStepMultiplier: Double = 2

    /// Weight given to the newest sample when smoothing scroll velocity, in
    /// `0...1`. Low values are steadier but lag behind a sudden flick.
    var velocitySmoothing: Double = 0.3

    /// Speed, in points per second, above which detents switch to the softer
    /// intensity.
    var attenuationVelocity: Double = 900

    /// A gap longer than this between events is treated as a new gesture: the
    /// accumulated distance and the velocity estimate are dropped.
    var idleTimeout: TimeInterval = 0.2

    /// Upper bound on how much accumulated distance a single event may drain.
    /// Events sometimes arrive in bursts carrying a large delta; without a cap,
    /// one burst could otherwise pay out a long backlog of notches at once.
    var maximumDetentsPerSample: Int = 2

    static let `default` = DetentConfiguration()

    /// Hard floor on the spacing between two pulses.
    ///
    /// Step widening is the primary rate limiter, but it works off a smoothed
    /// velocity that lags a sudden acceleration by a few events. This is the
    /// safety valve that covers that lag. It is deliberately looser than
    /// `1 / maximumDetentRate` so that the two limiters do not fight each other
    /// and make steady scrolling feel stuttery.
    var minimumDetentInterval: TimeInterval {
        1 / (maximumDetentRate * 1.5)
    }
}

/// What a single scroll event produced.
struct DetentOutcome: Equatable {
    /// How many detents the accumulated distance paid for.
    var count: Int = 0
    /// Whether they should be fired at the softer intensity.
    var isAttenuated: Bool = false

    static let none = DetentOutcome()
}

/// Turns a stream of continuous scroll deltas into discrete detents.
///
/// The model is a virtual wheel with notches `stepSize` points apart: scrolled
/// distance accumulates, and every time the accumulator crosses a notch it pays
/// out one detent. The notch spacing is not fixed — it widens with scroll speed
/// so that the *rate* of detents stays bounded. At a constant speed `v` the
/// engine fires `v / step` times per second, so once `v` passes
/// `stepSize * maximumDetentRate` the step grows in proportion to `v` and the
/// rate flattens out instead of climbing into a buzz.
///
/// The type is pure: no AppKit, no clocks of its own, no I/O. Time arrives as a
/// parameter, which is what makes the behaviour straightforward to test.
final class ScrollDetentEngine {

    var configuration: DetentConfiguration

    private var accumulator: Double = 0
    private var smoothedVelocity: Double = 0
    private var lastSampleTime: TimeInterval?
    private var lastDetentTime: TimeInterval?

    init(configuration: DetentConfiguration = .default) {
        self.configuration = configuration
    }

    /// Drops all accumulated state. The next event starts a fresh gesture.
    func reset() {
        accumulator = 0
        smoothedVelocity = 0
        lastSampleTime = nil
        lastDetentTime = nil
    }

    /// Feeds one scroll event to the engine.
    ///
    /// - Parameters:
    ///   - delta: Vertical scroll distance in points, signed by direction.
    ///   - timestamp: A monotonically increasing time, in seconds.
    ///   - phase: Where the event sits in the gesture's lifecycle.
    /// - Returns: The detents this event earned.
    func consume(delta: Double, timestamp: TimeInterval, phase: ScrollPhase) -> DetentOutcome {
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
            lastDetentTime = nil
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

        if let lastDetentTime, timestamp - lastDetentTime < configuration.minimumDetentInterval {
            // Too soon after the previous pulse. Keep exactly one step of
            // credit so the wait cannot build a backlog that pays out in a
            // burst once the limiter opens up again.
            accumulator = step * signum(accumulator)
            return .none
        }

        var count = 0
        while abs(accumulator) >= step, count < configuration.maximumDetentsPerSample {
            accumulator -= step * signum(accumulator)
            count += 1
        }

        // Whatever is left after hitting the per-event cap is discarded down to
        // a single step, for the same reason as above.
        if abs(accumulator) > step {
            accumulator = step * signum(accumulator)
        }

        lastDetentTime = timestamp

        let isFast = smoothedVelocity >= configuration.attenuationVelocity
        return DetentOutcome(count: count, isAttenuated: phase == .momentum || isFast)
    }

    // MARK: - Internals

    private func updateVelocity(delta: Double, elapsed: TimeInterval) {
        // Events can arrive in bursts a fraction of a millisecond apart; clamp
        // the interval so one tightly packed pair does not report a velocity of
        // several thousand points per second.
        let interval = min(max(elapsed, 1.0 / 240.0), configuration.idleTimeout)
        let instantaneous = abs(delta) / interval

        if smoothedVelocity == 0 {
            smoothedVelocity = instantaneous
        } else {
            let weight = min(max(configuration.velocitySmoothing, 0), 1)
            smoothedVelocity += weight * (instantaneous - smoothedVelocity)
        }
    }

    private func currentStep(for phase: ScrollPhase) -> Double {
        let rateLimitedStep = smoothedVelocity / configuration.maximumDetentRate
        var step = max(configuration.stepSize, rateLimitedStep)
        if phase == .momentum {
            step *= configuration.momentumStepMultiplier
        }
        return step
    }

    /// Direction only. Zero counts as positive, which is fine because the
    /// callers have already excluded it.
    private func signum(_ value: Double) -> Double {
        value < 0 ? -1 : 1
    }
}
