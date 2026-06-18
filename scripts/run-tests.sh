#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p .build

CORE_SOURCES=$(find Sources/TurtleCore -name '*.swift' | sort)
TEST_SOURCES=$(find Tests/manual -name '*.swift' | sort)

swiftc \
  -O \
  -parse-as-library \
  $CORE_SOURCES \
  $TEST_SOURCES \
  -o .build/turtlemeck-manual-tests

.build/turtlemeck-manual-tests
