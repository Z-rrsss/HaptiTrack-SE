import AppKit
import SwiftUI

/// Shows the level of whatever an edge gesture is driving, then gets out of the
/// way.
///
/// One overlay for all five controls. It is handed a name, an icon and a level
/// — never a control — so the sixth one to be added will not touch it.
///
/// The window is the same kind the launch intro uses: borderless,
/// non-activating, above everything, transparent to clicks. This is a system
/// OSD, and a volume HUD that could take a click or pull focus would be a bug
/// in every case where it made a difference.
/// Kept out of the controller so the initialiser can use it as a default
/// argument: default arguments are evaluated at the call site, where the main
/// actor cannot be assumed.
private enum HUDTiming {

    /// How long the HUD stays after the last change. Long enough to read a
    /// number that has stopped moving, short enough that letting go of the
    /// trackpad clears the screen.
    static let rest: TimeInterval = 0.9

    static let rollUp: TimeInterval = 0.2
}

@MainActor
final class ControlHUDController {

    /// Wide enough for "Keyboard Backlight" and a percentage without crowding
    /// them, and wider than any notch, so the shape never looks pinched where
    /// it meets one.
    private static let width: Double = 260

    private static let rollDown: Animation = .spring(response: 0.3, dampingFraction: 0.82)
    private static let rollUp: Animation = .easeIn(duration: 0.2)

    private let model = ControlHUDModel()
    private let restDuration: TimeInterval

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    /// Whether the overlay is on screen right now.
    var isVisible: Bool { panel?.isVisible ?? false }

    init(restDuration: TimeInterval = HUDTiming.rest) {
        self.restDuration = restDuration
    }

    /// Shows a level, or updates the one already showing.
    ///
    /// Called once per notch crossed, so this is the hot path of a gesture: the
    /// window is built once and kept, and everything after that is a property
    /// assignment.
    func show(_ presentation: ControlHUDPresentation) {
        let panel = panel ?? makePanel()
        self.panel = panel

        position(panel)
        model.presentation = presentation

        if !model.isExpanded {
            withAnimation(Self.rollDown) { model.isExpanded = true }
        }
        if !panel.isVisible {
            // Not `makeKeyAndOrderFront`: the HUD must never take focus from
            // whatever the user is actually working in.
            panel.orderFrontRegardless()
        }

        scheduleDismissal()
    }

    /// Rolls the HUD back up and takes the window down after it.
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        guard let panel, panel.isVisible else { return }

        withAnimation(Self.rollUp) { model.isExpanded = false }

        dismissTask = Task { [weak self] in
            guard await self?.sleep(HUDTiming.rollUp) == true else { return }
            self?.panel?.orderOut(nil)
            self?.dismissTask = nil
        }
    }

    /// Takes the overlay down at once, animation and all — for shutting the
    /// module off, where there is nothing left to narrate.
    func tearDown() {
        dismissTask?.cancel()
        dismissTask = nil
        model.isExpanded = false
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    // MARK: - Timing

    private func scheduleDismissal() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            guard let self, await sleep(restDuration) else { return }
            dismiss()
        }
    }

    private func sleep(_ duration: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            return true
        } catch {
            return false
        }
    }

    // MARK: - The window

    /// Puts the panel back under the notch of whichever screen is in front now.
    /// Recomputed on every show, because the answer changes when the user moves
    /// to an external display — where there is no notch, and the HUD falls back
    /// to the invented one.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }

        let notch = NotchGeometry.forScreen(screen)
        let frame = notch.hudFrame(
            in: screen.frame,
            width: Self.width,
            contentHeight: ControlHUDView.contentHeight
        )

        model.notchHeight = notch.size.height
        if panel.frame != frame {
            panel.setFrame(frame, display: false)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let hosting = NSHostingView(rootView: ControlHUDView(model: model))
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Above the menu bar and above full-screen apps, which is where the
        // system's own volume and brightness overlays live.
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        return panel
    }
}
