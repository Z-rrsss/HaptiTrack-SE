import AppKit
import OSLog
import SwiftUI

/// Plays the intro once, when the process starts.
///
/// The overlay is a borderless, transparent, non-activating panel at screen
/// saver level: it draws over everything, takes no clicks, never becomes key
/// and never steals focus from whatever the user was doing. It closes itself
/// when the animation ends — there is nothing to dismiss because there is
/// nothing to interact with.
///
/// The controller owns the clock. Each pulse writes the scale bump, fires the
/// haptic and plays the click from the same place, which is the only way the
/// three read as one event rather than as three near-simultaneous ones.
@MainActor
final class LaunchAnimationController {

    private let timeline: LaunchAnimationTimeline
    private let haptics: HapticEngine
    private let sound: ClickSound
    private let intensity: HapticIntensity

    private let logger = Logger(subsystem: AppInfo.subsystem, category: "LaunchAnimation")

    private var panel: NSPanel?
    private var model: LaunchOverlayModel?
    private var task: Task<Void, Never>?

    var isPlaying: Bool { task != nil }

    init(
        timeline: LaunchAnimationTimeline = LaunchAnimationTimeline(),
        haptics: HapticEngine = SystemHapticEngine(),
        sound: ClickSound = ClickSound(),
        intensity: HapticIntensity = .strong
    ) {
        self.timeline = timeline
        self.haptics = haptics
        self.sound = sound
        self.intensity = intensity
    }

    /// Runs the intro, calling `completion` on the main actor once it is over.
    ///
    /// `completion` runs whether the animation played or was skipped, so the
    /// caller can hang the rest of its launch sequence off it without having to
    /// know which happened. The one exception is a call made while a run is
    /// already under way: that is ignored outright, completion and all, rather
    /// than queued behind it or allowed to put up a second overlay.
    func play(completion: @escaping () -> Void = {}) {
        guard !isPlaying else { return }

        guard let screen = NSScreen.main else {
            completion()
            return
        }

        // Someone who has asked the system to calm down does not want a pulsing
        // overlay thrown over their screen, and the haptic and the click are
        // part of the same flourish rather than information they would lose.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            logger.info("Skipping the launch intro: Reduce Motion is on.")
            completion()
            return
        }

        let model = LaunchOverlayModel()
        let panel = makePanel(on: screen, model: model)
        self.model = model
        self.panel = panel

        haptics.prepare()
        panel.orderFrontRegardless()

        task = Task { [timeline] in
            await run(timeline, model: model)
            finish()
            completion()
        }
    }

    /// Takes the overlay down early — at quit, say. Safe to call at any time.
    func cancel() {
        task?.cancel()
        task = nil
        finish()
    }

    // MARK: - The sequence

    private func run(_ timeline: LaunchAnimationTimeline, model: LaunchOverlayModel) async {
        withAnimation(.easeOut(duration: timeline.fadeIn)) {
            model.opacity = 1
            model.titleOpacity = LaunchOverlayModel.restingTitleOpacity
            model.titleScale = 1
        }

        var elapsed: TimeInterval = 0
        for time in timeline.pulseTimes {
            guard await sleep(time - elapsed) else { return }
            elapsed = time
            pulse(timeline, model: model)
        }

        guard await sleep(timeline.fadeOutStart - elapsed) else { return }

        withAnimation(.easeIn(duration: timeline.fadeOut)) {
            model.opacity = 0
            // Drifting very slightly larger on the way out reads as the name
            // receding rather than as the window being switched off.
            model.titleScale = 1.04
        }
        _ = await sleep(timeline.fadeOut)
    }

    /// One beat: felt, heard and seen at the same instant.
    private func pulse(_ timeline: LaunchAnimationTimeline, model: LaunchOverlayModel) {
        haptics.perform(intensity)
        sound.play()

        withAnimation(.easeOut(duration: timeline.pulseRise)) {
            model.titleScale = LaunchOverlayModel.pulsedTitleScale
            model.titleOpacity = 1
        }
        withAnimation(.easeInOut(duration: timeline.pulseFall).delay(timeline.pulseRise)) {
            model.titleScale = 1
            model.titleOpacity = LaunchOverlayModel.restingTitleOpacity
        }
    }

    /// Sleeps, reporting `false` if the intro was cancelled while waiting.
    private func sleep(_ duration: TimeInterval) async -> Bool {
        guard duration > 0 else { return !Task.isCancelled }
        do {
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            return true
        } catch {
            return false
        }
    }

    private func finish() {
        sound.stop()
        haptics.teardown()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        model = nil
        task = nil
    }

    // MARK: - The window

    private func makePanel(on screen: NSScreen, model: LaunchOverlayModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            // `.nonactivatingPanel` is what stops the overlay pulling the app
            // in front of whatever the user is working in — an agent app that
            // steals focus at launch is exactly the thing this app is not.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = NSHostingView(rootView: LaunchOverlayView(model: model))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // The fade is the animation's own; letting AppKit add one of its own on
        // top would double it up.
        panel.animationBehavior = .none
        panel.setFrame(screen.frame, display: false)
        return panel
    }
}
