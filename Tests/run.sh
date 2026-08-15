#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ICON_CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/turtlemeck-icon-check.XXXXXX")"
EXPECTED_ICONSET="$ICON_CHECK_ROOT/Expected.iconset"
mkdir "$EXPECTED_ICONSET"
cleanup_icon_check() {
  find "$ICON_CHECK_ROOT" -depth -delete
}
trap cleanup_icon_check EXIT
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
iconutil -c iconset Resources/AppIcon.icns -o "$ICON_CHECK_ROOT/Actual.iconset"
ACTUAL_ICON_COUNT="$(find "$ICON_CHECK_ROOT/Actual.iconset" -type f | wc -l | tr -d ' ')"
if [ "$ACTUAL_ICON_COUNT" -ne "${#ICON_NAMES[@]}" ]; then
  echo "[check] AppIcon.icns contains unexpected representations" >&2
  exit 1
fi
for index in "${!ICON_NAMES[@]}"; do
  icon_name="${ICON_NAMES[$index]}"
  expected_size="${ICON_SIZES[$index]}"
  actual_icon="$ICON_CHECK_ROOT/Actual.iconset/$icon_name"
  if [ ! -f "$actual_icon" ]; then
    echo "[check] AppIcon.icns is missing representation: $icon_name" >&2
    exit 1
  fi
  actual_width="$(sips -g pixelWidth "$actual_icon" | awk '/pixelWidth/ {print $2}')"
  actual_height="$(sips -g pixelHeight "$actual_icon" | awk '/pixelHeight/ {print $2}')"
  # 문자열 비교여야 sips가 빈 출력을 내도 실패로 이어진다.
  if [ "$actual_width" != "$expected_size" ] || [ "$actual_height" != "$expected_size" ]; then
    echo "[check] AppIcon.icns representation has the wrong dimensions: $icon_name" >&2
    exit 1
  fi

  # The checked-in ICNS has separately encoded 16px and 32px 1x images.
  # Validate their presence and dimensions, and compare decoded pixels for
  # the other source-derived representations so PNG encoder metadata cannot
  # cause a false failure.
  if [ "$icon_name" = "icon_16x16.png" ] || [ "$icon_name" = "icon_32x32.png" ]; then
    continue
  fi
  expected_bitmap="$ICON_CHECK_ROOT/${icon_name%.png}-expected.bmp"
  actual_bitmap="$ICON_CHECK_ROOT/${icon_name%.png}-actual.bmp"
  sips -s format bmp "$EXPECTED_ICONSET/$icon_name" --out "$expected_bitmap" >/dev/null
  sips -s format bmp "$actual_icon" --out "$actual_bitmap" >/dev/null
  if ! cmp -s "$expected_bitmap" "$actual_bitmap"; then
    echo "[check] AppIcon.icns representation does not match AppIcon.png: $icon_name" >&2
    exit 1
  fi
done
cleanup_icon_check
trap - EXIT

swift run --disable-sandbox workflow-tests
