import AppKit
import CoreGraphics

/// Resolves the display the pointer is currently on.
///
/// AppKit and Core Graphics use different display abstractions. Edge controls
/// need a `CGDirectDisplayID` for the private brightness APIs, while the HUD
/// needs the corresponding `NSScreen`. Keeping the conversion here gives both
/// callers the same answer and leaves the brightness control testable.
enum DisplayTarget {

    struct Geometry: Equatable {
        var id: CGDirectDisplayID
        var frame: CGRect
    }

    static func displayID(
        at point: CGPoint,
        in displays: [Geometry],
        fallback: CGDirectDisplayID
    ) -> CGDirectDisplayID {
        displays.first(where: { $0.frame.contains(point) })?.id ?? fallback
    }

    static func displayUnderPointer() -> CGDirectDisplayID {
        displayID(
            at: NSEvent.mouseLocation,
            in: NSScreen.screens.compactMap { screen in
                guard let id = displayID(for: screen) else { return nil }
                return Geometry(id: id, frame: screen.frame)
            },
            fallback: CGMainDisplayID()
        )
    }

    static func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first(where: { self.displayID(for: $0) == displayID })
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }
}
