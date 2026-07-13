# Sparkle auto-updates + CI/CD Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire Sparkle auto-updates into Kivodo and add a GitHub Actions pipeline that builds on PRs and cuts signed, notarized releases (with a Sparkle appcast) on pushes to `main`.

**Architecture:** Sparkle is added to the `Kivodo` executable target behind a `KIVODO_MAS` env gate (mirrors LocaRec). A new `scripts/build_app.sh` becomes the single build path for local + CI, assembling the `.app`, embedding `Sparkle.framework`, and signing (ad-hoc locally, Developer ID + hardened runtime in CI). A `.github/workflows/build.yml` builds, notarizes, generates the appcast with `generate_appcast`, publishes a GitHub release, and commits `appcast.xml` to `main`. The appcast is served over `raw.githubusercontent.com` from the (now public) `tarikd/kivodo` repo.

**Tech Stack:** Swift Package Manager (swiftbuild engine), Sparkle 2.9.4, GitHub Actions (`macos-15`), `xcrun notarytool`/`stapler`, `codesign`, `gh` CLI.

**Design doc:** `docs/plans/2026-07-13-sparkle-cicd-design.md`

**Working context:** Implementing on `main`. Unrelated uncommitted changes already exist in the tree (README.md, Assets/, Swift files, Makefile, Info.plist, CHANGELOG.md). Keep each commit scoped to only the Sparkle/CI-CD files listed per task.

---

## Task 0: Generate the Sparkle EdDSA key pair (one-time)

**Files:** none committed. Produces a private key (→ GitHub secret + Keychain) and a public key (→ Info.plist in Task 3).

**Step 1: Download Sparkle 2.9.4 and extract the tools**

Run:
```bash
cd "$(mktemp -d)"
gh release download 2.9.4 --repo sparkle-project/Sparkle --pattern 'Sparkle-2.9.4.tar.xz'
tar -xf Sparkle-2.9.4.tar.xz
ls bin/
```
Expected: `bin/` contains `generate_keys`, `generate_appcast`, `sign_update`.

**Step 2: Generate the key pair into the login Keychain**

Run: `./bin/generate_keys`
Expected output includes a line: `A key has been generated and saved in your keychain.` and prints the **public key** (base64, ~44 chars). Record the public key — it goes into Info.plist (Task 3).

**Step 3: Export the private key for the GitHub secret**

Run: `./bin/generate_keys -x /tmp/sparkle_private_key.txt`
Expected: writes the private key (base64) to that file. This is the value for the `SPARKLE_PRIVATE_KEY` GitHub secret.

**Step 4: Record both keys for the user (do not commit)**

Print the public key and the path to the private key file. Instruct the user to:
- Add `SPARKLE_PRIVATE_KEY` as a repo secret with the file's contents.
- Keep the Keychain entry as the durable backup (losing it permanently breaks updates).
- Delete `/tmp/sparkle_private_key.txt` after adding the secret.

**No commit** (nothing tracked in this task).

---

## Task 1: Add Sparkle to Package.swift behind the MAS gate

**Files:**
- Modify: `Package.swift`

**Step 1: Rewrite Package.swift with the KIVODO_MAS gate**

```swift
// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Mac App Store builds must not ship Sparkle (the App Store handles updates).
// Set KIVODO_MAS=1 to drop the Sparkle dependency and compile out the updater
// via the MAS_BUILD flag. Default (unset) is the Developer ID / direct-download
// build, which keeps Sparkle.
let masBuild = ProcessInfo.processInfo.environment["KIVODO_MAS"] == "1"

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", .upToNextMinor(from: "2.4.0")),
]
var appDependencies: [Target.Dependency] = [
    "KivodoCore",
    .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
]
var appSwiftSettings: [SwiftSetting] = []

if masBuild {
    appSwiftSettings.append(.define("MAS_BUILD"))
} else {
    packageDependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4"))
    appDependencies.append(.product(name: "Sparkle", package: "Sparkle"))
}

let package = Package(
    name: "Kivodo",
    platforms: [.macOS(.v14)],
    dependencies: packageDependencies,
    targets: [
        .target(name: "KivodoCore"),
        .executableTarget(
            name: "Kivodo",
            dependencies: appDependencies,
            swiftSettings: appSwiftSettings
        ),
        .testTarget(name: "KivodoCoreTests", dependencies: ["KivodoCore"]),
    ]
)
```

**Step 2: Resolve dependencies**

Run: `swift package resolve`
Expected: Sparkle 2.9.4 is fetched; `Package.resolved` updates to include a `Sparkle` entry.

**Step 3: Build to confirm Sparkle links**

Run: `swift build`
Expected: build succeeds (Sparkle compiles/links; no source changes yet so no updater usage).

**Step 4: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "<humanized message>"
```

---

## Task 2: Add the AppUpdater wrapper and menu wiring

**Files:**
- Create: `Sources/Kivodo/AppUpdater.swift`
- Modify: `Sources/Kivodo/KivodoApp.swift`

**Step 1: Create AppUpdater.swift**

```swift
#if !MAS_BUILD
import AppKit
import Sparkle

/// Thin wrapper over Sparkle's standard updater. `startingUpdater: true` begins
/// the automatic background check as soon as the controller is created.
@MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Kivodo is an LSUIElement (no Dock icon), so the update window would open
    /// behind the frontmost app. Activate first so the dialog comes forward.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
#endif
```

**Step 2: Start the updater at launch in KivodoApp.swift**

In `AppDelegate.applicationDidFinishLaunching`, after the existing controller/hotkey setup, add:

```swift
        #if !MAS_BUILD
        _ = AppUpdater.shared
        #endif
```

**Step 3: Add the "Check for Updates…" menu item**

In the `MenuBarExtra` content, above the `Divider()`/`SettingsMenuItem()`, add:

```swift
            #if !MAS_BUILD
            Button("Check for Updates…") {
                AppUpdater.shared.checkForUpdates()
            }
            #endif
```

**Step 4: Build**

Run: `swift build`
Expected: succeeds.

**Step 5: Verify the MAS gate compiles out cleanly**

Run: `KIVODO_MAS=1 swift build`
Expected: succeeds with no reference to Sparkle (AppUpdater.swift is fully behind `#if !MAS_BUILD`).

**Step 6: Commit**

```bash
git add Sources/Kivodo/AppUpdater.swift Sources/Kivodo/KivodoApp.swift
git commit -m "<humanized message>"
```

---

## Task 3: Add Sparkle keys to Info.plist

**Files:**
- Modify: `Support/Info.plist`

**Step 1: Add the SU* keys** (before `</dict>`), using the public key from Task 0:

```xml
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/tarikd/kivodo/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>PASTE_PUBLIC_KEY_FROM_TASK_0</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
```

**Step 2: Lint the plist**

Run: `plutil -lint Support/Info.plist`
Expected: `Support/Info.plist: OK`

**Step 3: Commit**

```bash
git add Support/Info.plist
git commit -m "<humanized message>"
```

---

## Task 4: Add scripts/build_app.sh and repoint the Makefile

**Files:**
- Create: `scripts/build_app.sh` (executable)
- Modify: `Makefile`

**Step 1: Create scripts/build_app.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="Kivodo"
BUNDLE_ID="com.tarik.kivodo"
MAS_BUILD="${KIVODO_MAS:-0}"
OUTPUT_DIR="$ROOT_DIR/build"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
ICON="$ROOT_DIR/Assets/icon/Kivodo.icns"

export COPYFILE_DISABLE=1

cd "$ROOT_DIR"

# swiftbuild engine: Bundle.module looks for resource bundles in
# Contents/Resources, keeping the .app self-contained and relocatable.
swift build -c "$CONFIGURATION" --build-system swiftbuild
BIN="$(swift build -c "$CONFIGURATION" --build-system swiftbuild --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
# Package resource bundles (may be none).
if ls "$BIN"/*.bundle >/dev/null 2>&1; then
  cp -R "$BIN"/*.bundle "$RESOURCES_DIR/"
fi
cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ICON" "$RESOURCES_DIR/Kivodo.icns"

# A MAS build must not advertise a Sparkle feed.
if [ "$MAS_BUILD" = "1" ]; then
  for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true
  done
fi

if [ -n "${KIVODO_MARKETING_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $KIVODO_MARKETING_VERSION" "$CONTENTS_DIR/Info.plist"
fi
if [ -n "${KIVODO_BUNDLE_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $KIVODO_BUNDLE_VERSION" "$CONTENTS_DIR/Info.plist"
fi

# Embed Sparkle.framework (skip for MAS).
SPARKLE_FRAMEWORK="$(find "$BIN" -path '*/Sparkle.framework' -type d -prune -print | head -n 1)"
if [ "$MAS_BUILD" != "1" ] && [ -n "$SPARKLE_FRAMEWORK" ]; then
  mkdir -p "$FRAMEWORKS_DIR"
  rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
  ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR"
fi

# Sign inside-out. Sparkle ships nested helpers (Autoupdate, Updater.app, XPC
# services) that must be signed before the framework, and the framework before
# the app. CI passes a Developer ID identity + hardened runtime; local dev signs
# ad-hoc.
sign_one() {
  local target="$1"
  if [ -n "${KIVODO_CODESIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$KIVODO_CODESIGN_IDENTITY" "$target" >/dev/null
  else
    codesign --force --sign - "$target" >/dev/null
  fi
}

if command -v codesign >/dev/null 2>&1; then
  if [ -d "$FRAMEWORKS_DIR/Sparkle.framework" ]; then
    SPK="$FRAMEWORKS_DIR/Sparkle.framework"
    # XPC services and helper apps/binaries, deepest first.
    while IFS= read -r -d '' helper; do
      sign_one "$helper"
    done < <(find "$SPK/Versions/B" \( -name '*.xpc' -o -name '*.app' \) -print0 2>/dev/null)
    if [ -f "$SPK/Versions/B/Autoupdate" ]; then
      sign_one "$SPK/Versions/B/Autoupdate"
    fi
    sign_one "$SPK"
  fi

  if [ -n "${KIVODO_CODESIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp \
      --sign "$KIVODO_CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR" >/dev/null
  else
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR" >/dev/null
  fi
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR"
fi

echo "$APP_DIR"
```

Note: the exact nested-helper layout is verified in Step 3; adjust the `find` paths to match what Sparkle 2.9.4 actually ships if they differ.

**Step 2: Make it executable**

Run: `chmod +x scripts/build_app.sh`

**Step 3: Inspect the real Sparkle.framework layout before trusting the sign paths**

Run: `find "$(swift build -c release --build-system swiftbuild --show-bin-path)" -path '*/Sparkle.framework/*' -maxdepth 6 -print | grep -Ei 'xpc|Autoupdate|Updater.app|Versions' | head -40`
Expected: lists `Versions/B/Autoupdate`, `Versions/B/XPCServices/*.xpc`, `Versions/B/Updater.app`. Correct the script's `find` paths if the actual layout differs.

**Step 4: Repoint the Makefile `app` target**

Replace the body of the `app:` recipe with:
```make
app: $(ICON)
	CONFIGURATION=release scripts/build_app.sh
```
Keep `icon`, `run`, `test`, `clean` unchanged. `run` still depends on `app`.

**Step 5: Build the app locally (ad-hoc)**

Run: `make app`
Expected: prints the app path; `build/Kivodo.app/Contents/Frameworks/Sparkle.framework` exists.

**Step 6: Verify the signature and plist**

Run:
```bash
codesign --verify --verbose=2 build/Kivodo.app
plutil -lint build/Kivodo.app/Contents/Info.plist
```
Expected: `build/Kivodo.app: valid on disk` / `satisfies its Designated Requirement`; plist `OK`.

**Step 7: Launch and exercise the updater (manual)**

Run: `make run`
Then: open the menu-bar item → "Check for Updates…". Expected: Sparkle's update dialog appears in front. (It will report no update / feed error until the appcast exists — appearing at all confirms the wiring.)

**Step 8: Commit**

```bash
git add scripts/build_app.sh Makefile
git commit -m "<humanized message>"
```

---

## Task 5: Add the GitHub Actions workflow

**Files:**
- Create: `.github/workflows/build.yml`

**Step 1: Create the workflow.** Full contents:

```yaml
name: Build and Release

on:
  pull_request:
  push:
    branches: [main]
    paths-ignore:
      - 'appcast.xml'

permissions:
  contents: write

env:
  SPARKLE_VERSION: "2.9.4"

jobs:
  build:
    name: Build Kivodo
    runs-on: macos-15
    steps:
      - name: Checkout
        uses: actions/checkout@v6.0.3
        with:
          fetch-depth: 0

      - name: Show toolchain
        run: |
          swift --version
          xcodebuild -version

      - name: Build Swift package
        run: swift build

      - name: Import Developer ID certificate
        id: signing
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        env:
          DEVELOPER_ID_CERTIFICATE_BASE64: ${{ secrets.DEVELOPER_ID_CERTIFICATE_BASE64 }}
          DEVELOPER_ID_CERTIFICATE_PASSWORD: ${{ secrets.DEVELOPER_ID_CERTIFICATE_PASSWORD }}
        run: |
          set -euo pipefail
          if [ -z "$DEVELOPER_ID_CERTIFICATE_BASE64" ] || [ -z "$DEVELOPER_ID_CERTIFICATE_PASSWORD" ]; then
            echo "Developer ID certificate secrets are required for release signing." >&2
            exit 1
          fi
          certificate_path="$RUNNER_TEMP/developer-id.p12"
          keychain_path="$RUNNER_TEMP/kivodo-signing.keychain-db"
          keychain_password="$(uuidgen)"
          printf '%s' "$DEVELOPER_ID_CERTIFICATE_BASE64" | base64 -D > "$certificate_path"
          security create-keychain -p "$keychain_password" "$keychain_path"
          security set-keychain-settings -lut 21600 "$keychain_path"
          security unlock-keychain -p "$keychain_password" "$keychain_path"
          security import "$certificate_path" -P "$DEVELOPER_ID_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain_path"
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain_path"
          security list-keychains -d user -s "$keychain_path" $(security list-keychains -d user | tr -d '"')
          identity="$(security find-identity -v -p codesigning "$keychain_path" | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"
          if [ -z "$identity" ]; then
            echo "No Developer ID Application identity found." >&2
            exit 1
          fi
          echo "codesign_identity=$identity" >> "$GITHUB_OUTPUT"

      - name: Derive version from CHANGELOG
        id: version
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        run: |
          set -euo pipefail
          marketing_version="$(grep -m1 -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | sed -E 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/')"
          if [ -z "$marketing_version" ]; then
            echo "Could not parse a version heading from CHANGELOG.md" >&2
            exit 1
          fi
          echo "marketing_version=$marketing_version" >> "$GITHUB_OUTPUT"
          echo "bundle_version=${GITHUB_RUN_NUMBER}" >> "$GITHUB_OUTPUT"

      - name: Build app bundle
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        env:
          KIVODO_MARKETING_VERSION: ${{ steps.version.outputs.marketing_version }}
          KIVODO_BUNDLE_VERSION: ${{ steps.version.outputs.bundle_version }}
          KIVODO_CODESIGN_IDENTITY: ${{ steps.signing.outputs.codesign_identity }}
        run: ./scripts/build_app.sh

      - name: Verify app bundle
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        run: |
          plutil -lint build/Kivodo.app/Contents/Info.plist
          codesign -dv build/Kivodo.app
          codesign --verify --verbose=2 build/Kivodo.app

      - name: Archive app bundle
        id: archive
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        run: |
          set -euo pipefail
          mkdir -p dist
          short_sha="${GITHUB_SHA::7}"
          marketing_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Kivodo.app/Contents/Info.plist)"
          bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' build/Kivodo.app/Contents/Info.plist)"
          zip_name="Kivodo-${marketing_version}-${short_sha}.zip"
          zip_path="dist/${zip_name}"
          xattr -cr build/Kivodo.app
          ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent build/Kivodo.app "${zip_path}"
          shasum -a 256 "${zip_path}" > "${zip_path}.sha256"
          {
            echo "short_sha=${short_sha}"
            echo "marketing_version=${marketing_version}"
            echo "bundle_version=${bundle_version}"
            echo "zip_name=${zip_name}"
            echo "zip_path=${zip_path}"
            echo "checksum_path=${zip_path}.sha256"
            echo "tag_name=v${marketing_version}-${short_sha}"
          } >> "$GITHUB_OUTPUT"

      - name: Notarize and staple app bundle
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        env:
          APPLE_API_KEY_BASE64: ${{ secrets.APPLE_API_KEY_BASE64 }}
          APPLE_API_KEY_ID: ${{ secrets.APPLE_API_KEY_ID }}
          APPLE_API_ISSUER_ID: ${{ secrets.APPLE_API_ISSUER_ID }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          ZIP_PATH: ${{ steps.archive.outputs.zip_path }}
          CHECKSUM_PATH: ${{ steps.archive.outputs.checksum_path }}
        run: |
          set -euo pipefail
          if [ -z "$APPLE_API_KEY_BASE64" ] || [ -z "$APPLE_API_KEY_ID" ] || [ -z "$APPLE_API_ISSUER_ID" ] || [ -z "$APPLE_TEAM_ID" ]; then
            echo "Apple notarization secrets are required." >&2
            exit 1
          fi
          api_key_path="$RUNNER_TEMP/AuthKey_${APPLE_API_KEY_ID}.p8"
          printf '%s' "$APPLE_API_KEY_BASE64" | base64 -D > "$api_key_path"
          submission_result="$RUNNER_TEMP/notary.json"
          xcrun notarytool submit "$ZIP_PATH" --key "$api_key_path" --key-id "$APPLE_API_KEY_ID" \
            --issuer "$APPLE_API_ISSUER_ID" --team-id "$APPLE_TEAM_ID" --wait --timeout 30m \
            --output-format json > "$submission_result"
          cat "$submission_result"
          submission_status="$(plutil -extract status raw -o - "$submission_result")"
          if [ "$submission_status" != "Accepted" ]; then
            submission_id="$(plutil -extract id raw -o - "$submission_result")"
            xcrun notarytool log "$submission_id" --key "$api_key_path" --key-id "$APPLE_API_KEY_ID" \
              --issuer "$APPLE_API_ISSUER_ID" --team-id "$APPLE_TEAM_ID"
            exit 1
          fi
          xcrun stapler staple build/Kivodo.app
          xcrun stapler validate build/Kivodo.app
          codesign --verify --deep --strict --verbose=2 build/Kivodo.app
          spctl --assess --type execute --verbose build/Kivodo.app
          xattr -cr build/Kivodo.app
          ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent build/Kivodo.app "$ZIP_PATH"
          shasum -a 256 "$ZIP_PATH" > "$CHECKSUM_PATH"

      - name: Download Sparkle tools
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          set -euo pipefail
          mkdir -p dist/sparkle-tools/extracted
          gh release download "$SPARKLE_VERSION" --repo sparkle-project/Sparkle \
            --pattern "Sparkle-${SPARKLE_VERSION}.tar.xz" --dir dist/sparkle-tools
          tar -xf "dist/sparkle-tools/Sparkle-${SPARKLE_VERSION}.tar.xz" -C dist/sparkle-tools/extracted

      - name: Generate Sparkle appcast
        id: appcast
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
          TAG_NAME: ${{ steps.archive.outputs.tag_name }}
          ZIP_NAME: ${{ steps.archive.outputs.zip_name }}
          ZIP_PATH: ${{ steps.archive.outputs.zip_path }}
          MARKETING_VERSION: ${{ steps.archive.outputs.marketing_version }}
          BUNDLE_VERSION: ${{ steps.archive.outputs.bundle_version }}
          SHORT_SHA: ${{ steps.archive.outputs.short_sha }}
        run: |
          set -euo pipefail
          if [ -z "$SPARKLE_PRIVATE_KEY" ]; then
            echo "SPARKLE_PRIVATE_KEY secret is required." >&2
            exit 1
          fi
          mkdir -p dist/sparkle
          cp "$ZIP_PATH" "dist/sparkle/$ZIP_NAME"
          # Release notes from the CHANGELOG section for this version.
          notes_path="dist/sparkle/${ZIP_NAME%.zip}.md"
          awk -v v="$MARKETING_VERSION" '
            $0 ~ "^## \\[" v "\\]" {p=1; next}
            p && /^## \[/ {exit}
            p {print}
          ' CHANGELOG.md > "$notes_path" || true
          if [ ! -s "$notes_path" ]; then
            echo "Kivodo ${MARKETING_VERSION} (build ${BUNDLE_VERSION}, ${SHORT_SHA})." > "$notes_path"
          fi
          cp "$notes_path" dist/release-notes.md
          printf '%s' "$SPARKLE_PRIVATE_KEY" | \
            dist/sparkle-tools/extracted/bin/generate_appcast \
              --ed-key-file - \
              --download-url-prefix "https://github.com/${GITHUB_REPOSITORY}/releases/download/${TAG_NAME}/" \
              --link "https://github.com/${GITHUB_REPOSITORY}" \
              --embed-release-notes \
              --maximum-versions 1 \
              dist/sparkle
          echo "appcast_path=dist/sparkle/appcast.xml" >> "$GITHUB_OUTPUT"
          echo "release_notes_path=dist/release-notes.md" >> "$GITHUB_OUTPUT"

      - name: Upload build artifact
        uses: actions/upload-artifact@v7.0.1
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        with:
          name: Kivodo-macOS
          path: |
            ${{ steps.archive.outputs.zip_path }}
            ${{ steps.archive.outputs.checksum_path }}
          if-no-files-found: error

      - name: Create GitHub release
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        env:
          GH_TOKEN: ${{ github.token }}
          TAG_NAME: ${{ steps.archive.outputs.tag_name }}
          ZIP_PATH: ${{ steps.archive.outputs.zip_path }}
          CHECKSUM_PATH: ${{ steps.archive.outputs.checksum_path }}
          APPCAST_PATH: ${{ steps.appcast.outputs.appcast_path }}
          RELEASE_NOTES_PATH: ${{ steps.appcast.outputs.release_notes_path }}
          MARKETING_VERSION: ${{ steps.archive.outputs.marketing_version }}
        run: |
          gh release create "$TAG_NAME" "$ZIP_PATH" "$CHECKSUM_PATH" "$APPCAST_PATH" \
            --target "$GITHUB_SHA" --title "Kivodo ${MARKETING_VERSION}" --notes-file "$RELEASE_NOTES_PATH"

      - name: Commit appcast to main
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        env:
          MARKETING_VERSION: ${{ steps.archive.outputs.marketing_version }}
          SHORT_SHA: ${{ steps.archive.outputs.short_sha }}
        run: |
          set -euo pipefail
          cp "${{ steps.appcast.outputs.appcast_path }}" appcast.xml
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add appcast.xml
          if git diff --cached --quiet; then
            echo "appcast.xml already up to date."
          else
            git commit -m "Update appcast for ${MARKETING_VERSION} (${SHORT_SHA})"
            git push origin HEAD:main
          fi
```

**Step 2: Lint the YAML locally**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/build.yml')); print('yaml ok')"`
Expected: `yaml ok`.

**Step 3: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "<humanized message>"
```

---

## Task 6: Documentation — README + secrets checklist

**Files:**
- Modify: `README.md` (add an "Updates" / "Releases" note and the required-secrets list)

**Step 1:** Add a short section documenting: the app auto-updates via Sparkle; releases are cut on every push to `main`; the repo must stay public for the appcast to serve; the 7 required GitHub secrets with a one-line description each. Run this section through `/humanizer`.

**Step 2: Commit**

```bash
git add README.md
git commit -m "<humanized message>"
```

---

## Task 7: Pre-push checklist (per CLAUDE.md)

Not code — the release discipline required before pushing:

1. Decide the new version (MINOR bump — new capability). Confirm the `CHANGELOG.md` top heading matches.
2. Add a `## [X.Y.Z] - 2026-07-13` section with Added entries (Sparkle updates, CI/CD pipeline), humanized via `/humanizer`, plus the link-reference at the bottom.
3. `git add CHANGELOG.md`.
4. Humanize every commit message via `/humanizer`.
5. Verify no AI attribution anywhere.
6. **Before pushing:** confirm with the user that (a) the repo is public and (b) all 7 secrets are set — otherwise the release job fails. PR builds are safe regardless.
7. Commit and push.

---

## Manual steps owned by the user (cannot be automated here)

- Flip `tarikd/kivodo` to public.
- Add 7 GitHub secrets: `DEVELOPER_ID_CERTIFICATE_BASE64`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_BASE64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_TEAM_ID`, `SPARKLE_PRIVATE_KEY`.
- Confirm a Developer ID Application certificate and an App Store Connect API key (Developer role) exist.
