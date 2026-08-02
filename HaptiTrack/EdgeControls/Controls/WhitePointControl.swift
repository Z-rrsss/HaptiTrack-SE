import Foundation
import OSLog

/// Display white point, driven through Night Shift's colour-temperature slider.
///
/// ⚠️ **Private API.** There is no public interface to the display white point.
/// The Night Shift pane in System Settings talks to `CBBlueLightClient`, a
/// private Objective-C class in `CoreBrightness.framework`, and so does this.
///
/// The class is reached by name through the Objective-C runtime and bridged to
/// an `@objc` protocol that declares only the three methods used here. The
/// selectors have to match the real ones exactly — Swift derives
/// `setStrength:commit:` from `setStrength(_:commit:)` — but nothing checks
/// that at compile time, so the whole surface is guarded by
/// `NSClassFromString` returning `nil` and by `respondsToSelector`.
///
/// Verified on macOS 26.5: the class resolves and `getStrength:` returned a
/// live value.
///
/// One deliberate side effect: Night Shift only tints the display while it is
/// switched on, so moving this control past zero turns Night Shift on and
/// returning to zero turns it off. Without that, the edge would appear to do
/// nothing until the user enabled Night Shift by hand.
final class WhitePointControl: AdjustableControl {

    /// The subset of `CBBlueLightClient` this control uses.
    @objc private protocol BlueLightClient {
        func setStrength(_ strength: Float, commit: Bool) -> Bool
        func getStrength(_ strength: UnsafeMutablePointer<Float>) -> Bool
        func setEnabled(_ enabled: Bool) -> Bool
    }

    private let logger = Logger(subsystem: AppInfo.subsystem, category: "WhitePointControl")
    private let client: BlueLightClient?

    let identifier: ControlIdentifier = .whitePoint
    let displayName = "White Point"

    /// Night Shift's strength is continuous rather than notched, so this is a
    /// choice about feel rather than a property of the system: twelve steps
    /// across the range is fine enough to be smooth and coarse enough that each
    /// tick is a tick.
    let quantum: Double = 1.0 / 12.0

    init() {
        guard let clientClass = NSClassFromString("CBBlueLightClient") as? NSObject.Type else {
            logger.error("CBBlueLightClient is missing on this macOS release.")
            client = nil
            return
        }

        let instance = clientClass.init()
        let required: [Selector] = [
            NSSelectorFromString("setStrength:commit:"),
            NSSelectorFromString("getStrength:"),
            NSSelectorFromString("setEnabled:"),
        ]
        guard required.allSatisfy(instance.responds(to:)) else {
            logger.error("CBBlueLightClient no longer answers the expected selectors.")
            client = nil
            return
        }

        // Safe only because `BlueLightClient` is an `@objc` protocol: its
        // existential is a bare object pointer, so this is a reinterpretation
        // of the same pointer rather than a layout change.
        client = unsafeBitCast(instance, to: BlueLightClient.self)
    }

    var isAvailable: Bool { client != nil }

    var value: Double {
        get {
            guard let client else { return 0 }
            var strength: Float = 0
            guard client.getStrength(&strength) else { return 0 }
            return Double(strength).clamped(to: 0...1)
        }
        set {
            guard let client else { return }
            let clamped = newValue.clamped(to: 0...1)

            // Enable before writing so the first tick of a sweep is visible.
            if clamped > 0 {
                _ = client.setEnabled(true)
            }
            _ = client.setStrength(Float(clamped), commit: true)
            if clamped <= 0 {
                _ = client.setEnabled(false)
            }
        }
    }
}
