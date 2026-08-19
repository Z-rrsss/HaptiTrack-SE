import CoreGraphics
import Foundation
import OSLog

/// Brightness of the display under the pointer when an edge gesture begins.
///
/// The control chooses one path per gesture:
///
/// 1. Apple's DisplayServices/CoreDisplay path.
/// 2. DDC/CI hardware brightness for compatible external displays.
/// 3. A click-through per-screen software dimming panel.
///
/// The target and the chosen path stay fixed until the fingers lift, so moving
/// the pointer cannot switch screens or mix hardware and software values in the
/// middle of one sweep.
final class BrightnessControl: AdjustableControl {

    private struct Session {
        var displayID: CGDirectDisplayID
        var method: BrightnessControlMethod
        var value: Double
    }

    private let native: HardwareBrightnessServicing
    private let ddc: HardwareBrightnessServicing
    private let software: SoftwareDimmingServicing
    private let displayResolver: () -> CGDirectDisplayID
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "BrightnessControl")

    private var session: Session?

    let identifier: ControlIdentifier = .brightness
    let displayName = "Brightness"
    let quantum: Double = 1.0 / 16.0

    init(
        native: HardwareBrightnessServicing = NativeDisplayBrightnessService(),
        ddc: HardwareBrightnessServicing = DDCBrightnessService(),
        software: SoftwareDimmingServicing = SoftwareDimmingController(),
        displayResolver: @escaping () -> CGDirectDisplayID = DisplayTarget.displayUnderPointer
    ) {
        self.native = native
        self.ddc = ddc
        self.software = software
        self.displayResolver = displayResolver
    }

    var isAvailable: Bool {
        software.isAvailable(for: displayResolver())
    }

    var adjustmentDisplayID: CGDirectDisplayID? { session?.displayID }

    /// Exposed internally for diagnostics and unit tests; it is nil between
    /// gestures because the next screen may need a different path.
    var activeMethod: BrightnessControlMethod? { session?.method }

    func beginAdjustment() {
        guard session == nil else { return }
        let displayID = displayResolver()

        if let value = native.readBrightness(for: displayID) {
            software.clearDimming(for: displayID)
            session = Session(displayID: displayID, method: .native, value: value)
            return
        }

        if let value = ddc.readBrightness(for: displayID) {
            software.clearDimming(for: displayID)
            session = Session(displayID: displayID, method: .ddc, value: value)
            return
        }

        if software.isAvailable(for: displayID) {
            session = Session(
                displayID: displayID,
                method: .software,
                value: software.readBrightness(for: displayID).clamped(to: 0...1)
            )
        }
    }

    func endAdjustment() {
        session = nil
    }

    var value: Double {
        get {
            if let session { return session.value }

            // This path is mainly for settings and diagnostics. The gesture
            // engine always calls beginAdjustment() before reading the value.
            let displayID = displayResolver()
            if let value = native.readBrightness(for: displayID) { return value }
            let softwareValue = software.readBrightness(for: displayID)
            if softwareValue < 1 { return softwareValue }
            return ddc.readBrightness(for: displayID) ?? 1
        }
        set {
            if session == nil { beginAdjustment() }
            guard var current = session else { return }
            let requested = newValue.clamped(to: 0...1)

            switch current.method {
            case .native:
                if native.writeBrightness(requested, for: current.displayID) {
                    current.value = requested
                } else {
                    current = fallBackFromNative(to: requested, session: current)
                }

            case .ddc:
                if ddc.writeBrightness(requested, for: current.displayID) {
                    current.value = requested
                } else {
                    current = fallBackToSoftware(requested, session: current)
                }

            case .software:
                if software.writeBrightness(requested, for: current.displayID) {
                    current.value = requested
                }
            }

            session = current
        }
    }

    private func fallBackFromNative(to value: Double, session: Session) -> Session {
        var updated = session

        // A native service can disappear after a display wakes or changes
        // mode. Give DDC one chance before switching to visual dimming.
        if ddc.readBrightness(for: session.displayID) != nil,
           ddc.writeBrightness(value, for: session.displayID) {
            software.clearDimming(for: session.displayID)
            updated.method = .ddc
            updated.value = value
            logger.notice("Native brightness failed; continued with DDC/CI.")
            return updated
        }

        logger.notice("Native brightness failed; continued with software dimming.")
        return fallBackToSoftware(value, session: session)
    }

    private func fallBackToSoftware(_ value: Double, session: Session) -> Session {
        var updated = session
        if software.writeBrightness(value, for: session.displayID) {
            updated.method = .software
            updated.value = value
        }
        return updated
    }
}
