import AppKit

/// Creates and manages the menu bar item and its menu.
final class StatusItemController: NSObject {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    override init() {
        super.init()
        configureButton()
        statusItem.menu = makeMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "hand.tap",
            accessibilityDescription: "HaptiTrack"
        )
        button.image?.isTemplate = true
        button.toolTip = "HaptiTrack"
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "HaptiTrack", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit HaptiTrack",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
