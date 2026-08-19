# Contributing to HaptiTrack SE

Issues and pull requests are welcome. Please keep changes focused and describe
the hardware and macOS version used for testing.

## Before opening an issue

- Search existing issues.
- For DDC problems, include the Mac model, macOS version, display model,
  connection type, dock or adapter, and whether DDC/CI is enabled in the
  display's on-screen menu.
- Do not include serial numbers, usernames or other private device details.
- Confirm the problem with other display-control utilities closed; concurrent
  DDC transactions can interfere with each other.

## Pull requests

1. Create a focused branch.
2. Add or update tests for behavior that can be tested without hardware.
3. Run:

   ```sh
   xcodebuild -project HaptiTrack.xcodeproj -scheme HaptiTrack test
   ```

4. Describe the change, compatibility impact and checks performed.

Code, comments, commits and documentation use English. Avoid adding telemetry,
network access or a private API without documenting why it is necessary and
how failure degrades safely.

## Hardware changes

Display and trackpad behavior varies by device. A hardware-specific change
should retain a safe fallback, avoid guessing between multiple anonymous
displays, and report the exact setup used for validation.

By contributing, you agree that your contribution is licensed under the MIT
license in `LICENSE`.
