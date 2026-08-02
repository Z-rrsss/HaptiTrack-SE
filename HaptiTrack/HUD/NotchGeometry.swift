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

    /// A 14"/16" MacBook Pro notch, measured on this machine: a 1728 pt wide
    /// screen with 771 and 772 pt of menu bar either side leaves 185 pt, and
    /// the safe area is 32 pt deep.
    ///
    /// Used unchanged on hardware without a notch. An overlay that is a hair
    /// wider on the Mac mini would be a difference nobody asked for, and the
    /// shape reads as "system HUD" on both.
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
        // No safe area at the top means no camera housing to work around.
        guard safeAreaTop > 0 else {
            return NotchGeometry(size: standard, isPhysical: false)
        }

        guard let left = auxiliaryLeftWidth,
              let right = auxiliaryRightWidth,
              case let width = screenWidth - left - right,
              width > 0 else {
            // A safe area but no menu bar areas to measure against: the notch
            // is real and its depth is known, so only the width is borrowed.
            return NotchGeometry(size: CGSize(width: standard.width, height: safeAreaTop),
                                 isPhysical: true)
        }

        return NotchGeometry(size: CGSize(width: width, height: safeAreaTop), isPhysical: true)
    }

    /// Where a HUD `contentHeight` points tall sits, in screen coordinates.
    ///
    /// It hangs from the very top of the screen so that on a notched Mac its
    /// first 32 points are hidden behind the housing and the rest appears to
    /// grow out of it. Never narrower than the notch, or the shape would look
    /// pinched where it meets one.
    func hudFrame(in screenFrame: CGRect, width: Double, contentHeight: Double) -> CGRect {
        let width = max(width, size.width)
        let height = size.height + contentHeight

        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }
}
