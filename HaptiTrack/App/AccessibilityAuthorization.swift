import AppKit
import ApplicationServices

/// Thin wrapper around the Accessibility trust check that the scroll event tap
/// depends on.
enum AccessibilityAuthorization {

    /// Whether the app is currently allowed to observe input events.
    ///
    /// The value can change while the app is running — the user may grant or
    /// revoke it in System Settings at any moment — so it is read each time
    /// rather than cached.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks macOS to show its "wants permission to control this computer"
    /// alert, unless the permission has already been granted.
    ///
    /// macOS only shows the alert once per app bundle; afterwards the call is
    /// silent, which is why the UI also offers a direct link to the settings
    /// pane.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Opens System Settings directly on Privacy & Security → Accessibility.
    static func openSystemSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
