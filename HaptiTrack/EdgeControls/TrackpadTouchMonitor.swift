import CoreGraphics
import Foundation
import OSLog

/// The physical size of a trackpad's sensor surface, in millimetres.
///
/// Edge margins and gesture travel are configured in millimetres rather than in
/// fractions of the surface, so the same settings feel identical on a 13" built
/// in trackpad and on a Magic Trackpad.
struct TrackpadSurfaceSize: Equatable {
    var width: Double
    var height: Double

    /// A 13" MacBook Pro trackpad, used only when the device refuses to report
    /// its own dimensions.
    static let fallback = TrackpadSurfaceSize(width: 157.8, height: 97.8)
}

/// One finger in one frame.
struct TrackpadTouch: Equatable {
    /// Stable for the life of a single contact, which is what lets a gesture
    /// follow one finger and ignore the others.
    var identifier: Int32
    /// Normalised to `0...1`, origin at the bottom-left of the surface.
    var position: CGPoint
    /// Whether the finger is actually resting on the surface.
    var isInContact: Bool
}

/// Everything the trackpad reported in one sampling interval.
struct TrackpadTouchFrame: Equatable {
    var touches: [TrackpadTouch]
    /// Monotonic, in seconds.
    var timestamp: TimeInterval
    var surface: TrackpadSurfaceSize
}

/// Reads raw finger positions from the trackpad.
///
/// ⚠️ **Private API.** `CGEventTap` and `NSEvent` report scroll *deltas*, never
/// where a finger actually is, so nothing public can answer "is this finger
/// near the right-hand edge?". `MultitouchSupport.framework` can, and it is
/// what every trackpad utility on macOS uses for this.
///
/// The framework is opened with `dlopen`, so a macOS release that drops it
/// leaves edge controls unavailable rather than breaking the app.
///
/// ### Struct layout
///
/// The callback hands over a C array of `MTTouch`, a struct with no public
/// header. Rather than declare a Swift struct and trust Swift's layout rules to
/// match a C ABI they make no promise about, the fields are read at fixed byte
/// offsets from a raw pointer.
///
/// The offsets below were **verified against this machine** (macOS 26.5, Apple
/// silicon, built-in trackpad) by dumping the first 192 bytes of a real contact
/// frame: fields land exactly where the layout predicts, and everything from
/// +96 onwards is the `0xAAAAAAAA` fill of untouched memory, which pins the
/// stride at 96 bytes.
///
///     +0   int32   frame
///     +8   double  timestamp
///     +16  int32   identifier
///     +20  int32   state
///     +24  int32   fingerId
///     +28  int32   handId
///     +32  float   normalised x        ← used
///     +36  float   normalised y        ← used
///     +40  float   normalised velocity x
///     +44  float   normalised velocity y
///     +48  float   size
///     +56  float   angle
///     +60  float   major axis
///     +64  float   minor axis
///     +68  float   absolute x
///     +72  float   absolute y
///     +92  float   z density
///     ---  stride 96
///
/// A layout change in a future macOS would show up as normalised coordinates
/// far outside `0...1`, which `isPlausible(_:)` checks for on every frame; the
/// monitor stops itself rather than feed nonsense to the gesture engine.
final class TrackpadTouchMonitor {

    private typealias DeviceCreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterCallback = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
    private typealias UnregisterCallback = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
    private typealias DeviceStart = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias DeviceStop = @convention(c) (UnsafeMutableRawPointer) -> Void
    private typealias DeviceGetDimensions = @convention(c) (
        UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>
    ) -> Int32
    /// `bool MTDeviceIsBuiltIn(MTDeviceRef)`. Verified present on macOS 26.5,
    /// answering true for the trackpad and false for a Magic Mouse.
    private typealias DeviceIsBuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
    /// `int MTDeviceGetFamilyID(MTDeviceRef, int*)`. Verified on macOS 26.5:
    /// 105 for the built-in trackpad, 112 for a Magic Mouse.
    private typealias DeviceGetFamilyID = @convention(c) (
        UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>
    ) -> Int32

    /// `int (*)(MTDeviceRef, MTTouch*, int32_t, double, int32_t)`
    fileprivate typealias MTContactCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32

    private enum Layout {
        static let stride = 96
        static let identifier = 16
        static let state = 20
        static let normalisedX = 32
        static let normalisedY = 36
    }

    /// Observed contact states. The framework reports a wider range than this,
    /// but on a capacitive trackpad anything from "hovering in range" through
    /// "breaking contact" means a finger is on the glass — a light slide was
    /// seen alternating between 2 and 4 mid-gesture, so a stricter test would
    /// drop gestures halfway through.
    private static let contactStates: ClosedRange<Int32> = 2...5

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    enum StartError: LocalizedError {
        case frameworkUnavailable
        case noDevices

        var errorDescription: String? {
            switch self {
            case .frameworkUnavailable:
                return "This version of macOS does not expose the multitouch framework."
            case .noDevices:
                return "No multitouch trackpad was found."
            }
        }
    }

    private let logger = Logger(subsystem: AppInfo.subsystem, category: "TouchMonitor")
    private let handler: (TrackpadTouchFrame) -> Void

    private let framework: PrivateFramework?
    private let registerCallback: RegisterCallback?
    private let unregisterCallback: UnregisterCallback?
    private let deviceStart: DeviceStart?
    private let deviceStop: DeviceStop?

    private var devices: [UnsafeMutableRawPointer] = []

    /// One surface per open device, because "multitouch device" is a wider
    /// category than "trackpad": a Magic Mouse is one too, and measuring its
    /// frames with the trackpad's ruler would put a finger's millimetres in
    /// the wrong place entirely.
    private let surfaces = SurfaceStore()

    /// Set once the reported coordinates stop making sense, which is the only
    /// signal available that the struct layout has moved.
    private var layoutLooksBroken = false

    var isRunning: Bool { !devices.isEmpty }

    /// The trackpad the settings panel should draw: the built-in one, or the
    /// largest of whatever else is attached. The fallback until started.
    var surfaceSize: TrackpadSurfaceSize { surfaces.primary }

    /// - Parameter handler: Called on the main thread, once per frame.
    init(handler: @escaping (TrackpadTouchFrame) -> Void) {
        self.handler = handler
        framework = PrivateFramework(path: Self.frameworkPath)
        registerCallback = framework?.function("MTRegisterContactFrameCallback")
        unregisterCallback = framework?.function("MTUnregisterContactFrameCallback")
        deviceStart = framework?.function("MTDeviceStart")
        deviceStop = framework?.function("MTDeviceStop")
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func start() throws {
        guard devices.isEmpty else { return }
        guard let framework,
              let createList: DeviceCreateList = framework.function("MTDeviceCreateList"),
              let registerCallback,
              let deviceStart else {
            throw StartError.frameworkUnavailable
        }

        guard let list = createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else {
            throw StartError.noDevices
        }

        activeMonitor.set(self)
        layoutLooksBroken = false
        surfaces.removeAll()

        let isBuiltIn: DeviceIsBuiltIn? = framework.function("MTDeviceIsBuiltIn")
        let getFamilyID: DeviceGetFamilyID? = framework.function("MTDeviceGetFamilyID")
        var candidates: [Candidate] = []

        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)

            registerCallback(device, trackpadContactCallback)
            deviceStart(device, 0)
            devices.append(device)

            guard let size = dimensions(of: device, framework: framework) else { continue }

            var family: Int32 = 0
            if let getFamilyID, getFamilyID(device, &family) != 0 { family = 0 }

            let candidate = Candidate(
                surface: size,
                isBuiltIn: isBuiltIn?(device) ?? false,
                familyID: family
            )
            candidates.append(candidate)
            surfaces.set(candidate, for: device)

            logger.info("""
                Device \(index): \(size.width, format: .fixed(precision: 1)) × \
                \(size.height, format: .fixed(precision: 1)) mm, family \(family), \
                built in \(candidate.isBuiltIn), \
                \(candidate.isTrackpad ? "driving edge gestures" : "ignored: not a trackpad").
                """)
        }

        surfaces.primary = Self.primarySurface(among: candidates)

        guard !devices.isEmpty else { throw StartError.noDevices }
        logger.info("Touch monitor started on \(self.devices.count) device(s).")
    }

    func stop() {
        guard !devices.isEmpty else { return }
        for device in devices {
            deviceStop?(device)
            unregisterCallback?(device, trackpadContactCallback)
        }
        devices.removeAll()
        surfaces.removeAll()
        activeMonitor.clear(self)
        logger.info("Touch monitor stopped.")
    }

    /// What is known about one multitouch device.
    struct Candidate: Equatable {
        var surface: TrackpadSurfaceSize
        var isBuiltIn: Bool
        var familyID: Int32 = 0

        /// Whether this device may drive edge gestures.
        ///
        /// Edge controls are a trackpad feature, and "multitouch device" is a
        /// wider category than "trackpad": a Magic Mouse reports touches too,
        /// and resting a palm near the top of one would otherwise change the
        /// volume. Two tests, both of which a device has to pass:
        ///
        /// **It is not a known mouse.** Family 112 is the Magic Mouse on the
        /// machine this was measured on. 113 is its sibling by every published
        /// account and is *not* verified here — which is why it only ever adds
        /// to the excluded list and never decides anything on its own.
        ///
        /// **Its surface is landscape.** A trackpad is wider than it is tall
        /// and a mouse's touch surface is taller than it is wide, because one
        /// sits under the fingers and the other under the palm. This is a fact
        /// about the shape of the hardware rather than a table of model
        /// numbers, so it holds for devices that did not exist when this was
        /// written.
        ///
        /// Both tests are framed to exclude rather than to admit: a device
        /// this does not recognise is treated as a trackpad. Breaking edge
        /// controls on a Magic Trackpad — external, `isBuiltIn` false, and a
        /// family ID nobody here has seen — would be a worse failure than a
        /// mouse that still works.
        var isTrackpad: Bool {
            guard !Self.mouseFamilyIDs.contains(familyID) else { return false }
            guard surface.width > 0, surface.height > 0 else { return true }
            return surface.width > surface.height
        }

        /// Verified: 112 is the Magic Mouse attached to the machine this was
        /// written on. 113 is documented as the second generation everywhere
        /// it is discussed, and is unverified.
        private static let mouseFamilyIDs: Set<Int32> = [112, 113]
    }

    /// The device the settings panel should draw.
    ///
    /// Trackpads only, since they are the only devices that can drive an edge
    /// gesture; drawing the one thing the user cannot use would be a strange
    /// thing for the panel to do. The built-in one wins outright, failing that
    /// the largest — on a desktop with a Magic Trackpad and a Magic Mouse
    /// attached, the trackpad is the bigger by a wide margin anyway.
    ///
    /// Taking whichever device happened to be last in the framework's list —
    /// which is what this used to do — drew the settings diagram at the size
    /// of a Magic Mouse: 51 × 91 mm, taller than it is wide, so the trackpad
    /// came out portrait and dragged the settings window down the screen with
    /// it.
    static func primarySurface(among candidates: [Candidate]) -> TrackpadSurfaceSize {
        let trackpads = candidates.filter(\.isTrackpad)

        if let builtIn = trackpads.first(where: \.isBuiltIn) {
            return builtIn.surface
        }
        let largest = trackpads.max { left, right in
            left.surface.width * left.surface.height < right.surface.width * right.surface.height
        }
        return largest?.surface ?? .fallback
    }

    /// Physical surface size. `MTDeviceGetSensorSurfaceDimensions` reports
    /// hundredths of a millimetre — the built-in trackpad here answers
    /// 15780 × 9780, i.e. 157.8 × 97.8 mm, which matches the hardware.
    private func dimensions(of device: UnsafeMutableRawPointer, framework: PrivateFramework) -> TrackpadSurfaceSize? {
        guard let getDimensions: DeviceGetDimensions =
                framework.function("MTDeviceGetSensorSurfaceDimensions") else { return nil }

        var width: Int32 = 0
        var height: Int32 = 0
        guard getDimensions(device, &width, &height) == 0, width > 0, height > 0 else { return nil }

        return TrackpadSurfaceSize(width: Double(width) / 100, height: Double(height) / 100)
    }

    // MARK: - Frame decoding

    /// Called on the framework's own thread.
    ///
    /// - Parameter device: The device the frame came from, which is what says
    ///   how many millimetres its normalised coordinates are worth.
    fileprivate func handleFrame(
        device: UnsafeMutableRawPointer?,
        touches: UnsafeMutableRawPointer?,
        count: Int32
    ) {
        guard !layoutLooksBroken else { return }

        // Edge controls are a trackpad feature. A Magic Mouse reports touches
        // too, and a palm resting near the top of one would otherwise be a
        // finger at the top edge of a very small trackpad. Dropped here rather
        // than in the gesture engine, which is deliberately ignorant of
        // hardware: the monitor is what knows one device from another.
        guard surfaces.isTrackpad(device) else { return }

        var decoded: [TrackpadTouch] = []
        decoded.reserveCapacity(Int(count))

        if let touches, count > 0 {
            for index in 0..<Int(count) {
                let base = index * Layout.stride
                let x = Double(touches.loadUnaligned(fromByteOffset: base + Layout.normalisedX, as: Float.self))
                let y = Double(touches.loadUnaligned(fromByteOffset: base + Layout.normalisedY, as: Float.self))

                guard isPlausible(x), isPlausible(y) else {
                    layoutLooksBroken = true
                    logger.error("""
                        Multitouch frame reported an implausible position (\(x), \(y)). \
                        The MTTouch layout has probably changed; stopping the monitor.
                        """)
                    DispatchQueue.main.async { [weak self] in self?.stop() }
                    return
                }

                let state = touches.loadUnaligned(fromByteOffset: base + Layout.state, as: Int32.self)
                decoded.append(TrackpadTouch(
                    identifier: touches.loadUnaligned(fromByteOffset: base + Layout.identifier, as: Int32.self),
                    position: CGPoint(x: x, y: y),
                    isInContact: Self.contactStates.contains(state)
                ))
            }
        }

        let frame = TrackpadTouchFrame(
            touches: decoded,
            timestamp: ProcessInfo.processInfo.systemUptime,
            surface: surfaces.surface(for: device)
        )
        DispatchQueue.main.async { [weak self] in
            self?.handler(frame)
        }
    }

    /// Coordinates are normalised, so anything meaningfully outside `0...1` is
    /// not a coordinate. The slack absorbs the small overshoot the hardware
    /// reports at the very edges of the sensor.
    private func isPlausible(_ coordinate: Double) -> Bool {
        coordinate.isFinite && coordinate > -0.25 && coordinate < 1.25
    }
}

/// `MTRegisterContactFrameCallback` takes a bare C function pointer with no
/// refcon, so the callback has to find its way back to the monitor through
/// file-scope state. (`MTRegisterContactFrameCallbackWithRefcon` exists and
/// would avoid this, but its argument order is undocumented and unverified,
/// while the plain variant is the one confirmed working on this machine.)
///
/// Only one monitor is ever active, and the box is lock-guarded because the
/// callback arrives on the framework's thread while `start`/`stop` run on the
/// main one.
private final class ActiveMonitorBox {
    private let lock = NSLock()
    private weak var monitor: TrackpadTouchMonitor?

    func set(_ monitor: TrackpadTouchMonitor) {
        lock.lock()
        defer { lock.unlock() }
        self.monitor = monitor
    }

    func clear(_ monitor: TrackpadTouchMonitor) {
        lock.lock()
        defer { lock.unlock() }
        if self.monitor === monitor { self.monitor = nil }
    }

    var current: TrackpadTouchMonitor? {
        lock.lock()
        defer { lock.unlock() }
        return monitor
    }
}

private let activeMonitor = ActiveMonitorBox()

private let trackpadContactCallback: TrackpadTouchMonitor.MTContactCallback = { device, touches, count, _, _ in
    activeMonitor.current?.handleFrame(device: device, touches: touches, count: count)
    return 0
}

/// The physical size of each open device, plus which one the settings panel
/// draws.
///
/// Lock-guarded because it is written on the main thread while devices are
/// opened and closed, and read from the framework's own thread on every frame.
private final class SurfaceStore {

    private let lock = NSLock()
    private var byDevice: [UnsafeMutableRawPointer: TrackpadTouchMonitor.Candidate] = [:]
    private var primarySurface: TrackpadSurfaceSize = .fallback

    var primary: TrackpadSurfaceSize {
        get {
            lock.lock()
            defer { lock.unlock() }
            return primarySurface
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            primarySurface = newValue
        }
    }

    func set(_ candidate: TrackpadTouchMonitor.Candidate, for device: UnsafeMutableRawPointer) {
        lock.lock()
        defer { lock.unlock() }
        byDevice[device] = candidate
    }

    /// The size of the device a frame came from, falling back to the primary
    /// one for a device that would not report its dimensions.
    func surface(for device: UnsafeMutableRawPointer?) -> TrackpadSurfaceSize {
        lock.lock()
        defer { lock.unlock() }
        guard let device, let candidate = byDevice[device] else { return primarySurface }
        return candidate.surface
    }

    /// Whether frames from this device count as trackpad gestures. A device
    /// that never reported its dimensions is not recognised either way, and is
    /// let through rather than silently switched off.
    func isTrackpad(_ device: UnsafeMutableRawPointer?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let device, let candidate = byDevice[device] else { return true }
        return candidate.isTrackpad
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        byDevice.removeAll()
        primarySurface = .fallback
    }
}
