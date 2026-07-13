#!/usr/bin/env bash
set -euo pipefail

# Assemble, embed Sparkle into, and sign build/Kivodo.app from the Swift
# package build. Shared by local dev (make app) and CI.
#
# Env knobs:
#   CONFIGURATION            build config (default: release)
#   KIVODO_MAS               1 = Mac App Store build (drops Sparkle, strips feed keys)
#   KIVODO_MARKETING_VERSION overrides CFBundleShortVersionString
#   KIVODO_BUNDLE_VERSION    overrides CFBundleVersion
#   KIVODO_CODESIGN_IDENTITY Developer ID identity; unset = ad-hoc signing

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

# The Swift Build engine (--build-system swiftbuild) is required: the generated
# Bundle.module accessor looks for package resource bundles in
# Contents/Resources, so the .app stays self-contained and relocatable. The
# default (native) engine bakes in an absolute .build path instead, which
# breaks once the app is separated from this repo.
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

# A Mac App Store build must not advertise a Sparkle feed.
if [ "$MAS_BUILD" = "1" ]; then
  for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true
  done
fi

# Optional version injection (CI passes these from the release tag).
if [ -n "${KIVODO_MARKETING_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $KIVODO_MARKETING_VERSION" "$CONTENTS_DIR/Info.plist"
fi
if [ -n "${KIVODO_BUNDLE_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $KIVODO_BUNDLE_VERSION" "$CONTENTS_DIR/Info.plist"
fi

# Embed Sparkle.framework (skip for MAS builds). SPM links
# @rpath/Sparkle.framework/Versions/*/Sparkle but only bakes @loader_path and
# /usr/lib/swift as rpaths, so we must add @executable_path/../Frameworks for
# the copied framework to resolve at runtime.
SPARKLE_FRAMEWORK="$(find "$BIN" -maxdepth 1 -name 'Sparkle.framework' -type d -print 2>/dev/null | head -n 1)"
if [ "$MAS_BUILD" != "1" ] && [ -n "$SPARKLE_FRAMEWORK" ]; then
  mkdir -p "$FRAMEWORKS_DIR"
  rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
  ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
fi

xattr -cr "$APP_DIR"

# Sign inside-out. Sparkle ships nested helpers (XPC services, Updater.app, the
# Autoupdate binary) that must each be signed before the framework bundle, and
# the framework before the app. A single --deep sign is not enough for Sparkle's
# hardened-runtime layout. CI passes a Developer ID identity + hardened runtime;
# local dev signs ad-hoc (which rewrites the code hash every rebuild, so macOS
# may re-prompt for Reminders access — acceptable for development).
sign_one() {
  local target="$1"
  if [ -n "${KIVODO_CODESIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$KIVODO_CODESIGN_IDENTITY" "$target" >/dev/null
  else
    codesign --force --sign - "$target" >/dev/null
  fi
}

if [ -d "$FRAMEWORKS_DIR/Sparkle.framework" ]; then
  SPK="$FRAMEWORKS_DIR/Sparkle.framework"
  # Resolve the versioned directory (Versions/Current -> B) rather than
  # hardcoding it, in case a future Sparkle bumps the letter.
  if [ -d "$SPK/Versions/Current" ]; then
    VER_DIR="$SPK/Versions/Current"
  else
    VER_DIR="$(find "$SPK/Versions" -mindepth 1 -maxdepth 1 -type d ! -name Current -print 2>/dev/null | head -n 1)"
  fi

  # (a) Nested helpers deepest-first: XPC services and Updater.app, then the
  # Autoupdate command-line binary.
  while IFS= read -r -d '' helper; do
    sign_one "$helper"
  done < <(find "$VER_DIR" \( -name '*.xpc' -o -name '*.app' \) -print0 2>/dev/null | sort -rz)
  if [ -f "$VER_DIR/Autoupdate" ]; then
    sign_one "$VER_DIR/Autoupdate"
  fi

  # (b) The framework bundle itself.
  sign_one "$SPK"
fi

# (c) The whole app last.
if [ -n "${KIVODO_CODESIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp \
    --sign "$KIVODO_CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR" >/dev/null
else
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR" >/dev/null
fi

xattr -cr "$APP_DIR"

echo "$APP_DIR"
