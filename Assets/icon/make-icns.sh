#!/usr/bin/env bash
# Generate a macOS .icns from one of the Kivodo SVG masters.
#
# Requirements: macOS `iconutil` (built in) + an SVG rasterizer:
#   * rsvg-convert  (brew install librsvg)   — recommended, sharpest
#   * or inkscape
#
# Usage:  ./make-icns.sh masters/kivodo-2b-frosted-panel.svg Kivodo
#   → writes Kivodo.icns next to this script.
#
set -euo pipefail
cd "$(dirname "$0")"
SVG="${1:?path to master svg}"
NAME="${2:-AppIcon}"
WORK="$(mktemp -d)"
ICONSET="$WORK/$NAME.iconset"
mkdir -p "$ICONSET"
trap 'rm -rf "$WORK"' EXIT

render() { # size outfile
  if command -v rsvg-convert >/dev/null; then
    rsvg-convert -w "$1" -h "$1" "$SVG" -o "$2"
  elif command -v inkscape >/dev/null; then
    inkscape "$SVG" -w "$1" -h "$1" -o "$2" >/dev/null 2>&1
  else
    echo "No SVG rasterizer found. brew install librsvg" >&2; exit 1
  fi
}

# Apple iconset requires 1x + 2x for 16,32,128,256,512.
for s in 16 32 128 256 512; do
  render "$s"        "$ICONSET/icon_${s}x${s}.png"
  render "$((s*2))"  "$ICONSET/icon_${s}x${s}@2x.png"
done

iconutil -c icns "$ICONSET" -o "$NAME.icns"
echo "Wrote $(pwd)/$NAME.icns"
