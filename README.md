# HaptiTrack SE

**Satisfying haptic feedback for your Force Touch trackpad.**

HaptiTrack SE is a lightweight macOS menu bar utility that adds a physical "detent"
sensation to trackpad scrolling: every notch of scroll produces a crisp haptic
pulse, the way a well-machined scroll wheel or a camera dial feels in your hand.

> **Status: 1.2.0.** This is an independent community edition based on
> [Andrea De Pasquale's HaptiTrack](https://github.com/andrea-depasquale/HaptiTrack),
> distributed under the same MIT license. It is not an official upstream
> release and is not affiliated with BetterDisplay.

## What SE adds

- **Pointer-targeted display brightness.** A brightness gesture controls the
  screen containing the pointer when the gesture begins; the target stays
  locked until both fingers lift, and the HUD appears on that screen.
- **Three-stage brightness control.** HaptiTrack SE tries macOS native
  brightness first, then DDC/CI hardware control on compatible external
  displays, then per-display software dimming when neither hardware path works.
- **Optional accidental-activation protection.** Enabled by default: exactly
  two fingers must begin inside the same edge strip. Disable it to restore the
  original one-finger edge gesture.

All original scroll haptics, edge assignments, haptic ticks and notch HUD
features remain available.

## Relationship to upstream

This repository preserves the original HaptiTrack copyright and commit history.
The upstream source and assets remain copyright Andrea De Pasquale and are
redistributed under the upstream MIT license; HaptiTrack SE's changes are
identified in [What SE adds](#what-se-adds) and [CHANGELOG.md](CHANGELOG.md).
The SE name denotes an unofficial community fork and does not imply endorsement
by the original author.

No BetterDisplay source code or assets are included. The Apple Silicon DDC/CI
transport was adapted from documented compatibility work in the MIT-licensed
[AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC) project; its
copyright and full license text are preserved in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Why this exists

Scrolling on a Mac trackpad is smooth, precise — and completely mute to the
touch. macOS already drives the Taptic Engine for alignment guides, Force Touch
clicks and slider notches, but never for scrolling.

There are excellent commercial apps that fill this gap. The upstream HaptiTrack exists
because the idea deserves a **free, open source, auditable** implementation: no
subscriptions, no telemetry, no closed binary asking for Accessibility access.
HaptiTrack SE preserves that goal while extending the MIT-licensed upstream
project. The DDC implementation has no dependency on BetterDisplay code.

## Roadmap

1. **Scroll haptics** — a configurable haptic pulse per scroll detent, with
   sensitivity control and speed adaptation. *(done)*
2. **Edge controls** — slide along an edge of the trackpad to drive volume,
   brightness, the keyboard backlight, the microphone gain or Night Shift, with a
   haptic tick per step. Each of the four edges is configured separately, and
   the settings panel draws the trackpad to scale with the edge being
   configured lit up. A HUD rolls down out of the notch while you swipe,
   showing what is moving and where it has got to. *(done)*
   Brightness follows the pointer across displays and automatically falls back
   from native control to DDC/CI and then software dimming. Optional
   accidental-activation protection requires two fingers to begin in the same
   edge strip; turning it off restores the original one-finger gesture. *(done)*
3. **System-wide haptic feedback** — additional user-configurable haptic cues.

Audible "click" sounds are intentionally out of scope for the scroll and edge
haptics; the only sound the app makes is the click that punctuates the launch
flourish, twice, once per process.

## Requirements

- macOS 14 (Sonoma) or later
- A Mac with a Force Touch trackpad (built-in trackpad on 2015+ notebooks, or a
  Magic Trackpad 2 or later)
- Release downloads contain a Universal binary for Apple silicon and Intel.
- Xcode 15 or later to build from source

### Display compatibility

- Built-in and Apple-controlled displays use macOS native brightness services.
- DDC/CI is currently implemented for Apple Silicon display connections,
  primarily USB-C and DisplayPort Alt Mode. The monitor must expose VCP `0x10`
  and may require DDC/CI to be enabled in its on-screen settings.
- Some HDMI ports, docks, KVMs, DisplayLink adapters and monitor firmware do not
  pass DDC traffic. These displays automatically use software dimming.
- Intel Macs currently use native control where available and software dimming
  otherwise; Intel DDC transport is not implemented yet.
- Software dimming is a click-through black overlay, not a hardware backlight
  change. It is limited to 92% opacity so the screen remains recoverable, and
  it disappears when HaptiTrack SE quits.

Do not run multiple DDC utilities against the same monitor at the same time;
their transactions can collide even though each app serialises its own writes.

## Installing

Download the latest `HaptiTrack-SE-*.dmg` and matching `.sha256` file from this
repository's Releases page, open the disk image, and drag **HaptiTrack SE** to
Applications. Then read the next section, because the first launch needs a
detour.

### This app is not signed by Apple

HaptiTrack SE is **not signed with an Apple Developer ID certificate and not
notarised**. Both require membership of the Apple Developer Program, which
has an annual fee. Community builds are published without that certificate.

The practical consequence is that macOS will refuse to open it the first time
and will imply it might be malware. macOS cannot tell "unsigned" from
"dangerous" — the check it runs is "did somebody pay Apple to vouch for this",
and the honest answer here is no.

What you get instead of Apple's word:

- **The whole source is in this repository.** Nothing is hidden in a binary.
- **You can build it yourself** and skip the download entirely — see
  [Building](#building). An app you compiled was never downloaded, so it
  carries no quarantine flag and none of the steps below apply to it.
- **A checksum**, below, so you can prove the download is byte for byte the
  file that was published.

### Opening it the first time

On **macOS 15 (Sequoia) and later**:

1. Double-click HaptiTrack SE in Applications. macOS shows a warning saying it
   could not verify that the app is free of malware. Click **Done** — that is
   the only button, and it does not mean anything went wrong.
2. Open **System Settings → Privacy & Security**, scroll to the bottom of the
   pane, and you will find a line reading **"HaptiTrack SE" was blocked to protect
   your Mac**. Click **Open Anyway**, then authenticate with your administrator
   password.
3. That is it — only the first launch needs this. Afterwards HaptiTrack SE opens
   like any other app.

On **macOS 14 (Sonoma)**, the shorter route still works: right-click the app in
Applications, choose **Open**, and confirm in the dialog.

HaptiTrack SE then asks for two system permissions of its own, one per module —
see [Permissions](#permissions).

### Verifying the download

```sh
shasum -a 256 -c HaptiTrack-SE-*.dmg.sha256
```

Worth being clear about what this proves and what it does not. A matching
checksum means the file arrived intact and is the one that was published — not
that its contents deserve your trust. Only reading the code can tell you that,
which is the point of the next section.

### Read the source — that is the actual guarantee

A signature from Apple would tell you an identity was verified and an automated
malware scan came back clean. It would not tell you what the app does. The
source does, and this one is small enough to read in an evening.

If you are checking whether it deserves the permissions it asks for, these are
the files that matter:

| What you might worry about | Where to look |
|---|---|
| What it does with your scroll events | `ScrollEngine/ScrollEventTap.swift` — the tap is listen-only, it never modifies, injects or records |
| What it does with finger positions | `EdgeControls/TrackpadTouchMonitor.swift` |
| What it changes on your system | `EdgeControls/Controls/` — one file per control, nothing else writes anything |
| Whether it phones home | Nothing anywhere imports `URLSession` or opens a socket. The app makes no network requests at all, and stores nothing beyond its own settings in `UserDefaults` |
| The private APIs it uses and why | [ARCHITECTURE.md](ARCHITECTURE.md#a-note-on-private-api), plus a comment at each point of use recording what was verified and how |

For how the app is put together internally — folder layout, the design of the
notch HUD and launch animation, and why it needs private frameworks at all —
see [ARCHITECTURE.md](ARCHITECTURE.md).

## Building

Clone the repository and build with Xcode:

```sh
git clone https://github.com/Z-rrsss/HaptiTrack-SE.git
cd HaptiTrack-SE
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
dependencies) rather than a Swift package, because HaptiTrack SE ships as an
`LSUIElement` app bundle — a menu bar agent with no Dock icon.

## Permissions

The two modules need two *different* permissions. macOS lists them separately
and an app can hold either without the other.

**Accessibility** — for scroll haptics. HaptiTrack SE observes scroll events
system-wide through a `CGEventTap`.

> System Settings → Privacy & Security → Accessibility → enable **HaptiTrack SE**

**Input Monitoring** — for edge controls. Knowing *where* a finger is on the
trackpad means reading raw multitouch data, which macOS gates behind
`kTCCServiceListenEvent` rather than Accessibility.

> System Settings → Privacy & Security → Input Monitoring → enable **HaptiTrack SE**

The app asks for each one when you first switch the matching module on, and
picks the work back up by itself once you grant it.

The event tap is *listen-only*: HaptiTrack SE never modifies, injects or records
events. Scroll deltas and finger positions are consumed in memory to decide
when to fire a pulse and are never stored or transmitted. The app makes no
network requests.

## Contributing

Issues and pull requests are welcome. Code, comments, commit messages and
documentation are in English. See [CONTRIBUTING.md](CONTRIBUTING.md) before
submitting a change and [ARCHITECTURE.md](ARCHITECTURE.md) for the internal
design.

## License

MIT — see [LICENSE](LICENSE). The original HaptiTrack copyright notice is
preserved. DDC research acknowledgements are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
