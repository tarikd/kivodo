# Kivodo

A macOS menu bar utility: press a global hotkey (⌥ Space) from any app and a
small floating panel appears over everything on screen. Type a todo, hit
Enter, and it lands in Apple Reminders. Capture-only — viewing and completing
happens in Reminders.

- **Stack:** native Swift/SwiftUI, zero third-party dependencies
- **Design doc:** `docs/plans/2026-07-12-kivodo-design.md`
- **Build:** Swift package — `make app` assembles and signs `build/Kivodo.app`; `make run` relaunches it; `make test` runs the suite

## ⚠️ CRITICAL: Git Rules (READ THIS FIRST)

**These rules are NON-NEGOTIABLE.**

### No AI Attribution

- **NEVER** include `Co-Authored-By: Claude` or any AI attribution in commits
- **NEVER** mention Claude, AI, or LLM assistance in commit messages, PR descriptions, or branch names
- All git artifacts must appear fully human-written

### Humanization Required

- **BEFORE** writing ANY commit message, PR description, or branch name: run the text through `/humanizer`
- **NEVER** push commits without humanizing the messages first
- This applies to ALL git operations, no exceptions

### Changelog Rules

- Maintain CHANGELOG.md at the project root
- **NEVER** use an "Unreleased" section. Every push cuts a new version.
- Before every push, add a new version heading at the top, `## [X.Y.Z] - YYYY-MM-DD`, with today's date, and list the changes under it (Added, Changed, Fixed, Removed).
- Bump the version with [Semantic Versioning](https://semver.org/), sized to how heavy the changes are:
  - **MAJOR** (`X`): breaking changes — incompatible behavior changes (e.g. hotkey or data-handling changes that break existing usage).
  - **MINOR** (`Y`): new features that are backward-compatible (new capabilities, settings, UI).
  - **PATCH** (`Z`): backward-compatible bug fixes and small tweaks only.
  - When changes span several levels, use the highest that applies.
- Add the matching link-reference definition at the bottom of the file, e.g. `[X.Y.Z]: https://github.com/<owner>/kivodo/compare/vPREV...vX.Y.Z` (use the repo's origin remote once one exists).
- **ALWAYS** run changelog entries through `/humanizer` before writing them.
- Follow [Keep a Changelog](https://keepachangelog.com/) format.

### Mandatory Pre-Push Checklist

1. ✅ Decide the new version number from the SemVer rules above
2. ✅ Add a new `## [X.Y.Z] - YYYY-MM-DD` section to CHANGELOG.md (humanized via `/humanizer`) and its link reference at the bottom — no "Unreleased"
3. ✅ Stage the changelog: `git add CHANGELOG.md`
4. ✅ Humanize all commit messages via `/humanizer`
5. ✅ Verify NO AI attribution anywhere in the commit
6. ✅ Commit and push
