import Foundation

/// Input gain of the microphone the system is listening through.
///
/// The same `AudioDeviceVolume` the output volume uses, pointed at the default
/// input device instead. Public API throughout: the microphone *permission*
/// gates recording, not the input gain, and HaptiTrack never opens the
/// microphone — it moves a slider the same way System Settings does. If a
/// future macOS does start gating the property, the writes fail, `isSupported`
/// goes false and the control takes itself out of the picker.
///
/// Two things are deliberately different from the output side:
///
/// It never unmutes. Raising the output volume on a muted device is a
/// convenience; doing the same to a microphone would turn a muted microphone
/// back on because a finger brushed an edge, which is not a convenience.
///
/// It reports itself unsupported rather than merely unavailable when there is
/// no usable input device. Every Mac has speakers, so an output volume that
/// cannot be set right now is a passing condition worth explaining in the
/// panel; a Mac can genuinely have no microphone, or one whose gain is fixed
/// in hardware, and an inert Microphone row in the picker would be a lie.
final class MicrophoneControl: AdjustableControl {

    private let volume: AudioDeviceVolume

    let identifier: ControlIdentifier = .microphone
    let displayName = "Microphone"

    /// There is no microphone key on the keyboard to match, so sixteen steps
    /// is chosen to match everything else the module drives.
    let quantum: Double = 1.0 / 16.0

    init(volume: AudioDeviceVolume = .defaultInput()) {
        self.volume = volume
    }

    var isSupported: Bool { volume.isSettable }

    var isAvailable: Bool { volume.isSettable }

    var value: Double {
        get { volume.read() ?? 0 }
        set { volume.write(newValue.clamped(to: 0...1)) }
    }
}
