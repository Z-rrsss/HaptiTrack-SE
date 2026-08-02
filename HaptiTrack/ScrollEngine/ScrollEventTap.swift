import CoreGraphics
import Foundation
import OSLog

/// Observes system-wide scroll wheel events through a `CGEventTap` and reports
/// them as plain values.
///
/// The tap is created with `.listenOnly`: HaptiTrack never modifies, injects,
/// swallows or records events, it only measures how far the content moved. That
/// still requires the Accessibility permission, which the caller is expected to
/// have obtained before calling `start()`.
///
/// The tap runs on the main run loop. A tap that takes too long to return is
/// disabled by the system, and the main thread of a menu bar agent is idle
/// almost all of the time, so the risk is small and the alternative — a
/// dedicated thread plus a hop back to the main thread to actuate — would add
/// latency to the one thing that has to feel immediate. The
/// `tapDisabledByTimeout` case is handled anyway, because "almost all" is not
/// "all".
final class ScrollEventTap {

    /// One scroll event, reduced to what the tick logic needs.
    struct Sample: Equatable {
        /// Vertical scroll distance in points, signed by direction.
        var delta: Double
        var phase: GesturePhase
        /// `true` for pixel-precise devices (trackpads, Magic Mouse), `false`
        /// for a classic notched mouse wheel.
        var isContinuous: Bool
        /// Monotonic time in seconds.
        var timestamp: TimeInterval
    }

    enum StartError: LocalizedError {
        case accessibilityPermissionMissing
        case eventTapCreationFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionMissing:
                return "HaptiTrack needs the Accessibility permission to observe scrolling."
            case .eventTapCreationFailed:
                return "macOS refused to create the scroll event tap."
            }
        }
    }

    /// A mouse wheel reports whole lines rather than points. Ten points per
    /// line is the conversion AppKit itself uses for legacy wheel events.
    private static let pointsPerLine: Double = 10

    private let logger = Logger(subsystem: AppInfo.subsystem, category: "ScrollEventTap")
    private let handler: (Sample) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { eventTap != nil }

    /// - Parameter handler: Called on the main thread for every scroll event.
    init(handler: @escaping (Sample) -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() throws {
        guard eventTap == nil else { return }
        guard AccessibilityAuthorization.isTrusted else {
            throw StartError.accessibilityPermissionMissing
        }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: scrollEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw StartError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        logger.info("Scroll event tap started.")
    }

    func stop() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(eventTap)
        self.eventTap = nil
        self.runLoopSource = nil
        logger.info("Scroll event tap stopped.")
    }

    // MARK: - Event handling

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .scrollWheel:
            handler(sample(from: event))

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system switches a tap off if it ever blocks for too long, or
            // when the user toggles the permission. Both are recoverable.
            logger.notice("Scroll event tap was disabled by the system; re-enabling.")
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

        default:
            break
        }
    }

    private func sample(from event: CGEvent) -> Sample {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let delta: Double = isContinuous
            ? event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            : event.getDoubleValueField(.scrollWheelEventDeltaAxis1) * Self.pointsPerLine

        return Sample(
            delta: delta,
            phase: phase(of: event),
            isContinuous: isContinuous,
            // The event's own timestamp is in mach units; the uptime clock is
            // monotonic, already in seconds, and close enough for velocity.
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }

    private func phase(of event: CGEvent) -> GesturePhase {
        let momentumRaw = UInt32(truncatingIfNeeded: event.getIntegerValueField(.scrollWheelEventMomentumPhase))
        if let momentum = CGMomentumScrollPhase(rawValue: momentumRaw), momentum != .none {
            return momentum == .end ? .ended : .coasting
        }

        let scrollRaw = UInt32(truncatingIfNeeded: event.getIntegerValueField(.scrollWheelEventScrollPhase))
        switch CGScrollPhase(rawValue: scrollRaw) {
        case .ended, .cancelled:
            return .ended
        default:
            // Includes plain wheel events, which carry no phase at all.
            return .active
        }
    }
}

/// C callback trampoline: recovers the tap from `userInfo` and hands the event
/// over. The tap is created with `.listenOnly`, so the return value is ignored
/// by the system; the event is passed straight through regardless.
private func scrollEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        Unmanaged<ScrollEventTap>.fromOpaque(userInfo)
            .takeUnretainedValue()
            .handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
