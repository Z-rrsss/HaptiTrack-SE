# Architecture

This document covers how HaptiTrack SE is put together internally: the code
layout, the design of the notch HUD and launch animation, and why the app
needs private frameworks at all. If you just want to install and use the app,
you don't need any of this — see the main [README](README.md) instead.

## Layout

```
HaptiTrack/
  App/            AppDelegate, entry point, menu bar item, permission checks
  Core/           Shared pieces: the tick accumulator, private-framework loading
  HUD/            The notch overlay that shows what an edge gesture is moving
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
answer. Availability moves with whatever is plugged in. Brightness remains
available because per-display software dimming is the final fallback;
hardware-dependent controls can still disappear. Support is a fact about the
Mac: a desktop will never grow a backlit keyboard, so that control is left out
of the picker entirely rather than offered and then explained away.

Brightness uses three replaceable backends. `BrightnessControl` locks the
display under the pointer for one gesture, tries macOS native control first,
then DDC/CI hardware control, and finally a click-through software dimming
panel. The same display identifier is passed to the HUD so feedback appears on
the screen being changed.

Haptic output likewise sits behind a `HapticEngine` protocol. The shipping
backend uses the public `NSHapticFeedbackManager` API; the protocol exists so an
alternative backend (for finer control over actuation intensity and timing) can
be added later without touching the rest of the app.

## The notch HUD

Swiping an edge rolls a small overlay down out of the notch — the name of what
you are moving, the level as a percentage, and a purple bar — which rolls back
up on its own about a second after you stop. None of the controls an edge drives
puts up a HUD of its own when it is changed this way, so without it a sweep
moves the world silently.

On a Mac with no notch the same shape appears in the same place, sized to a
14" MacBook Pro's notch, so the app looks the same on every machine. Detecting
the real one needs no private API: it is the width left between the two halves
of the menu bar, and the depth of the screen's top safe area.

Like the intro, it is a non-activating overlay that takes no clicks and never
becomes the key window.

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
backlight. HaptiTrack SE uses private macOS entry points in
`MultitouchSupport`, `DisplayServices`/`CoreDisplay` and `CoreBrightness`.
External DDC/CI on Apple Silicon uses the IOAV I²C transport exported by
CoreDisplay. Software dimming itself uses ordinary AppKit windows.

This is a deliberate, documented trade-off rather than an accident:

- every use is commented at the point of use, with what was verified and how;
- everything is resolved at runtime with `dlopen`/`dlsym`, never linked, so a
  macOS release that renames or removes a symbol turns a feature off instead of
  stopping the app from launching;
- each one sits behind a protocol (`AdjustableControl`, `TrackpadTouchMonitor`)
  so replacing it later touches one file.

It also means HaptiTrack SE could never ship on the App Store, which is fine —
it is not headed there.
