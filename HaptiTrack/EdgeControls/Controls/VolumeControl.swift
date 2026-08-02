import Foundation

/// System output volume.
///
/// One of the two controls in the module that uses nothing but public API. All
/// the CoreAudio work lives in `AudioDeviceVolume`; this adds the one thing
/// that is specific to playback.
final class VolumeControl: AdjustableControl {

    private let volume: AudioDeviceVolume

    let identifier: ControlIdentifier = .volume
    let displayName = "Volume"

    /// macOS moves the volume in sixteenths for the keyboard keys, so matching
    /// that makes an edge sweep land on exactly the same notches as F11/F12.
    let quantum: Double = 1.0 / 16.0

    init(volume: AudioDeviceVolume = .defaultOutput()) {
        self.volume = volume
    }

    var isAvailable: Bool { volume.isSettable }

    var value: Double {
        get { volume.read() ?? 0 }
        set {
            let clamped = newValue.clamped(to: 0...1)
            volume.write(clamped)

            // Raising the volume on a muted device would otherwise be silent
            // in both senses of the word.
            if clamped > 0 {
                volume.unmute()
            }
        }
    }
}
