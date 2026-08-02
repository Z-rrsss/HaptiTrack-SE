import AppKit
import Combine
import OSLog

/// Wires the three pieces of module 1 together: the event tap that sees the
/// scrolling, the detent engine that decides when a notch is due, and the
/// haptic engine that makes it felt.
///
/// It also owns the lifecycle around them — settings changes, the Accessibility
/// permission, and recovering once the permission is granted.
@MainActor
final class ScrollHapticsController: ObservableObject {

    enum Status: Equatable {
        case stopped
        case running
        case waitingForPermission
        case failed(String)

        var isRunning: Bool { self == .running }
    }

    @Published private(set) var status: Status = .stopped

    private let settings: SettingsStore
    private let haptics: HapticEngine
    private let detents: ScrollDetentEngine

    private var eventTap: ScrollEventTap?
    private var permissionTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private let logger = Logger(subsystem: AppInfo.subsystem, category: "ScrollHaptics")

    /// How often to re-check the Accessibility permission while waiting for the
    /// user to grant it in System Settings. There is no notification for this.
    private static let permissionPollInterval: TimeInterval = 1.5

    init(settings: SettingsStore, haptics: HapticEngine = SystemHapticEngine()) {
        self.settings = settings
        self.haptics = haptics
        self.detents = ScrollDetentEngine(configuration: settings.detentConfiguration)

        // `objectWillChange` fires just *before* a property changes, so the hop
        // through the run loop is what makes the settings read below see the
        // new values.
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Brings the module in line with the current preferences. Safe to call at
    /// any time, and idempotent.
    func applySettings() {
        detents.configuration = settings.detentConfiguration

        if settings.isScrollHapticsEnabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard eventTap == nil else { return }

        guard AccessibilityAuthorization.isTrusted else {
            status = .waitingForPermission
            startPermissionPolling()
            return
        }

        let tap = ScrollEventTap { [weak self] sample in
            // The tap runs on the main run loop, so this callback is already on
            // the main thread; the compiler just has no way to know it.
            MainActor.assumeIsolated {
                self?.process(sample)
            }
        }

        do {
            try tap.start()
            eventTap = tap
            detents.reset()
            haptics.prepare()
            stopPermissionPolling()
            status = .running
            logger.info("Scroll haptics running.")
        } catch {
            status = .failed(error.localizedDescription)
            logger.error("Could not start scroll haptics: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        stopPermissionPolling()
        guard eventTap != nil else {
            status = .stopped
            return
        }
        eventTap?.stop()
        eventTap = nil
        detents.reset()
        haptics.teardown()
        status = .stopped
        logger.info("Scroll haptics stopped.")
    }

    /// Fires one pulse at the configured intensity, for the "Test" button in
    /// Settings. Works even while the module is off, so the user can audition
    /// intensities before switching it on.
    func firePreviewPulse() {
        haptics.perform(settings.intensity)
    }

    // MARK: - Event processing

    private func process(_ sample: ScrollEventTap.Sample) {
        guard settings.isScrollHapticsEnabled else { return }
        guard sample.isContinuous || settings.respondsToMouseWheel else { return }

        if sample.phase == .momentum, !settings.isMomentumHapticsEnabled {
            // Treat coasting as the end of the gesture: drop the accumulated
            // distance so it cannot pay out once the next gesture starts.
            detents.reset()
            return
        }

        let outcome = detents.consume(
            delta: sample.delta,
            timestamp: sample.timestamp,
            phase: sample.phase
        )
        guard outcome.count > 0 else { return }

        // A single event can pay for more than one notch, but two pulses fired
        // in the same run loop pass are indistinguishable by touch, so the
        // extra ones only serve to keep the accumulator honest.
        let intensity = outcome.isAttenuated ? settings.intensity.attenuated : settings.intensity
        haptics.perform(intensity)
    }

    // MARK: - Permission

    private func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        logger.notice("Waiting for the Accessibility permission.")

        let timer = Timer.scheduledTimer(
            withTimeInterval: Self.permissionPollInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AccessibilityAuthorization.isTrusted else { return }
                self.stopPermissionPolling()
                self.start()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
}
