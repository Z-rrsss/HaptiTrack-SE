# HaptiTrack

**Satisfying haptic feedback for your Force Touch trackpad.**

HaptiTrack is a lightweight macOS menu bar utility that adds a physical "detent"
sensation to trackpad scrolling: every notch of scroll produces a crisp haptic
pulse, the way a well-machined scroll wheel or a camera dial feels in your hand.

> **Status: early development — the scroll haptics module is in progress.**

## Why this exists

Scrolling on a Mac trackpad is smooth, precise — and completely mute to the
touch. macOS already drives the Taptic Engine for alignment guides, Force Touch
clicks and slider notches, but never for scrolling.

There are excellent commercial apps that fill this gap. HaptiTrack exists
because the idea deserves a **free, open source, auditable** implementation: no
subscriptions, no telemetry, no closed binary asking for Accessibility access.
It is written from scratch and shares no code or assets with any other app.

## Roadmap

1. **Scroll haptics** — a configurable haptic pulse per scroll detent, with
   sensitivity control and speed adaptation. *(in progress)*
2. **Edge gestures** — volume and brightness control by swiping along the edges
   of the trackpad.
3. **System-wide haptic feedback** — additional user-configurable haptic cues.

Audible "click" sounds are intentionally out of scope for module 1; they may
arrive in a later module.

## Requirements

- macOS 14 (Sonoma) or later
- A Mac with a Force Touch trackpad (built-in trackpad on 2015+ notebooks, or a
  Magic Trackpad 2 or later)
- Xcode 15 or later to build from source

## Building

Clone the repository and build with Xcode:

```sh
git clone https://github.com/andrea-depasquale/HaptiTrack.git
cd HaptiTrack
open HaptiTrack.xcodeproj
```

Or from the command line:

```sh
# Build a Debug app bundle into ./build
xcodebuild -project HaptiTrack.xcodeproj -scheme HaptiTrack -configuration Debug \
           -derivedDataPath build build

# Run the unit tests (pure logic, no Accessibility permission required)
xcodebuild -project HaptiTrack.xcodeproj -scheme HaptiTrack test
```

The project is a plain Xcode project (AppKit + SwiftUI, no third-party
dependencies) rather than a Swift package, because HaptiTrack ships as an
`LSUIElement` app bundle — a menu bar agent with no Dock icon.

## Permissions

HaptiTrack observes scroll events system-wide through a `CGEventTap`, which
requires the **Accessibility** permission:

> System Settings → Privacy & Security → Accessibility → enable **HaptiTrack**

The event tap is *listen-only*: HaptiTrack never modifies, injects or records
events. Scroll deltas are consumed in memory to decide when to fire a haptic
pulse and are never stored or transmitted. The app makes no network requests.

## Architecture

```
HaptiTrack/
  App/            AppDelegate, entry point, menu bar item (NSStatusItem)
  Haptics/        HapticEngine protocol + NSHapticFeedbackManager backend
  ScrollEngine/   CGEventTap plumbing and the scroll detent state machine
  Settings/       Preferences store and SwiftUI settings panel
  Resources/      Assets
```

Haptic output sits behind a `HapticEngine` protocol. The shipping backend uses
the public `NSHapticFeedbackManager` API; the protocol exists so an alternative
backend (for finer control over actuation intensity and timing) can be added
later without touching the rest of the app.

## Contributing

Issues and pull requests are welcome. Code, comments, commit messages and
documentation are in English.

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, ship it.
