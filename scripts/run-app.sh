#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/turtlemac.app"

if [ ! -x "$APP/Contents/MacOS/turtlemac" ]; then
  "$ROOT/scripts/package-app.sh"
fi

open "$APP"
