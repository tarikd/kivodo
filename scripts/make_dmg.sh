#!/usr/bin/env bash
set -euo pipefail

# Build a drag-to-Applications disk image from build/Kivodo.app, sign it, and
# (when Apple notarization creds are present) notarize + staple it. Shared by
# local dev (make dmg) and CI.
#
# The app inside must already be signed — and for a shippable DMG, notarized +
# stapled — before this runs; this packages it, it does not build it.
#
# The output name is intentionally version-less (Kivodo.dmg) so the GitHub
# "latest" download URL stays stable:
#   https://github.com/<owner>/kivodo/releases/latest/download/Kivodo.dmg
#
# Env knobs:
#   KIVODO_CODESIGN_IDENTITY Developer ID identity; unset = ad-hoc signing
#   APPLE_API_KEY_BASE64     base64 App Store Connect API key (.p8)
#   APPLE_API_KEY_ID         API key id
#   APPLE_API_ISSUER_ID      API issuer id
#   APPLE_TEAM_ID            Developer team id
# When the four Apple vars are all set, the DMG is notarized and stapled;
# otherwise it is signed only (fine for local dev).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Kivodo"
VOLUME_NAME="Kivodo"
OUTPUT_DIR="$ROOT_DIR/build"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/$APP_NAME.dmg"

export COPYFILE_DISABLE=1

if [ ! -d "$APP_DIR" ]; then
  echo "error: $APP_DIR not found — build the app first (make app / build_app.sh)" >&2
  exit 1
fi

# Stage the drag-install layout in a scratch dir: the app plus an /Applications
# symlink so the Finder window shows the familiar "drag here" target.
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
ditto "$APP_DIR" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

# UDZO = zlib-compressed read-only image, the standard for distribution.
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE_DIR" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null

# Sign the disk image itself. Gatekeeper checks the app inside (already signed
# + stapled), but a signed, notarized DMG opens without any warning at all.
if [ -n "${KIVODO_CODESIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$KIVODO_CODESIGN_IDENTITY" "$DMG_PATH" >/dev/null
else
  codesign --force --sign - "$DMG_PATH" >/dev/null
fi

# Notarize + staple the DMG when Apple creds are available (CI). Without them
# (local dev) we ship a signed-only image, which is all a dev build needs.
if [ -n "${APPLE_API_KEY_BASE64:-}" ] && [ -n "${APPLE_API_KEY_ID:-}" ] \
   && [ -n "${APPLE_API_ISSUER_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
  work_dir="${RUNNER_TEMP:-$(mktemp -d)}"
  api_key_path="$work_dir/AuthKey_${APPLE_API_KEY_ID}.p8"
  printf '%s' "$APPLE_API_KEY_BASE64" | base64 -D > "$api_key_path"
  submission_result="$work_dir/notary-dmg.json"
  xcrun notarytool submit "$DMG_PATH" --key "$api_key_path" --key-id "$APPLE_API_KEY_ID" \
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
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

echo "$DMG_PATH"
