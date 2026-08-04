# HaptiTrack

**Satisfying haptic feedback for your Force Touch trackpad.**

HaptiTrack is a lightweight macOS menu bar utility that adds a physical "detent"
sensation to trackpad scrolling: every notch of scroll produces a crisp haptic
pulse, the way a well-machined scroll wheel or a camera dial feels in your hand.

> **Status: 1.0.0 — the first release.** Scroll haptics and edge controls are
> both complete and have been through a week of real use on the hardware they
> were built on. Wider hardware coverage is exactly what a first release is
> for; if something behaves oddly on yours, please open an issue.

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
   configured lit up. A HUD rolls down out of the notch while you swipe,
   showing what is moving and where it has got to. *(done)*
3. **System-wide haptic feedback** — additional user-configurable haptic cues.

Audible "click" sounds are intentionally out of scope for the scroll and edge
haptics; the only sound the app makes is the click that punctuates the launch
flourish, twice, once per process.

## Requirements

- macOS 14 (Sonoma) or later
- A Mac with a Force Touch trackpad (built-in trackpad on 2015+ notebooks, or a
  Magic Trackpad 2 or later)
- Xcode 15 or later to build from source

## Installing

Download `HaptiTrack-1.0.0.dmg`, open it, and drag HaptiTrack to Applications.
Then read the next section, because the first launch needs a detour.

### This app is not signed by Apple

HaptiTrack is **not signed with an Apple Developer ID certificate and not
notarised**. Both require membership of the Apple Developer Program, which
costs $99 a year. This is one person's open source project, given away for
free, and that is not a bill it can carry.

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

1. Double-click HaptiTrack in Applications. macOS shows a warning saying it
   could not verify that the app is free of malware. Click **Done** — that is
   the only button, and it does not mean anything went wrong.
2. Open **System Settings → Privacy & Security**, scroll to the bottom of the
   pane, and you will find a line reading **"HaptiTrack" was blocked to protect
   your Mac**. Click **Open Anyway**, then authenticate with your administrator
   password.
3. That is it — only the first launch needs this. Afterwards HaptiTrack opens
   like any other app.

On **macOS 14 (Sonoma)**, the shorter route still works: right-click the app in
Applications, choose **Open**, and confirm in the dialog.

HaptiTrack then asks for two system permissions of its own, one per module —
see [Permissions](#permissions).

### Verifying the download

```sh
shasum -a 256 HaptiTrack-1.0.0.dmg
```

It should print exactly:

```
d8e3b6cb7130586391e7df2d8447dec46b5c16f5f579c8a01f90ef3b6acab26a  HaptiTrack-1.0.0.dmg
```

Or, with `HaptiTrack-1.0.0.dmg.sha256` downloaded next to it:

```sh
shasum -a 256 -c HaptiTrack-1.0.0.dmg.sha256
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

## Contributing

Issues and pull requests are welcome. Code, comments, commit messages and
documentation are in English. See [ARCHITECTURE.md](ARCHITECTURE.md) for how
the codebase is organized before diving in.

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, ship it.
