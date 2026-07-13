# Destination toggle — Design

**Date:** 2026-07-13
**Status:** Validated with user

## What it is

A small chip in the floating capture panel that shows which Reminders list
the todo will land in, toggling between two user-chosen lists. Press Tab or
click the chip to flip it; Enter saves to whichever list is shown.

## UX

- **Panel:** a capsule chip at the right end of the text field shows the
  active list's name. Tab or a click toggles it. Selection is remembered
  while the app runs; a fresh launch starts on list 1. With no lists
  configured there is no chip and saves go to the system default list
  (today's behavior).
- **Settings:** two dropdowns ("List 1", "List 2") under the shortcut
  recorder, populated live from EventKit. Selections are stored by stable
  calendar identifier (plus a cached title for the chip). Both must be set
  and different for the toggle to appear.
- **Errors:** a configured list that was deleted produces the inline error
  "That list no longer exists — pick it again in Settings." with typed text
  preserved. Shake and permission flows are unchanged.

## Architecture changes

| Area | Change |
|---|---|
| `KivodoCore/ReminderStore` | `ReminderList` value type (id + title); protocol becomes `save(title:to listID: String?)` (nil = default list) + `availableLists()`; new `ReminderError.listNotFound` |
| `KivodoCore/CaptureViewModel` | `destinations`, `selectedDestination`, `toggleDestination()`, `updateDestinations(_:)` (preserves selection by id); `submit()` passes the selected id; `reset()` keeps the selection |
| `EventKitReminderStore` | Calendar lookup by identifier; `availableLists()` maps `calendars(for: .reminder)` |
| `PanelController` | Re-reads the configured pair from UserDefaults on every `show()`, so Settings edits apply on the next open |
| `CaptureView` | The chip + Tab handling on the focused field |
| `SettingsView` | Two pickers fed by `availableLists()`; permission-denied state shows a hint + settings deep link |
| App layer | AppDelegate owns the shared `EventKitReminderStore`; UserDefaults keys `destinationList{1,2}{ID,Title}` |

## Testing

TDD on `CaptureViewModel`: toggle cycles / no-ops when unconfigured, submit
passes the selected list id, `updateDestinations` preserves selection by id
when possible, `listNotFound` keeps text with the right message, `reset()`
keeps the selection. `EventKitReminderStore` and the UI stay manually
verified:

- [ ] No lists configured: no chip, saves to default list
- [ ] Pick two lists in Settings: chip appears on next panel open
- [ ] Tab and click both flip the chip
- [ ] Enter saves to the list shown on the chip (check both)
- [ ] Selection survives closing/reopening the panel
- [ ] Delete a configured list in Reminders, save: inline error, text kept
- [ ] Same list in both pickers: no chip (treated as unconfigured)

## Versioning

MINOR bump (0.2.0) at the next push.
