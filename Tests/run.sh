#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TEST_ARGUMENTS=(
  --disable-sandbox
  --enable-swift-testing
  --disable-xctest
)

DEVELOPER_DIR="$(xcode-select -p)"
if [[ "$DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" ]]; then
  TESTING_FRAMEWORKS="$DEVELOPER_DIR/Library/Developer/Frameworks"
  TESTING_LIBRARIES="$DEVELOPER_DIR/Library/Developer/usr/lib"
  TEST_ARGUMENTS+=(
    -Xswiftc -F
    -Xswiftc "$TESTING_FRAMEWORKS"
    -Xlinker "-F$TESTING_FRAMEWORKS"
    -Xlinker -rpath
    -Xlinker "$TESTING_FRAMEWORKS"
    -Xlinker -rpath
    -Xlinker "$TESTING_LIBRARIES"
  )
fi

swift test "${TEST_ARGUMENTS[@]}"
