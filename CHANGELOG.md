# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.1] - 2026-07-14

### Added

- The landing page now has a favicon, taken from the app icon.

## [0.5.0] - 2026-07-14

### Added

- Releases now include a signed and notarized `Kivodo.dmg` next to the zip, so
  you can drag the app to Applications the usual way. Its download link stays
  the same across versions.
- A landing page at kivodo.dieo.uk. The download buttons there always grab the
  newest DMG.

## [0.4.0] - 2026-07-14

### Added

- A "Launch at login" setting, in a new Startup section in Settings. Kivodo
  registers itself as a login item so it starts when you log in. New installs
  start with it on; turn it off from Settings.

## [0.3.2] - 2026-07-14

### Added

- Screenshots of the capture panel in the README.

## [0.3.1] - 2026-07-14

### Fixed

- Opening Settings crashed the app. The release build used the wrong Swift
  build engine, which baked an absolute build-directory path into a
  dependency's resource lookup, so the shortcut recorder couldn't find its
  resources once the app was installed. The build now uses the engine that
  keeps those resources reachable inside the app bundle.

## [0.3.0] - 2026-07-13

### Added

- Automatic updates through Sparkle. Kivodo checks in the background, and a
  "Check for Updates…" menu bar item runs a check on demand.
- A GitHub Actions release pipeline: pull requests get a build check; a push to
  main builds, signs with a Developer ID cert, notarizes, publishes a release,
  and updates the Sparkle appcast that installed copies read.
- `scripts/build_app.sh` as one build path for local dev and CI. The
  `KIVODO_MAS` flag drops Sparkle for a future App Store build.

## [0.2.0] - 2026-07-13

### Added

- A keyboard-hint footer under the capture field, showing the Save, Cancel,
  and List keys.
- An app icon: a frosted-glass panel that looks like the capture window
  itself, generated from an SVG master with `make icon`.

### Changed

- Redesigned the capture panel: a taller container, a hairline divider above
  the new hint footer, an outline checkmark status glyph, and a rounded
  destination chip with a Tab hint for switching lists.
- The saved confirmation reads "Added to {list}" and collapses the panel back
  to one row.
- Rebuilt Settings in the grouped macOS System Settings style, with the
  shortcut and destination controls in inset cards.
- The menu bar Capture item now puts its shortcut on the trailing edge instead
  of packing everything into one line.
- The needs-permission panel got a two-line message and a filled accent Open
  Settings button.
- The capture panel now stays open when you switch Spaces or apps. It closes
  only on Escape, a click outside, the shortcut again, or a save. Before, any
  focus change (including a Space swipe) closed it.

## [0.1.0] - 2026-07-13

### Added

- Menu bar app with a global hotkey (⌥ Space by default) that opens a
  floating capture panel over any app, including full-screen ones. The
  frontmost app keeps focus while you type.
- Enter saves the typed todo to the default Apple Reminders list. Escape,
  clicking outside, or pressing the hotkey again dismisses the panel.
- Empty submissions shake the panel instead of creating blank reminders.
- Reminders permission flow with a System Settings deep link when access
  is denied.
- Configurable shortcut: a recorder field in Settings (⌘,) with a reset
  button and a hint about combos other apps already own. Built on the
  KeyboardShortcuts package, pinned to 2.4.x.
- Makefile packaging: `make app` assembles and signs a relocatable
  Kivodo.app, `make run` relaunches it, `make test` runs the suite.

[0.5.1]: https://github.com/tarikd/kivodo/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/tarikd/kivodo/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/tarikd/kivodo/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/tarikd/kivodo/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/tarikd/kivodo/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/tarikd/kivodo/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/tarikd/kivodo/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/tarikd/kivodo/releases/tag/v0.1.0
