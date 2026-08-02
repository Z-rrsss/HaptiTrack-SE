import Foundation

/// When each beat of the launch intro happens, in seconds from the moment the
/// overlay is put on screen.
///
/// The schedule is a value rather than a scattering of literals inside the
/// controller for two reasons: the haptic pulse, the click and the scale bump
/// have to be driven off the same clock or they stop feeling like one event,
/// and "the whole thing is over in under two seconds" is a promise worth having
/// a test for. An intro is a flourish; the moment it reads as a splash screen
/// standing between the user and their Mac, it has failed.
struct LaunchAnimationTimeline: Equatable {

    /// The overlay and the name fading in.
    var fadeIn: TimeInterval = 0.22

    /// Two beats, as asked for: one is a twitch, three is a loading screen.
    var pulseCount: Int = 2

    /// When the first pulse fires. Slightly after the fade-in has settled, so
    /// the first tick lands on a name that is already legible.
    var firstPulse: TimeInterval = 0.28

    /// Gap between the start of one pulse and the start of the next.
    var pulseInterval: TimeInterval = 0.46

    /// A pulse swells quickly and settles back more slowly, which is what makes
    /// it read as a heartbeat rather than as a bounce.
    var pulseRise: TimeInterval = 0.14
    var pulseFall: TimeInterval = 0.26

    /// A breath between the last pulse settling and the overlay leaving.
    var hold: TimeInterval = 0.18

    var fadeOut: TimeInterval = 0.34

    /// When pulse `index` fires, counting from zero.
    func pulseTime(_ index: Int) -> TimeInterval {
        firstPulse + Double(index) * pulseInterval
    }

    var pulseTimes: [TimeInterval] {
        (0..<max(pulseCount, 0)).map(pulseTime)
    }

    var fadeOutStart: TimeInterval {
        (pulseTimes.last ?? fadeIn) + pulseRise + pulseFall + hold
    }

    /// Everything, from the overlay appearing to the window closing.
    var total: TimeInterval { fadeOutStart + fadeOut }
}
