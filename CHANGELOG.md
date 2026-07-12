# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/tarikd/kivodo/releases/tag/v0.1.0
