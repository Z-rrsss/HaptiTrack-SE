import AppKit
import Combine

/// Creates and manages the menu bar item and its menu.
///
/// The menu is rebuilt every time it is about to open rather than mutated in
/// place, so it can never drift out of sync with the settings or the engine's
/// status.
@MainActor
final class StatusItemController: NSObject {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settings: SettingsStore
    private let scrollHaptics: ScrollHapticsController
    private let edgeControls: EdgeControlsController
    private let openSettings: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: SettingsStore,
        scrollHaptics: ScrollHapticsController,
        edgeControls: EdgeControlsController,
        openSettings: @escaping () -> Void
    ) {
        self.settings = settings
        self.scrollHaptics = scrollHaptics
        self.edgeControls = edgeControls
        self.openSettings = openSettings
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        updateButton()
        scrollHaptics.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)
    }

    // MARK: - Button

    private func updateButton() {
        guard let button = statusItem.button else { return }

        // Filled while ticking, outlined while off: readable at a glance in
        // both light and dark menu bars without needing colour.
        let symbol = scrollHaptics.status.isRunning ? "hand.tap.fill" : "hand.tap"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: AppInfo.name)
        image?.isTemplate = true
        button.image = image
        button.toolTip = tooltip
    }

    private var tooltip: String {
        switch scrollHaptics.status {
        case .running: return "\(AppInfo.name) — scroll haptics on"
        case .stopped: return "\(AppInfo.name) — scroll haptics off"
        case .waitingForPermission: return "\(AppInfo.name) — Accessibility permission required"
        case .failed(let message): return "\(AppInfo.name) — \(message)"
        }
    }

    // MARK: - Menu

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = item(
            title: "Scroll Haptics",
            action: #selector(toggleScrollHaptics),
            keyEquivalent: ""
        )
        toggle.state = settings.isScrollHapticsEnabled ? .on : .off
        menu.addItem(toggle)

        let edges = item(
            title: "Edge Controls",
            action: #selector(toggleEdgeControls),
            keyEquivalent: ""
        )
        edges.state = settings.areEdgeControlsEnabled ? .on : .off
        menu.addItem(edges)

        if case .waitingForPermission = edgeControls.status {
            menu.addItem(item(
                title: "Grant Input Monitoring Permission…",
                action: #selector(requestInputMonitoring),
                keyEquivalent: ""
            ))
        }

        if case .waitingForPermission = scrollHaptics.status {
            let permission = item(
                title: "Grant Accessibility Permission…",
                action: #selector(requestPermission),
                keyEquivalent: ""
            )
            menu.addItem(permission)
        }

        if case .failed(let message) = scrollHaptics.status {
            let failure = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            failure.isEnabled = false
            menu.addItem(failure)
        }

        menu.addItem(.separator())
        menu.addItem(item(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(item(title: "Quit \(AppInfo.name)", action: #selector(quit), keyEquivalent: "q"))
    }

    private func item(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func toggleScrollHaptics() {
        settings.isScrollHapticsEnabled.toggle()

        // Turning the module on for the first time is the natural moment to ask
        // for the permission it needs.
        if settings.isScrollHapticsEnabled, !AccessibilityAuthorization.isTrusted {
            AccessibilityAuthorization.requestIfNeeded()
        }
    }

    @objc private func toggleEdgeControls() {
        settings.areEdgeControlsEnabled.toggle()

        if settings.areEdgeControlsEnabled, !InputMonitoringAuthorization.isPermitted {
            InputMonitoringAuthorization.request()
        }
    }

    @objc private func requestInputMonitoring() {
        InputMonitoringAuthorization.request()
        InputMonitoringAuthorization.openSystemSettings()
    }

    @objc private func requestPermission() {
        AccessibilityAuthorization.requestIfNeeded()
        AccessibilityAuthorization.openSystemSettings()
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }
}
