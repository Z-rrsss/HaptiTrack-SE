# Changelog

All notable changes to HaptiTrack SE are documented here. Versions follow
[Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-08-19

### Added

- DDC/CI brightness control for compatible Apple Silicon external display
  connections.
- Per-display software dimming when native and DDC hardware control are both
  unavailable.
- Automatic brightness fallback order: native, DDC/CI, then software dimming.
- Unit coverage for DDC packets, display matching and fallback selection.

### Changed

- Renamed the community build and bundle to HaptiTrack SE.
- Brightness targets the display under the pointer and keeps that display
  locked for the full gesture.
- The brightness HUD follows the selected display.

## [1.1.0] - 2026-08-18

### Added

- Optional accidental-activation protection, enabled by default.
- Two-finger edge gestures with both contacts required to start in the same
  edge strip.

## [1.0.0] - 2026-08-04

- Initial upstream HaptiTrack release by Andrea De Pasquale.
