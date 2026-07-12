# Configurable shortcut — Design

**Date:** 2026-07-13
**Status:** Validated with user

## What it is

Let the user change Kivodo's global capture shortcut (hardcoded ⌥ Space
until now) with a native recorder field: click, press any combo, done.
Motivation: ⌥ Space collides with the ChatGPT desktop app's default
shortcut.

## Approach

Use the `KeyboardShortcuts` package (sindresorhus, MIT, source-only SPM) —
the one sanctioned exception to the zero-dependencies rule. It provides the
SwiftUI `Recorder` control, international keyboard handling, system-conflict
warnings, UserDefaults persistence, and Carbon-based registration (still
permission-free). Alternatives considered: a preset submenu (rejected: user
wants free recording), a hand-rolled recorder (~200 lines, layout and
conflict edge cases — not worth it).

## Changes

| Area | Change |
|---|---|
| `Package.swift` | Add KeyboardShortcuts dependency to the **executable target only**; KivodoCore stays dependency-free |
| `HotKeyManager.swift` | Deleted — the package replaces it |
| `KivodoApp.swift` | Shortcut name `toggleCapture` (default ⌥ Space); `KeyboardShortcuts.onKeyDown` wiring; `Settings` scene; menu gains "Settings…" (⌘,) and the hotkey line reads the current shortcut dynamically |
| `SettingsView.swift` | New: `KeyboardShortcuts.Recorder` row, a hint that globally-owned combos can't be recorded, and a "Reset to ⌥ Space" button |
| Docs | Scope tables updated here and in the v1 design doc |

The settings window must actually come to the front when opened from the
menu (LSUIElement apps don't activate on their own — pair the open with
`NSApp.activate`).

## Testing

Nothing meaningfully unit-testable (system/UI behavior). Manual checks:

- [ ] Default is still ⌥ Space on first run (existing UserDefaults absent)
- [ ] Settings… opens the window in front; recorder records a new combo
- [ ] New shortcut toggles the panel; old one is dead immediately
- [ ] Choice survives relaunch
- [ ] Menu line shows the current shortcut
- [ ] Existing capture flow unchanged (Enter/Escape/click-outside/toggle)

## Versioning

MINOR bump (new backward-compatible feature) when this reaches a push.
