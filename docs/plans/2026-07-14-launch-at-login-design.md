# Launch at Login — Design

Add a setting that controls whether Kivodo launches automatically when the
user logs in.

## Goal

A "Startup" toggle in Settings labelled "Launch at login". On a fresh install
the app registers itself as a login item (opt-out default); the user can turn
it off from Settings. The toggle always reflects macOS's real login-item state,
not just a stored bool.

## Mechanism

`SMAppService.mainApp` from the ServiceManagement framework (macOS 13+, and the
app targets 14.0). It registers the `.app` bundle itself as a login item — no
helper target, no `Info.plist` changes. For an `LSUIElement` menu bar app it
launches hidden at login, which is what we want.

Three calls matter:
- `register()` — throws; enables the login item.
- `unregister()` — throws; disables it.
- `.status` — reports macOS's actual view: `.enabled`, `.notRegistered`,
  `.requiresApproval` (login items disabled in System Settings or by policy).

## Components

### `LoginItem` controller — `Sources/Kivodo/LoginItem.swift`

`@MainActor @Observable final class LoginItem`. The single place that
reconciles the UI with the real OS state.

- `var isEnabled: Bool` — a computed toggle target. The getter derives from
  `SMAppService.mainApp.status == .enabled`. The setter calls `register()` /
  `unregister()`, catching errors, then re-reads status so the UI never claims
  a state macOS didn't accept.
- `var requiresApproval: Bool` — `status == .requiresApproval`, so the UI can
  point the user to System Settings when login items are blocked.
- `func registerOnFirstLaunch()` — reads a `@AppStorage`-equivalent flag
  (`UserDefaults` key `launchAtLoginConfigured`). If unset, calls `register()`
  and sets the flag. Idempotent across launches.

### First-launch registration — `KivodoApp.AppDelegate`

In `applicationDidFinishLaunching`, call `loginItem.registerOnFirstLaunch()`.
A fresh install genuinely becomes a login item; thereafter the toggle reflects
true `.status`. The delegate owns the `LoginItem` instance and hands it to the
Settings scene, mirroring how `reminderStore` is shared today.

### UI — `SettingsView`

A new "Startup" `SettingsSection` appended after Destinations, built from the
existing `SettingsSection` / `SettingsRow` / `RowDivider` blocks. One row: a
`Toggle` bound to `loginItem.isEnabled`, labelled "Launch at login". When
`requiresApproval` is true, the section caption explains login items are turned
off in System Settings and offers an "Open Settings" affordance (same pattern
as the Reminders-access fallback).

## Edge cases

- **`.requiresApproval`** — surface it in the caption; don't silently show the
  toggle as on. The setter's status re-read keeps the toggle honest.
- **Unsigned / non-bundled runs** — `register()` throws for a loose binary
  (`swift run`). Errors are caught and the toggle reflects the failed state; a
  real signed `make app` build works.
- **State drift** — the getter reads live `.status` every access, so if macOS
  drops the registration the toggle updates on next Settings open.

## Testing

`LoginItem`'s logic is thin and wraps a system singleton that needs a signed
bundle, so it's exercised manually via `make app && make run` rather than unit
tested: verify first-launch registration (check System Settings > General >
Login Items), toggling off/on, and that the toggle reflects an externally
changed state. The existing `swift test` suite (`CaptureViewModelTests`) stays
green.
