# Kivodo — Design

**Date:** 2026-07-12
**Status:** Validated with user

## What it is

A macOS menu bar utility for capturing todos into Apple Reminders. Press a
global hotkey from any app and a small floating panel appears over whatever
is on screen (the ChatGPT-macOS-style quick-entry box). Type a todo, hit
Enter, and it lands in the default Apple Reminders list. The panel vanishes
and focus returns to what you were doing.

Kivodo is capture-only. Viewing, editing, and completing reminders happens
in Apple Reminders (which also syncs them to iPhone/iPad via iCloud).

## User experience

- Lives in the menu bar only: no Dock icon, no main window. The menu offers
  Quit and shows the hotkey.
- **⌥ Space** toggles the panel: a frosted-glass rounded box, centered
  horizontally, about a third of the way down the screen, containing a
  single borderless text field ("Add a reminder…").
- The panel is *non-activating*: the frontmost app keeps visual focus while
  keystrokes go to Kivodo's field.
- **Enter** saves the reminder, flashes a brief confirmation (~0.3s), and
  dismisses. **Escape**, **clicking outside**, or **pressing the hotkey
  again** dismisses without saving.
- Empty input + Enter does nothing except a login-window-style shake.
- Works on every Space and over full-screen apps.

## Scope decisions

| Decision | Choice |
|---|---|
| Storage | Apple Reminders via EventKit (default list) |
| Input | Plain text only — no date parsing, no list picker |
| Stack | Native Swift / SwiftUI, zero third-party dependencies |
| Distribution | Personal use, locally signed, not App Store |

Deliberately deferred (easy to add later): natural-language dates, list
targeting, configurable hotkey UI, launch-at-login toggle, viewing todos.

## Architecture

Five small components:

1. **`KivodoApp`** — SwiftUI `MenuBarExtra` entry point. `LSUIElement = true`
   in Info.plist removes the Dock icon.
2. **`FloatingPanel`** — `NSPanel` subclass; the heart of the overlay trick:
   - `.nonactivatingPanel` style mask — receive keys without activating
   - `level = .floating` — floats above normal windows
   - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
   - `canBecomeKey` overridden to `true` so the text field gets keystrokes
   - dismisses itself on `resignKey` (click-outside handling for free)
3. **`CaptureView`** — SwiftUI content hosted in the panel:
   `NSVisualEffectView` blur + one `TextField`.
4. **`HotKeyManager`** — Carbon `RegisterEventHotKey`. Chosen because it
   requires no Accessibility/Input Monitoring permissions, unlike global
   NSEvent monitors.
5. **`RemindersService`** — EventKit. Requests Reminders access on first
   save; creates an `EKReminder` in the default list.

No database, no network. The only state is the hotkey registration.

## Error handling

| Failure | Behavior |
|---|---|
| Reminders permission denied | Panel shows "Kivodo needs Reminders access" + button deep-linking to Privacy & Security → Reminders |
| Empty input + Enter | Shake animation, panel stays open |
| Save fails (e.g. no default list) | Inline error, typed text preserved |

## Build

Plain Xcode project, no external dependencies. Build with `xcodebuild` or
⌘R. Info.plist needs `LSUIElement` and `NSRemindersFullAccessUsageDescription`;
entitlements need `com.apple.security.personal-information.reminders`
(plus App Sandbox). Local (ad-hoc/development) signing.

## Testing

- Unit tests for `RemindersService` against a protocol-mocked EventKit:
  permission granted / denied / save-failure paths.
- Panel behavior (non-activation, hotkey, focus return) is verified by hand:

### Manual test checklist

- [ ] Hotkey opens panel over a normal app; that app's window stays visually focused
- [ ] Typing goes into the panel; Enter creates the reminder in Reminders.app
- [ ] Panel dismisses after save; keystrokes go back to the original app
- [ ] Escape dismisses and discards text
- [ ] Click outside dismisses
- [ ] Hotkey toggles (second press closes)
- [ ] Works over a full-screen app and on a second Space
- [ ] Empty Enter: shake, no reminder created
- [ ] Permission-denied flow shows the settings link
