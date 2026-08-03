import AppKit

/// The notch at the top of the screen — or, on a Mac that has none, the same
/// shape invented so the HUD looks identical everywhere.
///
/// Nothing private is needed for this. `NSScreen.safeAreaInsets.top` is the
/// height macOS keeps clear for the camera housing, and the two auxiliary menu
/// bar areas are the strips of menu bar either side of it, so the notch is
/// exactly what is left of the screen width between them.
struct NotchGeometry: Equatable {

    /// The notch itself, in points.
    var size: CGSize

    /// Whether there is really a notch there, or this is the invented one.
    var isPhysical: Bool

    /// The shape to draw on a Mac that has no notch, taken from a 14"/16"
    /// MacBook Pro: a 1728 pt wide screen with 771 and 772 pt of menu bar
    /// either side leaves 185 pt, over a 32 pt safe area.
    ///
    /// This is **only** the fallback. A Mac with a notch is measured, never
    /// assumed: notches differ between models, and one machine's numbers drawn
    /// on another's screen is how the HUD ended up wider than the hole it was
    /// supposed to be growing out of.
    static let standard = CGSize(width: 185, height: 32)

    static func forScreen(_ screen: NSScreen?) -> NotchGeometry {
        guard let screen else { return NotchGeometry(size: standard, isPhysical: false) }

        return make(
            screenWidth: screen.frame.width,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea.map { Double($0.width) },
            auxiliaryRightWidth: screen.auxiliaryTopRightArea.map { Double($0.width) }
        )
    }

    /// The arithmetic on its own, so it can be checked against hardware that is
    /// not the machine the tests happen to run on.
    static func make(
        screenWidth: Double,
        safeAreaTop: Double,
        auxiliaryLeftWidth: Double?,
        auxiliaryRightWidth: Double?
    ) -> NotchGeometry {
        // A notch is a hole in the menu bar, so it takes all three numbers to
        // find one: a safe area to work around, and two strips of menu bar to
        // measure the gap between. Missing or empty strips mean there is no
        // hole — an external display, a desktop, a notebook made before 2021 —
        // and the drawn-on notch takes over.
        guard safeAreaTop > 0,
              let left = auxiliaryLeftWidth, left > 0,
              let right = auxiliaryRightWidth, right > 0 else {
            return NotchGeometry(size: standard, isPhysical: false)
        }

        let width = screenWidth - left - right
        guard width > 0 else {
            return NotchGeometry(size: standard, isPhysical: false)
        }

        return NotchGeometry(size: CGSize(width: width, height: safeAreaTop), isPhysical: true)
    }

    /// Where a HUD `contentHeight` points tall sits, in screen coordinates.
    ///
    /// Exactly as wide as the notch and hanging from the very top of the
    /// screen, so on a notched Mac its first rows are hidden behind the
    /// housing and the rest appears to grow out of it. Any wider and it stops
    /// looking like the notch and starts looking like a black bar laid over
    /// the menu bar.
    ///
    /// Centred on the screen rather than on the measured gap: the two menu bar
    /// strips came back 771 and 772 points on the machine this was written on,
    /// which puts the middle of the notch half a point from the middle of the
    /// screen.
    func hudFrame(in screenFrame: CGRect, contentHeight: Double) -> CGRect {
        let height = size.height + contentHeight

        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - height,
            width: size.width,
            height: height
        )
    }
}
