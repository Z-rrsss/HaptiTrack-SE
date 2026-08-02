# HaptiTrack

**Satisfying haptic feedback for your Force Touch trackpad.**

HaptiTrack is a lightweight macOS menu bar utility that adds a physical "detent"
sensation to trackpad scrolling: every notch of scroll produces a crisp haptic
pulse, the way a well-machined scroll wheel or a camera dial feels in your hand.

> **Status: early development — scroll haptics and edge controls are in
> place; neither has been through a long shakedown on real hardware yet.**

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
   sensitivity control and speed adaptation. *(done)*
2. **Edge controls** — slide along an edge of the trackpad to drive volume,
   brightness, the keyboard backlight, the microphone gain or Night Shift, with a
   haptic tick per step. Each of the four edges is configured separately, and
   the settings panel draws the trackpad to scale with the edge being
   configured lit up. *(done)*
3. **System-wide haptic feedback** — additional user-configurable haptic cues.

Audible "click" sounds are intentionally out of scope for the scroll and edge
haptics; the only sound the app makes is the click that punctuates the launch
flourish, twice, once per process.

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

The two modules need two *different* permissions. macOS lists them separately
and an app can hold either without the other.

**Accessibility** — for scroll haptics. HaptiTrack observes scroll events
system-wide through a `CGEventTap`.

> System Settings → Privacy & Security → Accessibility → enable **HaptiTrack**

**Input Monitoring** — for edge controls. Knowing *where* a finger is on the
trackpad means reading raw multitouch data, which macOS gates behind
`kTCCServiceListenEvent` rather than Accessibility.

> System Settings → Privacy & Security → Input Monitoring → enable **HaptiTrack**

The app asks for each one when you first switch the matching module on, and
picks the work back up by itself once you grant it.

The event tap is *listen-only*: HaptiTrack never modifies, injects or records
events. Scroll deltas and finger positions are consumed in memory to decide
when to fire a pulse and are never stored or transmitted. The app makes no
network requests.

## The launch intro

Starting the app plays a flourish once per process: a purple vignette closing in
from the edges of the screen, the name in the middle, two pulses — each one a
haptic tick and a quiet click together — and gone in under two seconds. A menu
bar agent otherwise launches invisibly, and the one thing this app is about is
the thing a silent launch cannot show.

It is a borderless, non-activating overlay at screen saver level: it takes no
clicks, never becomes the key window, never pulls focus from what you were
doing, and closes itself. Turning on **Reduce Motion** in System Settings →
Accessibility → Display skips it entirely.

## A note on private API

Module 1 uses nothing but public API. Module 2 cannot: macOS exposes no public
way to read absolute finger positions, to set the brightness of a built-in
display, to change the Night Shift colour temperature, or to move the keyboard
backlight. HaptiTrack uses the same private frameworks every trackpad and
brightness utility on macOS relies on — `MultitouchSupport`,
`DisplayServices`/`CoreDisplay` and `CoreBrightness` (both `CBBlueLightClient`
for Night Shift and `KeyboardBrightnessClient` for the backlight).

This is a deliberate, documented trade-off rather than an accident:

- every use is commented at the point of use, with what was verified and how;
- everything is resolved at runtime with `dlopen`/`dlsym`, never linked, so a
  macOS release that renames or removes a symbol turns a feature off instead of
  stopping the app from launching;
- each one sits behind a protocol (`AdjustableControl`, `TrackpadTouchMonitor`)
  so replacing it later touches one file.

It also means HaptiTrack could never ship on the App Store, which is fine —
it is not headed there.

## Architecture

```
HaptiTrack/
  App/            AppDelegate, entry point, menu bar item, permission checks
  Core/           Shared pieces: the tick accumulator, private-framework loading
  Haptics/        HapticEngine protocol + NSHapticFeedbackManager backend
  Launch/         The intro overlay played once per process
  ScrollEngine/   CGEventTap plumbing, scroll-specific wiring
  EdgeControls/   Multitouch monitor, edge geometry, gesture engine
    Controls/     AdjustableControl protocol and its implementations
  Settings/       Preferences store and SwiftUI settings panel
  Resources/      Assets
```

Two seams carry most of the design:

**`TickAccumulator`** (in `Core/`) is the shared heart of both modules. It turns
a stream of movement deltas into discrete notches, widening the notch spacing
with speed so the tick *rate* stays bounded instead of blurring into a buzz.
The scroll module feeds it points of scroll; the edge module feeds it
millimetres of finger travel. Same code, same feel.

**`AdjustableControl`** is what makes an edge a knob rather than a volume
button. Anything that can express itself as a `0...1` value can be assigned to
an edge; the gesture code knows nothing about audio or displays.

**`isAvailable` and `isSupported`** are two different questions a control has to
answer. Availability moves with whatever is plugged in — an external display can
take brightness away and give it back — so an unavailable control stays in the
assignment picker with a note explaining itself. Support is a fact about the
Mac: a desktop will never grow a backlit keyboard, so that control is left out
of the picker entirely rather than offered and then explained away.

Haptic output likewise sits behind a `HapticEngine` protocol. The shipping
backend uses the public `NSHapticFeedbackManager` API; the protocol exists so an
alternative backend (for finer control over actuation intensity and timing) can
be added later without touching the rest of the app.

## Contributing

Issues and pull requests are welcome. Code, comments, commit messages and
documentation are in English.

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, ship it.
