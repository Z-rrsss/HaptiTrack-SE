import AppKit
import Combine
import OSLog

/// Lifecycle owner for module 2, mirroring `ScrollHapticsController`: it wires
/// the touch monitor to the gesture engine to the haptic engine, keeps them in
/// step with the settings, and handles the Input Monitoring permission.
@MainActor
final class EdgeControlsController: ObservableObject {

    enum Status: Equatable {
        case stopped
        case running
        case waitingForPermission
        case failed(String)

        var isRunning: Bool { self == .running }
    }

    @Published private(set) var status: Status = .stopped

    /// The trackpad's physical size, once one has been opened. The settings
    /// panel draws its diagram from this, so the rectangle on screen has the
    /// proportions of the trackpad in front of the user rather than of a
    /// generic one.
    @Published private(set) var surface: TrackpadSurfaceSize = .fallback

    private let settings: SettingsStore
    private let haptics: HapticEngine
    private let registry: ControlRegistry
    private let hud: ControlHUDController
    private let engine: EdgeGestureEngine

    private var monitor: TrackpadTouchMonitor?
    private var permissionTimer: Timer?
    private var previewTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private let logger = Logger(subsystem: AppInfo.subsystem, category: "EdgeControls")

    private static let permissionPollInterval: TimeInterval = 1.5

    /// Spacing of the ticks the "Test" button plays. Slow enough that each one
    /// is felt separately, quick enough to read as one gesture.
    private static let previewTickInterval: TimeInterval = 0.09
    private static let previewTickCount = 5

    init(
        settings: SettingsStore,
        haptics: HapticEngine = SystemHapticEngine(),
        registry: ControlRegistry = .shared,
        hud: ControlHUDController? = nil
    ) {
        // Built here rather than in a default argument: those are evaluated at
        // the call site, where the main actor cannot be assumed.
        let hud = hud ?? ControlHUDController()

        self.settings = settings
        self.haptics = haptics
        self.registry = registry
        self.hud = hud

        // The engine is deliberately given closures rather than the registry
        // and the haptic engine directly: that is the seam the tests replace.
        self.engine = EdgeGestureEngine(
            zones: settings.edgeZones,
            requiresTwoFingers: settings.requiresTwoFingersForEdgeControls,
            controlProvider: { [registry] identifier in registry.control(for: identifier) },
            onTick: { [haptics] intensity in haptics.perform(intensity) },
            // The engine runs on the main thread — the touch monitor hands its
            // frames over there — which is what makes reaching a main-actor
            // window controller from here sound.
            onAdjust: { adjustment in
                MainActor.assumeIsolated {
                    hud.show(ControlHUDPresentation(adjustment))
                }
            }
        )

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func applySettings() {
        engine.zones = settings.edgeZones
        engine.requiresTwoFingers = settings.requiresTwoFingersForEdgeControls

        if settings.areEdgeControlsEnabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard monitor == nil else { return }

        guard InputMonitoringAuthorization.isPermitted else {
            status = .waitingForPermission
            startPermissionPolling()
            return
        }

        let monitor = TrackpadTouchMonitor { [weak self] frame in
            self?.engine.consume(frame)
        }

        do {
            try monitor.start()
            self.monitor = monitor
            surface = monitor.surfaceSize
            engine.reset()
            haptics.prepare()
            stopPermissionPolling()
            status = .running
            logger.info("Edge controls running.")
        } catch {
            status = .failed(error.localizedDescription)
            logger.error("Could not start edge controls: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        stopPermissionPolling()
        stopPreview()
        hud.tearDown()
        guard monitor != nil else {
            status = .stopped
            return
        }
        monitor?.stop()
        monitor = nil
        engine.reset()
        haptics.teardown()
        status = .stopped
        logger.info("Edge controls stopped.")
    }

    /// Whether an edge's assigned control actually works on this machine, for
    /// the settings panel to warn about.
    func isControlAvailable(_ identifier: ControlIdentifier) -> Bool {
        registry.isAvailable(identifier)
    }

    /// What the settings panel may offer for an edge currently set to
    /// `current`, which is always included even if this Mac cannot drive it.
    func assignableControls(including current: ControlIdentifier) -> [ControlIdentifier] {
        registry.assignableControls(including: current)
    }

    // MARK: - Preview

    /// Plays the tick pattern an edge would produce, without touching the
    /// control it is assigned to. Auditioning the feel should never move the
    /// volume or dim the screen.
    func firePreviewTicks() {
        stopPreview()
        haptics.perform(settings.intensity)

        var remaining = Self.previewTickCount - 1
        let timer = Timer.scheduledTimer(
            withTimeInterval: Self.previewTickInterval,
            repeats: true
        ) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.haptics.perform(self.settings.intensity)
                remaining -= 1
                if remaining <= 0 { self.stopPreview() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        previewTimer = timer
    }

    private func stopPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
    }

    // MARK: - Permission

    private func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        logger.notice("Waiting for the Input Monitoring permission.")
        InputMonitoringAuthorization.request()

        let timer = Timer.scheduledTimer(
            withTimeInterval: Self.permissionPollInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, InputMonitoringAuthorization.isPermitted else { return }
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
