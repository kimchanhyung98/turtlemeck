#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ICON_CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/turtlemeck-icon-check.XXXXXX")"
EXPECTED_ICONSET="$ICON_CHECK_ROOT/Expected.iconset"
mkdir "$EXPECTED_ICONSET"
ICON_NAMES=(
  icon_16x16.png icon_16x16@2x.png
  icon_32x32.png icon_32x32@2x.png
  icon_128x128.png icon_128x128@2x.png
  icon_256x256.png icon_256x256@2x.png
  icon_512x512.png icon_512x512@2x.png
)
ICON_SIZES=(16 32 32 64 128 256 256 512 512 1024)
for index in "${!ICON_NAMES[@]}"; do
  sips -z "${ICON_SIZES[$index]}" "${ICON_SIZES[$index]}" Resources/AppIcon.png \
    --out "$EXPECTED_ICONSET/${ICON_NAMES[$index]}" >/dev/null
done
iconutil -c icns "$EXPECTED_ICONSET" -o "$ICON_CHECK_ROOT/Expected.icns"
iconutil -c iconset "$ICON_CHECK_ROOT/Expected.icns" -o "$ICON_CHECK_ROOT/ExpectedRoundtrip.iconset"
iconutil -c iconset Resources/AppIcon.icns -o "$ICON_CHECK_ROOT/Actual.iconset"
ACTUAL_ICON_COUNT="$(find "$ICON_CHECK_ROOT/Actual.iconset" -type f | wc -l | tr -d ' ')"
if [ "$ACTUAL_ICON_COUNT" -ne "${#ICON_NAMES[@]}" ]; then
  echo "[check] AppIcon.icns contains unexpected representations" >&2
  exit 1
fi
for icon_name in "${ICON_NAMES[@]}"; do
  if ! cmp -s \
    "$ICON_CHECK_ROOT/ExpectedRoundtrip.iconset/$icon_name" \
    "$ICON_CHECK_ROOT/Actual.iconset/$icon_name"; then
    echo "[check] AppIcon.icns representation is stale or corrupted: $icon_name" >&2
    exit 1
  fi
done
find "$ICON_CHECK_ROOT" -depth -delete

swift run --disable-sandbox workflow-tests
