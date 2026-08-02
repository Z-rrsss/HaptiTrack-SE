import AppKit

// HaptiTrack is an LSUIElement agent: it lives in the menu bar, owns no windows
// at launch and never shows up in the Dock or the ⌘-Tab switcher.
//
// The entry point is spelled out here rather than through @main so the
// activation policy is set before the app finishes launching, which avoids a
// brief Dock icon flash on some macOS releases.
let application = NSApplication.shared
let delegate = AppDelegate()

application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
