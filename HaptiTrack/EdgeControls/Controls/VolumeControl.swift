import CoreAudio
import Foundation
import OSLog

/// System output volume, driven through CoreAudio.
///
/// This is the one control in the module that uses nothing but public API.
///
/// Devices disagree about where their volume lives. Most expose a single
/// "virtual main volume" that CoreAudio maps onto whatever the hardware really
/// has; some — notably several USB and Bluetooth devices — only expose
/// per-channel scalars. Both are tried, in that order.
final class VolumeControl: AdjustableControl {

    /// `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`, spelled out as
    /// its four-character code. The constant has been renamed once already
    /// (`VirtualMasterVolume` before macOS 12) and lives in a header that keeps
    /// moving between AudioToolbox and CoreAudio, so the literal is steadier
    /// than the symbol.
    private static let virtualMainVolumeSelector: AudioObjectPropertySelector = 0x766D_7663 // 'vmvc'

    private let logger = Logger(subsystem: AppInfo.subsystem, category: "VolumeControl")

    let identifier: ControlIdentifier = .volume
    let displayName = "Volume"

    /// macOS moves the volume in sixteenths for the keyboard keys, so matching
    /// that makes an edge sweep land on exactly the same notches as F11/F12.
    let quantum: Double = 1.0 / 16.0

    var isAvailable: Bool {
        guard let device = defaultOutputDevice else { return false }
        return isSettable(virtualMainVolumeAddress, on: device)
            || !settableChannels(of: device).isEmpty
    }

    var value: Double {
        get { readValue() ?? 0 }
        set { write(newValue.clamped(to: 0...1)) }
    }

    // MARK: - Reading and writing

    private func readValue() -> Double? {
        guard let device = defaultOutputDevice else { return nil }

        if let scalar = scalar(at: virtualMainVolumeAddress, on: device) {
            return Double(scalar)
        }

        // Fall back to the average of the individual channels, which is what
        // the volume slider in System Settings shows for such devices.
        let channels = settableChannels(of: device)
        guard !channels.isEmpty else { return nil }

        let readings = channels.compactMap { scalar(at: channelVolumeAddress($0), on: device) }
        guard !readings.isEmpty else { return nil }
        return Double(readings.reduce(0, +) / Float(readings.count))
    }

    private func write(_ newValue: Double) {
        guard let device = defaultOutputDevice else { return }
        let scalar = Float(newValue)

        if isSettable(virtualMainVolumeAddress, on: device) {
            setScalar(scalar, at: virtualMainVolumeAddress, on: device)
        } else {
            for channel in settableChannels(of: device) {
                setScalar(scalar, at: channelVolumeAddress(channel), on: device)
            }
        }

        // Raising the volume on a muted device would otherwise be silent in
        // both senses of the word.
        if newValue > 0 {
            unmute(device)
        }
    }

    private func unmute(_ device: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return }

        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr,
              isSettable.boolValue else { return }

        var muted: UInt32 = 0
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muted
        )
    }

    // MARK: - CoreAudio plumbing

    private var defaultOutputDevice: AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != kAudioObjectUnknown else {
            logger.error("No default output device (status \(status)).")
            return nil
        }
        return device
    }

    private var virtualMainVolumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: Self.virtualMainVolumeSelector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func channelVolumeAddress(_ channel: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
    }

    /// The stereo pair the device prefers, filtered down to the channels that
    /// actually accept a new volume.
    private func settableChannels(of device: AudioObjectID) -> [UInt32] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var channels: (UInt32, UInt32) = (1, 2)
        var size = UInt32(MemoryLayout<(UInt32, UInt32)>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &channels)

        return [channels.0, channels.1].filter {
            isSettable(channelVolumeAddress($0), on: device)
        }
    }

    private func scalar(at address: AudioObjectPropertyAddress, on device: AudioObjectID) -> Float? {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return nil }

        var scalar: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &scalar)
        return status == noErr ? scalar : nil
    }

    private func setScalar(_ scalar: Float, at address: AudioObjectPropertyAddress, on device: AudioObjectID) {
        var address = address
        var scalar = scalar
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &scalar
        )
        if status != noErr {
            logger.error("Setting volume failed (status \(status)).")
        }
    }

    private func isSettable(_ address: AudioObjectPropertyAddress, on device: AudioObjectID) -> Bool {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return false }

        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(device, &address, &settable)
        return status == noErr && settable.boolValue
    }
}
