import AppKit

/// A short, quiet click, played alongside a haptic pulse.
///
/// This is a system sound rather than a bundled asset: `Tink` is the shortest
/// thing macOS ships, it is already on every Mac, and using it means the app
/// carries no audio resources and no licence question. If a future macOS drops
/// it, `sound` comes back `nil` and the intro simply plays silently.
///
/// Deliberately not a general "play a sound" facility. Audible feedback for
/// scrolling is explicitly out of scope for the app; this exists to punctuate
/// the launch flourish and nothing else.
final class ClickSound {

    /// Well under the volume of a notification. The click is there to be felt
    /// as much as heard — it lands with a haptic pulse — and an intro that
    /// announces itself across the room would be a nuisance, not a flourish.
    private static let volume: Float = 0.35

    private let sound: NSSound?

    init(named name: String = "Tink") {
        sound = NSSound(named: NSSound.Name(name))
        sound?.volume = Self.volume
    }

    var isAvailable: Bool { sound != nil }

    /// Plays from the start, cutting short a click still ringing from the
    /// previous pulse rather than overlapping the two.
    func play() {
        guard let sound else { return }
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    func stop() {
        sound?.stop()
    }
}
