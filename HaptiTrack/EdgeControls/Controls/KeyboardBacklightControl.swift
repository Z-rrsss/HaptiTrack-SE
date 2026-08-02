import Foundation
import OSLog

/// Keyboard backlight.
///
/// ⚠️ **Private API.** macOS exposes no public way to read or set the keyboard
/// backlight. The F5/F6 keys and the Keyboard pane in System Settings both go
/// through `KeyboardBrightnessClient`, a private Objective-C class in
/// `CoreBrightness.framework` — the same framework `WhitePointControl` already
/// uses for Night Shift — and so does this.
///
/// The alternative would be writing HID reports to the backlight element on the
/// keyboard's IOHIDDevice. That is no more supported and considerably more
/// fragile: it needs the right usage page for each generation of hardware, it
/// bypasses whatever else the system thinks it is doing with the backlight, and
/// it would be a second, entirely separate mechanism sitting next to the one
/// `BrightnessControl` already established. Following the existing pattern is
/// worth more here than avoiding one more private class.
///
/// The class is reached by name through the Objective-C runtime and bridged to
/// an `@objc` protocol declaring only the three methods used. Swift derives
/// `setBrightness:forKeyboard:` from `setBrightness(_:forKeyboard:)`, and
/// nothing checks that against the real selector at compile time, so the whole
/// surface is guarded by `NSClassFromString` and `respondsToSelector`.
///
/// **Verified on macOS 26.5** (Apple silicon, built-in keyboard): the class
/// resolves, `copyKeyboardBacklightIDs` returned one built-in keyboard,
/// `brightnessForKeyboard:` returned a live value, and writing that same value
/// straight back returned `true`.
///
/// One thing this deliberately leaves alone: `KeyboardBrightnessClient` can
/// also switch off the ambient auto-brightness that raises and lowers the
/// backlight by itself. Setting the level while that is on behaves exactly the
/// way the F5/F6 keys do — the value holds until the light sensor decides
/// otherwise — and quietly turning off a system-wide setting because the user
/// swiped an edge would be a much ruder thing to do than obeying it.
final class KeyboardBacklightControl: AdjustableControl {

    /// The subset of `KeyboardBrightnessClient` this control uses.
    @objc private protocol KeyboardBrightnessClient {
        /// Backlight-capable keyboards, as an array of `NSNumber` IDs. A Mac
        /// with no backlit keyboard reports none, which is what makes it
        /// possible to answer `isSupported` honestly instead of guessing from
        /// the model identifier.
        func copyKeyboardBacklightIDs() -> NSArray?
        func brightnessForKeyboard(_ keyboard: UInt64) -> Float
        func setBrightness(_ brightness: Float, forKeyboard keyboard: UInt64) -> Bool
        func isKeyboardBuiltIn(_ keyboard: UInt64) -> Bool
    }

    private let logger = Logger(subsystem: AppInfo.subsystem, category: "KeyboardBacklight")
    private let client: KeyboardBrightnessClient?

    let identifier: ControlIdentifier = .keyboardBacklight
    let displayName = "Keyboard Backlight"

    /// The backlight keys move in sixteenths, like the display brightness ones,
    /// so an edge sweep lands on the same notches F5 and F6 would.
    let quantum: Double = 1.0 / 16.0

    init() {
        guard let clientClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            logger.error("KeyboardBrightnessClient is missing on this macOS release.")
            client = nil
            return
        }

        let instance = clientClass.init()
        let required: [Selector] = [
            NSSelectorFromString("copyKeyboardBacklightIDs"),
            NSSelectorFromString("brightnessForKeyboard:"),
            NSSelectorFromString("setBrightness:forKeyboard:"),
        ]
        guard required.allSatisfy(instance.responds(to:)) else {
            logger.error("KeyboardBrightnessClient no longer answers the expected selectors.")
            client = nil
            return
        }

        // Safe only because `KeyboardBrightnessClient` is an `@objc` protocol:
        // its existential is a bare object pointer, so this reinterprets the
        // same pointer rather than changing any layout.
        client = unsafeBitCast(instance, to: KeyboardBrightnessClient.self)
    }

    /// Whether this Mac has a backlit keyboard at all.
    ///
    /// A Mac mini, or a notebook driving an external keyboard that has no
    /// backlight, reports no backlight-capable keyboards. The control is then
    /// left out of the assignment picker entirely rather than offered and then
    /// explained away.
    var isSupported: Bool { keyboard != nil }

    var isAvailable: Bool { keyboard != nil }

    var value: Double {
        get {
            guard let client, let keyboard else { return 0 }
            return Double(client.brightnessForKeyboard(keyboard)).clamped(to: 0...1)
        }
        set {
            guard let client, let keyboard else { return }
            let clamped = newValue.clamped(to: 0...1)
            if !client.setBrightness(Float(clamped), forKeyboard: keyboard) {
                logger.error("The keyboard backlight refused a new level.")
            }
        }
    }

    /// The keyboard an edge gesture drives: the built-in one if there is one,
    /// otherwise the first that reports a backlight.
    ///
    /// Resolved on every access rather than cached, because keyboards come and
    /// go — closing the lid, docking, swapping a Magic Keyboard for a plain one
    /// — and a cached ID would outlive the hardware it names.
    private var keyboard: UInt64? {
        guard let client,
              let identifiers = client.copyKeyboardBacklightIDs() as? [NSNumber],
              !identifiers.isEmpty else { return nil }

        let keyboards = identifiers.map(\.uint64Value)
        return keyboards.first(where: { client.isKeyboardBuiltIn($0) }) ?? keyboards.first
    }
}
