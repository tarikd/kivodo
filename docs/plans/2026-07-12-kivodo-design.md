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
| Stack | Native Swift / SwiftUI; one dependency: KeyboardShortcuts (recorder UI — see 2026-07-13 design) |
| Distribution | Personal use, locally signed, not App Store |

Deliberately deferred (easy to add later): natural-language dates,
launch-at-login toggle, viewing todos. (Configurable shortcut and the
two-list destination toggle added 2026-07-13.)

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
4. **Shortcut handling** — the KeyboardShortcuts package (Carbon-based,
   no Accessibility/Input Monitoring permissions needed) with a recorder
   field in Settings; default ⌥ Space. (Replaced the hand-rolled Carbon
   `HotKeyManager` on 2026-07-13.)
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

Swift package, no external dependencies. `make app` builds a release binary
and assembles `build/Kivodo.app` (see Makefile). Info.plist needs `LSUIElement`
and `NSRemindersFullAccessUsageDescription`. The app is unsandboxed and needs
no entitlements — outside the sandbox, TCC only requires the app bundle plus
the usage description. Local ad-hoc signing (`codesign --sign -`); the code
hash changes on every rebuild, so macOS may re-ask for Reminders permission.

## Testing

- Unit tests for `CaptureViewModel` against a mocked `ReminderStore`:
  save, empty-input, permission-denied, save-failure, and async-race paths.
  The thin `EventKitReminderStore` wrapper is verified manually.
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
- [ ] Re-granting permission and retrying without a relaunch saves successfully
- [ ] First-run permission dialog: panel stays visible behind the system prompt during the save (dismissal is suppressed while saving); after granting, confirmation shows and reminder is created
