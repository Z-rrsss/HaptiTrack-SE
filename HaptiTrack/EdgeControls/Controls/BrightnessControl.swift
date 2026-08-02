import CoreGraphics
import Foundation
import OSLog

/// Built-in display backlight.
///
/// ⚠️ **Private API.** Apple ships no public way to set the brightness of an
/// internal display — `IODisplaySetFloatParameter` stopped working on Apple
/// silicon, and there has never been a documented replacement. This uses the
/// same two private entry points every brightness utility on macOS relies on:
///
///   - `DisplayServices.framework` — `DisplayServicesGetBrightness`,
///     `DisplayServicesSetBrightness`, `DisplayServicesCanChangeBrightness`.
///     This is the primary path; it is what the brightness keys drive.
///   - `CoreDisplay.framework` — `CoreDisplay_Display_GetUserBrightness` /
///     `SetUserBrightness`, used as a fallback.
///
/// Both are resolved with `dlopen`/`dlsym` rather than linked, so a macOS
/// release that removes or renames them degrades to "control unavailable"
/// instead of refusing to launch the app. That, plus `AdjustableControl` in
/// front, is what makes this replaceable: when it breaks, only this file has to
/// change.
///
/// Verified present on macOS 26.5 (`DisplayServicesGetBrightness` returned a
/// live value). `DisplayServicesBrightnessChanged`, which some older utilities
/// call to refresh the on-screen HUD, is *not* exported on this release, so
/// changing brightness this way updates the display without showing the HUD.
final class BrightnessControl: AdjustableControl {

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetUserBrightness = @convention(c) (CGDirectDisplayID) -> Double
    private typealias SetUserBrightness = @convention(c) (CGDirectDisplayID, Double) -> Int32

    private static let displayServicesPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    private static let coreDisplayPath =
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"

    private let logger = Logger(subsystem: AppInfo.subsystem, category: "BrightnessControl")

    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?
    private let canChangeBrightness: CanChangeBrightness?
    private let getUserBrightness: GetUserBrightness?
    private let setUserBrightness: SetUserBrightness?

    let identifier: ControlIdentifier = .brightness
    let displayName = "Brightness"

    /// Matches the sixteen steps the brightness keys move through.
    let quantum: Double = 1.0 / 16.0

    init() {
        let displayServices = PrivateFramework(path: Self.displayServicesPath)
        let coreDisplay = PrivateFramework(path: Self.coreDisplayPath)

        getBrightness = displayServices?.function("DisplayServicesGetBrightness")
        setBrightness = displayServices?.function("DisplayServicesSetBrightness")
        canChangeBrightness = displayServices?.function("DisplayServicesCanChangeBrightness")
        getUserBrightness = coreDisplay?.function("CoreDisplay_Display_GetUserBrightness")
        setUserBrightness = coreDisplay?.function("CoreDisplay_Display_SetUserBrightness")

        if setBrightness == nil && setUserBrightness == nil {
            logger.error("No usable brightness entry point on this macOS release.")
        }
    }

    /// The display an edge gesture drives. The main display is the one the menu
    /// bar is on, which is the one the user is looking at when they reach for
    /// the trackpad.
    private var display: CGDirectDisplayID { CGMainDisplayID() }

    var isAvailable: Bool {
        guard setBrightness != nil || setUserBrightness != nil else { return false }
        guard let canChangeBrightness else { return true }
        return canChangeBrightness(display)
    }

    var value: Double {
        get {
            if let getBrightness {
                var brightness: Float = 0
                if getBrightness(display, &brightness) == 0 {
                    return Double(brightness).clamped(to: 0...1)
                }
            }
            if let getUserBrightness {
                return getUserBrightness(display).clamped(to: 0...1)
            }
            return 0
        }
        set {
            let clamped = newValue.clamped(to: 0...1)
            if let setBrightness, setBrightness(display, Float(clamped)) == 0 {
                return
            }
            if let setUserBrightness {
                _ = setUserBrightness(display, clamped)
            }
        }
    }
}
