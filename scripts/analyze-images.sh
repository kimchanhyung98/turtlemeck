#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_DIR="${1:-$ROOT/Samples}"

cd "$ROOT"
swift build --disable-sandbox -c release --product analyze-image

if [ ! -d "$INPUT_DIR" ]; then
  echo "input directory not found: $INPUT_DIR" >&2
  exit 2
fi

find "$INPUT_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.heic' \) -print0 |
while IFS= read -r -d '' image; do
  echo "== $image"
  .build/release/analyze-image "$image" || true
done
