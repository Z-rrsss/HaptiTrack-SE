import AppKit
import CoreGraphics

/// Per-display visual dimming for screens whose hardware brightness cannot be
/// changed. A non-interactive black panel sits above applications and below
/// HaptiTrack's HUD. It never receives clicks, key focus or drag events.
final class SoftwareDimmingController: SoftwareDimmingServicing {

    /// Leaving a small amount visible makes a zero setting recoverable even if
    /// the user stops the gesture at the bottom of the range.
    static let maximumOpacity: Double = 0.92

    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var brightness: [CGDirectDisplayID: Double] = [:]
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshScreens()
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        panels.values.forEach { $0.close() }
    }

    func isAvailable(for displayID: CGDirectDisplayID) -> Bool {
        DisplayTarget.screen(for: displayID) != nil
    }

    func readBrightness(for displayID: CGDirectDisplayID) -> Double {
        brightness[displayID] ?? 1
    }

    @discardableResult
    func writeBrightness(_ value: Double, for displayID: CGDirectDisplayID) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let screen = DisplayTarget.screen(for: displayID) else { return false }

        let clamped = value.clamped(to: 0...1)
        brightness[displayID] = clamped
        let opacity = Self.opacity(forBrightness: clamped)

        if opacity <= 0.0001 {
            clearDimming(for: displayID)
            return true
        }

        let panel = panels[displayID] ?? makePanel(for: screen)
        panels[displayID] = panel
        panel.setFrame(screen.frame, display: true)
        panel.alphaValue = opacity
        panel.orderFrontRegardless()
        return true
    }

    func clearDimming(for displayID: CGDirectDisplayID) {
        dispatchPrecondition(condition: .onQueue(.main))
        brightness[displayID] = nil
        panels.removeValue(forKey: displayID)?.close()
    }

    static func opacity(forBrightness brightness: Double) -> Double {
        (1 - brightness.clamped(to: 0...1)) * maximumOpacity
    }

    private func makePanel(for screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        panel.sharingType = .none
        return panel
    }

    private func refreshScreens() {
        dispatchPrecondition(condition: .onQueue(.main))
        let connected = Set(NSScreen.screens.compactMap(DisplayTarget.displayID(for:)))

        for displayID in Array(panels.keys) where !connected.contains(displayID) {
            panels.removeValue(forKey: displayID)?.close()
            brightness[displayID] = nil
        }

        for (displayID, panel) in panels {
            guard let screen = DisplayTarget.screen(for: displayID) else { continue }
            panel.setFrame(screen.frame, display: true)
        }
    }
}
