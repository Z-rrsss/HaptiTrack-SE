import CoreGraphics
import Foundation

/// What the HUD says: a name, a level, and an icon to put in front of them.
///
/// The HUD knows nothing about volume, backlights or colour temperature — one
/// overlay serves every control, and adding a sixth one will not touch it. This
/// is the whole of what gets passed across.
struct ControlHUDPresentation: Equatable {

    var title: String
    var symbolName: String
    var displayID: CGDirectDisplayID?

    /// Always `0...1`. Clamped here rather than trusted, because a control that
    /// reports something odd should make the bar sit at an end, not draw past
    /// the end of the HUD.
    private(set) var value: Double

    init(
        title: String,
        symbolName: String,
        value: Double,
        displayID: CGDirectDisplayID? = nil
    ) {
        self.title = title
        self.symbolName = symbolName
        self.displayID = displayID
        self.value = value.isFinite ? value.clamped(to: 0...1) : 0
    }

    init(_ adjustment: ControlAdjustment) {
        self.init(
            title: adjustment.displayName,
            symbolName: adjustment.identifier.symbolName,
            value: adjustment.value,
            displayID: adjustment.displayID
        )
    }

    /// The level as the user would say it. Whole percent: a HUD that flickered
    /// through decimal places would be reporting precision the controls do not
    /// have — most of them move in sixteenths.
    var percentageText: String {
        "\(Int((value * 100).rounded()))%"
    }
}
