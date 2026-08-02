import CoreAudio
import Foundation
import OSLog

/// The volume of one CoreAudio device, in one direction.
///
/// Output and input are the same problem twice — find the default device, ask
/// it for a volume, discover it does not have the property you expected, fall
/// back to the other one — so they are the same code twice, pointed at
/// different scopes. This is the one place in the app that talks to CoreAudio.
///
/// Devices disagree about where their volume lives. Most expose a single
/// "virtual main volume" that CoreAudio maps onto whatever the hardware really
/// has; some — notably several USB and Bluetooth devices — only expose
/// per-channel scalars. Both are tried, in that order. The built-in speakers
/// and the built-in microphone on this machine both answer the first.
final class AudioDeviceVolume {

    /// Which device to drive. A closure rather than an ID because the default
    /// device changes under the app's feet — headphones go in, a meeting app
    /// grabs the microphone — and an ID captured once would outlive it.
    typealias DeviceProvider = () -> AudioObjectID?

    /// `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`, spelled out as
    /// its four-character code. The constant has been renamed once already
    /// (`VirtualMasterVolume` before macOS 12) and lives in a header that keeps
    /// moving between AudioToolbox and CoreAudio, so the literal is steadier
    /// than the symbol.
    private static let virtualMainVolumeSelector: AudioObjectPropertySelector = 0x766D_7663 // 'vmvc'

    private let logger = Logger(subsystem: AppInfo.subsystem, category: "AudioDeviceVolume")
    private let scope: AudioObjectPropertyScope
    private let deviceProvider: DeviceProvider

    init(scope: AudioObjectPropertyScope, device: @escaping DeviceProvider) {
        self.scope = scope
        self.deviceProvider = device
    }

    /// The device the system is playing through.
    static func defaultOutput() -> AudioDeviceVolume {
        AudioDeviceVolume(scope: kAudioDevicePropertyScopeOutput) {
            defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        }
    }

    /// The device the system is listening through.
    static func defaultInput() -> AudioDeviceVolume {
        AudioDeviceVolume(scope: kAudioDevicePropertyScopeInput) {
            defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        }
    }

    // MARK: - Reading and writing

    /// Whether there is a device here whose volume can actually be set.
    var isSettable: Bool {
        guard let device = deviceProvider() else { return false }
        return isSettable(mainVolumeAddress, on: device) || !settableChannels(of: device).isEmpty
    }

    /// The current level, or `nil` if there is nothing to read it from.
    func read() -> Double? {
        guard let device = deviceProvider() else { return nil }

        if let scalar = scalar(at: mainVolumeAddress, on: device) {
            return Double(scalar)
        }

        // Fall back to the average of the individual channels, which is what
        // the sliders in System Settings show for such devices.
        let channels = settableChannels(of: device)
        guard !channels.isEmpty else { return nil }

        let readings = channels.compactMap { scalar(at: channelVolumeAddress($0), on: device) }
        guard !readings.isEmpty else { return nil }
        return Double(readings.reduce(0, +) / Float(readings.count))
    }

    func write(_ newValue: Double) {
        guard let device = deviceProvider() else { return }
        let scalar = Float(newValue.clamped(to: 0...1))

        if isSettable(mainVolumeAddress, on: device) {
            setScalar(scalar, at: mainVolumeAddress, on: device)
        } else {
            for channel in settableChannels(of: device) {
                setScalar(scalar, at: channelVolumeAddress(channel), on: device)
            }
        }
    }

    /// Unmutes the device, if it is muted and says it can be unmuted.
    ///
    /// Only worth doing in one direction: raising the output volume on a muted
    /// device would otherwise be silent in both senses of the word. The input
    /// side deliberately does not call this — see `MicrophoneControl`.
    func unmute() {
        guard let device = deviceProvider() else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
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

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private var mainVolumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: Self.virtualMainVolumeSelector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func channelVolumeAddress(_ channel: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: scope,
            mElement: channel
        )
    }

    /// The stereo pair the device prefers, filtered down to the channels that
    /// actually accept a new level.
    private func settableChannels(of device: AudioObjectID) -> [UInt32] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: scope,
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
            logger.error("Setting the level failed (status \(status)).")
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
