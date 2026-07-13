# Sparkle auto-updates + GitHub Actions CI/CD — Design

**Date:** 2026-07-13
**Status:** Validated with user

## What it is

Automatic updates and a release pipeline, modeled on the LocaRec project
(`tarikd/LocaRec`). Every push to `main` produces a signed, notarized
`Kivodo.app`, publishes it as a GitHub release, and updates a Sparkle appcast
so installed copies update themselves. Pull requests get an unsigned build
check.

## Decisions

- **Signing:** Developer ID + Apple notarization (hardened runtime, stapled).
  No Gatekeeper warnings; Sparkle can install updates unattended.
- **Appcast host:** the same `tarikd/kivodo` repo. `appcast.xml` is committed
  to `main` and served over `raw.githubusercontent.com`; update zips are
  attached to `kivodo` GitHub releases. This requires the repo to be **public**
  (Sparkle fetches over plain HTTPS with no auth).
- **Versioning:** marketing version from the top `## [X.Y.Z]` heading in
  `CHANGELOG.md`; `CFBundleVersion` from `github.run_number`. Respects the
  existing changelog-driven release discipline.
- **CI triggers:** `pull_request` (unsigned build check) + `push` to `main`
  (sign, notarize, release). Runner `macos-15` (target is macOS 14+).
- **Build path:** a new `scripts/build_app.sh` is the single source of truth;
  `make app` becomes a thin wrapper so local and CI build identically.
- **Sparkle version:** 2.9.4.

## The update loop, end to end

Push to `main` → CI builds + notarizes `Kivodo-X.Y.Z-<sha>.zip` →
`generate_appcast` signs it with the EdDSA private key and writes
`appcast.xml` → CI attaches the zip to a GitHub release and commits
`appcast.xml` to `main` → an installed Kivodo periodically fetches the
appcast, verifies the EdDSA signature against the baked-in public key, and
offers the update.

## Architecture changes

| Area | Change |
|---|---|
| `Package.swift` | `KIVODO_MAS` env gate (mirrors LocaRec): default build appends `sparkle-project/Sparkle` 2.9.4 to the `Kivodo` executable target; `KIVODO_MAS=1` drops Sparkle and adds `.define("MAS_BUILD")`. `KivodoCore` and tests stay dependency-free. |
| `Sources/Kivodo/AppUpdater.swift` (new) | `#if !MAS_BUILD` `@MainActor` wrapper over `SPUStandardUpdaterController(startingUpdater: true, ...)`; `checkForUpdates()` activates the app first (Kivodo is `LSUIElement`, so the update window needs `NSApp.activate(ignoringOtherApps:)`). |
| `KivodoApp.swift` | Start the updater in `applicationDidFinishLaunching` (`_ = AppUpdater.shared`); add a `#if !MAS_BUILD` "Check for Updates…" button to the `MenuBarExtra`. |
| `Support/Info.plist` | Add `SUFeedURL` (`raw.githubusercontent.com/tarikd/kivodo/main/appcast.xml`), `SUPublicEDKey`, `SUEnableAutomaticChecks`. |
| `scripts/build_app.sh` (new) | Build SPM product (`--build-system swiftbuild`), assemble bundle, inject version, embed `Sparkle.framework` + rpath, sign inside-out (Dev ID + hardened runtime in CI, ad-hoc locally). MAS guard strips `SU*` keys and skips Sparkle. |
| `Makefile` | `make app` → `CONFIGURATION=release scripts/build_app.sh`; `run`/`test`/`icon`/`clean` unchanged. |
| `.github/workflows/build.yml` (new) | The pipeline (below). |

## Workflow steps (`build.yml`)

Signing/notarize/release steps guarded by
`github.event_name == 'push' && github.ref == 'refs/heads/main'`.

1. Checkout (`fetch-depth: 0`).
2. Show toolchain.
3. `swift build` (PRs too — early breakage check).
4. Import Developer ID cert into a temp keychain *(main)*.
5. Derive version from `CHANGELOG.md` top heading + `run_number` *(main)*.
6. `scripts/build_app.sh` with version + `KIVODO_CODESIGN_IDENTITY` *(main)*.
7. Verify bundle (`plutil -lint`, `codesign --verify`).
8. Archive → `Kivodo-<version>-<sha>.zip` + `.sha256`.
9. Notarize + staple + `spctl --assess`; re-zip *(main)*.
10. Download Sparkle 2.9.4 tools; extract `generate_appcast` *(main)*.
11. `generate_appcast` with `--download-url-prefix` pointing at the release
    assets, `--embed-release-notes`, `--maximum-versions 1` *(main)*.
12. Upload build artifact (zip + checksum).
13. `gh release create` with zip, checksum, appcast.xml *(main)*.
14. Commit `appcast.xml` to `main` as `github-actions[bot]` *(main)*.

**Loop avoidance:** step 14 pushes to `main`; the push trigger uses
`paths-ignore: [appcast.xml]` so the appcast commit does not retrigger the
workflow.

## Keys & secrets

- **Sparkle EdDSA key pair** (one-time, generated locally with Sparkle's
  `generate_keys`): private key → `SPARKLE_PRIVATE_KEY` secret + Keychain
  backup; public key → `SUPublicEDKey` in Info.plist. Losing the private key
  permanently breaks updates for existing installs.
- **GitHub secrets:** `DEVELOPER_ID_CERTIFICATE_BASE64`,
  `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_BASE64`,
  `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_TEAM_ID`,
  `SPARKLE_PRIVATE_KEY`.

## Manual steps (owned by the user)

1. Flip `tarikd/kivodo` to public.
2. Add the 7 GitHub secrets (a checklist with exact commands is produced
   during implementation).
3. Confirm a Developer ID Application certificate and an App Store Connect
   API key (Developer role) exist.

## Testing

- `swift build` + `swift test` still pass (Sparkle touches only the
  executable target).
- `make app` produces a launchable `Kivodo.app` with `Sparkle.framework`
  embedded; `codesign --verify` clean; `plutil -lint` on the shipped plist.
- Launch → menu → "Check for Updates…" → Sparkle UI appears and reaches the
  feed.
- PR path (unsigned build) passes on the first CI run; the signed/notarized
  path succeeds once the repo is public and the secrets exist.

## Versioning

MINOR bump at the next push (new capability, backward-compatible).
