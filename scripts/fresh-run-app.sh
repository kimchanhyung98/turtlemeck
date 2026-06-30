#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/turtlemeck.app"

osascript -e 'tell application id "com.go.turtlemeck" to quit' >/dev/null 2>&1 || true
for _ in {1..20}; do
  if ! pgrep -x turtlemeck >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
pkill -x turtlemeck >/dev/null 2>&1 || true

"$ROOT/scripts/package-app.sh"

open -n "$APP"
