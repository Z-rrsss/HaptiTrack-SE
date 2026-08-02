import AppKit
import IOKit.hid

/// The Input Monitoring permission, which raw multitouch data sits behind.
///
/// This is a *different* permission from the Accessibility one the scroll
/// module needs, and macOS lists them separately. `CGEventTap` asks for
/// Accessibility; reading HID input directly — which is what
/// `MultitouchSupport` does underneath — asks for Input Monitoring
/// (`kTCCServiceListenEvent`). An app can hold either without the other, so
/// edge controls check for their own rather than assuming the scroll module
/// already cleared the way.
///
/// `IOHIDCheckAccess` and `IOHIDRequestAccess` are public API (macOS 10.15+),
/// unlike the framework they are guarding here.
enum InputMonitoringAuthorization {

    enum Status: Equatable {
        case granted
        case denied
        /// macOS has not been asked yet. Reads are usually allowed in this
        /// state, and the first attempt is what triggers the system prompt.
        case undetermined
    }

    static var status: Status {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .undetermined
        }
    }

    /// Whether it is worth trying to read touches. `undetermined` counts as
    /// worth trying: that is the state a freshly installed app is in, and the
    /// attempt is what makes macOS show its prompt.
    static var isPermitted: Bool {
        status != .denied
    }

    /// Shows the system prompt, if macOS has not already made up its mind.
    @discardableResult
    static func request() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Opens System Settings on Privacy & Security → Input Monitoring.
    static func openSystemSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
