import Foundation
import ObjectiveC.runtime
import OSLog

/// Night Shift: how warm the screen is, from untinted to as orange as macOS
/// will make it.
///
/// ⚠️ **Private API.** There is no public interface to Night Shift. The pane in
/// System Settings talks to `CBBlueLightClient`, a private Objective-C class in
/// `CoreBrightness.framework`, and so does this — the same framework
/// `KeyboardBacklightControl` uses for the backlight.
///
/// The class is reached by name through the Objective-C runtime and bridged to
/// an `@objc` protocol that declares only the four methods used here. The
/// selectors have to match the real ones exactly — Swift derives
/// `setStrength:commit:` from `setStrength(_:commit:)` — but nothing checks
/// that at compile time, so the whole surface is guarded by `NSClassFromString`
/// returning `nil` and by `respondsToSelector`.
///
/// **Verified on macOS 26.5**: the class resolves, `+supportsBlueLightReduction`
/// answers, `getStrength:` returned a live value, and `getBlueLightStatus:`
/// filled a struct whose bytes match the layout below field for field.
///
/// Sweeping an edge does not just move a number: Night Shift only tints while
/// it is switched on, so passing zero turns it on and returning to zero turns
/// it off. Without that, an edge assigned to this would appear to do nothing
/// until the user went and enabled Night Shift by hand.
final class NightShiftControl: AdjustableControl {

    /// The subset of `CBBlueLightClient` this control uses.
    @objc private protocol BlueLightClient {
        func setStrength(_ strength: Float, commit: Bool) -> Bool
        func getStrength(_ strength: UnsafeMutablePointer<Float>) -> Bool
        func setEnabled(_ enabled: Bool) -> Bool
        func getBlueLightStatus(_ status: UnsafeMutableRawPointer) -> Bool
    }

    /// `getBlueLightStatus:` fills a struct with no public header. Its
    /// Objective-C type encoding, read off the running class, is
    /// `{?=BBBi{?={?=ii}{?=ii}}QB}`:
    ///
    ///     +0   BOOL    active                  ← used
    ///     +1   BOOL    enabled
    ///     +2   BOOL    sunSchedulePermitted
    ///     +4   int32   mode
    ///     +8   struct  schedule, two hh:mm pairs
    ///     +24  uint64  disableFlags
    ///     +32  BOOL    available
    ///     ---  40 bytes
    ///
    /// Dumped from a real call on macOS 26.5, which came back
    /// `01 01 01 00 | 00000000 | 16000000 00000000 07000000 00000000 | …` —
    /// Night Shift on, mode 0, schedule 22:00 to 07:00 — matching the layout
    /// exactly. Only the first byte is ever read, and it sits at offset zero of
    /// a struct that starts with three `BOOL`s, which is the one field a layout
    /// change could hardly move. The buffer is larger than the struct so that
    /// growing it cannot overflow anything.
    private enum StatusLayout {
        static let bufferSize = 64
        static let active = 0
    }

    private let logger = Logger(subsystem: AppInfo.subsystem, category: "NightShiftControl")
    private let client: BlueLightClient?

    /// Whether the running class still answers `getBlueLightStatus:`. Without
    /// it the control cannot tell an untinted screen from a switched-off one,
    /// and falls back to reporting the stored strength.
    private let canReadStatus: Bool

    /// Whether this Mac can reduce blue light at all, asked of the class itself
    /// rather than guessed from the model identifier.
    private let isReductionSupported: Bool

    let identifier: ControlIdentifier = .nightShift
    let displayName = "Night Shift"

    /// Night Shift's strength is continuous rather than notched, so this is a
    /// choice about feel rather than a property of the system: twelve steps
    /// across the range is fine enough to be smooth and coarse enough that each
    /// tick is a tick.
    let quantum: Double = 1.0 / 12.0

    init() {
        guard let clientClass = NSClassFromString("CBBlueLightClient") as? NSObject.Type else {
            logger.error("CBBlueLightClient is missing on this macOS release.")
            client = nil
            canReadStatus = false
            isReductionSupported = false
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
            canReadStatus = false
            isReductionSupported = false
            return
        }

        canReadStatus = instance.responds(to: NSSelectorFromString("getBlueLightStatus:"))
        isReductionSupported = Self.supportsBlueLightReduction(clientClass)

        // Safe only because `BlueLightClient` is an `@objc` protocol: its
        // existential is a bare object pointer, so this is a reinterpretation
        // of the same pointer rather than a layout change.
        client = unsafeBitCast(instance, to: BlueLightClient.self)
    }

    /// `+[CBBlueLightClient supportsBlueLightReduction]`, called through its
    /// implementation pointer rather than `perform(_:)`: the method returns a
    /// `BOOL`, and reading a `BOOL` back out of `perform`'s object-typed return
    /// is the kind of thing that works right up until it does not.
    private static func supportsBlueLightReduction(_ clientClass: AnyClass) -> Bool {
        typealias Supports = @convention(c) (AnyClass, Selector) -> Bool
        let selector = NSSelectorFromString("supportsBlueLightReduction")

        guard let method = class_getClassMethod(clientClass, selector) else {
            // Nothing to ask, so assume it works and let a failed write say
            // otherwise. Hiding the control on a Mac that can tint would be
            // the worse mistake of the two.
            return true
        }
        let implementation = unsafeBitCast(method_getImplementation(method), to: Supports.self)
        return implementation(clientClass, selector)
    }

    var isSupported: Bool { client != nil && isReductionSupported }

    var isAvailable: Bool { isSupported }

    var value: Double {
        get {
            guard let client else { return 0 }

            // An untinted screen reads as zero, whatever strength Night Shift
            // has on file from last time. Otherwise a sweep starting on a
            // normal-looking screen would pick up wherever the slider was left
            // and throw the display there on the first tick.
            guard isTinting else { return 0 }

            var strength: Float = 0
            guard client.getStrength(&strength) else { return 0 }
            return Double(strength).clamped(to: 0...1)
        }
        set {
            guard let client else { return }
            let clamped = newValue.clamped(to: 0...1)

            guard clamped > 0 else {
                _ = client.setStrength(0, commit: true)
                _ = client.setEnabled(false)
                return
            }

            // Strength first, switch second. Turning Night Shift on before
            // writing would tint the screen at whatever strength was left over
            // — often full orange — for however long it takes the next line to
            // run. The strength is written again after enabling, in case
            // setting it while switched off was ignored.
            _ = client.setStrength(Float(clamped), commit: true)
            if !isTinting {
                _ = client.setEnabled(true)
                _ = client.setStrength(Float(clamped), commit: true)
            }
        }
    }

    /// Whether the screen is warm right now.
    ///
    /// This reads `active` rather than `enabled`, and the difference matters:
    /// with a sunset-to-sunrise schedule Night Shift is *enabled* all day and
    /// only *active* after dark, so reporting a strength at noon would be
    /// reporting a tint that is not on the screen.
    private var isTinting: Bool {
        guard let client, canReadStatus else {
            // No way to ask, so assume the strength on file is the strength on
            // screen — the behaviour this control had before it could ask.
            return true
        }

        var buffer = [UInt8](repeating: 0, count: StatusLayout.bufferSize)
        let didRead = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return client.getBlueLightStatus(base)
        }
        guard didRead else { return true }
        return buffer[StatusLayout.active] != 0
    }
}
