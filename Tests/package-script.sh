#!/usr/bin/env bash
# shellcheck disable=SC2329
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=package-helpers.sh
source "$ROOT/package-helpers.sh"

assert_status() {
  local expected="$1"
  local label="$2"
  local actual
  shift 2
  if "$@"; then
    actual=0
  else
    actual=$?
  fi
  if [ "$actual" -ne "$expected" ]; then
    echo "[check] $label returned $actual, expected $expected" >&2
    exit 1
  fi
}

assert_scan_status() (
  STUB_OUTPUT="$1"
  STUB_STATUS="$2"
  expected="$3"
  label="$4"
  xattr() {
    printf '%s' "$STUB_OUTPUT"
    return "$STUB_STATUS"
  }
  assert_status "$expected" "$label" has_codesign_forbidden_xattrs /fixture
)

assert_scan_status '' 0 1 "clean xattr scan"
assert_scan_status $'/fixture: com.apple.FinderInfo\n' 0 0 "FinderInfo xattr"
assert_scan_status $'/fixture: com.apple.ResourceFork\n' 0 0 "resource-fork xattr"
assert_scan_status $'/fixture: com.example.com.apple.FinderInfo\n' 0 1 "similar xattr name"
assert_scan_status $'/fixture: com.apple.FinderInfo\n' 7 2 "partial xattr scan failure"

(
  XATTR_STATE=clean
  AFTER_CLEAR_STATE=clean
  CLEAR_STATUS=0
  SCAN_STATUS=0
  CLEAR_CALLS=0
  xattr() {
    case "$1" in
      -crs)
        CLEAR_CALLS=$((CLEAR_CALLS + 1))
        if [ "$CLEAR_STATUS" -ne 0 ]; then
          return "$CLEAR_STATUS"
        fi
        XATTR_STATE="$AFTER_CLEAR_STATE"
        ;;
      -rs)
        if [ "$SCAN_STATUS" -ne 0 ]; then
          return "$SCAN_STATUS"
        fi
        if [ "$XATTR_STATE" = forbidden ]; then
          printf '%s\n' '/fixture: com.apple.FinderInfo'
        fi
        ;;
      *) return 64 ;;
    esac
  }

  CLEAR_STATUS=7
  assert_status 2 "xattr clear failure" prepare_codesign_xattrs /fixture
  CLEAR_STATUS=0
  SCAN_STATUS=7
  assert_status 2 "post-clear scan failure" prepare_codesign_xattrs /fixture

  SCAN_STATUS=0
  XATTR_STATE=forbidden
  AFTER_CLEAR_STATE=clean
  CLEAR_CALLS=0
  assert_status 0 "initial FinderInfo fallback" needs_codesign_cache /fixture
  if [ "$CLEAR_CALLS" -ne 0 ]; then
    echo "[check] initial FinderInfo was cleared before fallback selection" >&2
    exit 1
  fi
  XATTR_STATE=clean
  assert_status 1 "clean direct signing" needs_codesign_cache /fixture
  if [ "$CLEAR_CALLS" -ne 1 ]; then
    echo "[check] clean source was not cleared after scanning" >&2
    exit 1
  fi
  XATTR_STATE=clean
  AFTER_CLEAR_STATE=forbidden
  assert_status 0 "metadata restoration fallback" needs_codesign_cache /fixture
  SCAN_STATUS=7
  assert_status 0 "source scan failure fallback" needs_codesign_cache /fixture
)

expected_temp="$(getconf DARWIN_USER_TEMP_DIR)"
expected_temp="${expected_temp%/}"
cache_path="$(TMPDIR='relative temp' package_cache_path test-key)"
if [ "$cache_path" != "$expected_temp/turtlemeck-package-cache/test-key/turtlemeck.app" ]; then
  echo "[check] package cache path is not rooted in the private user temporary directory" >&2
  exit 1
fi
(
  getconf() {
    printf '%s\n' 'relative/temp'
  }
  assert_status 1 "relative user temporary directory" package_cache_path test-key
)

TEST_ROOT="$(mktemp -d "$expected_temp/turtlemeck-package-test.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

APP_FIXTURE="$TEST_ROOT/turtlemeck.app"
EXTERNAL_FILE="$TEST_ROOT/external-model"
FINDER_INFO=0000000000000000000000000000000000000000000000000000000000000001
mkdir -p "$APP_FIXTURE/Contents/Resources"
touch "$APP_FIXTURE/Contents/Resources/model" "$EXTERNAL_FILE"
xattr -wx com.apple.FinderInfo "$FINDER_INFO" "$APP_FIXTURE/Contents/Resources/model"
assert_status 0 "real FinderInfo xattr" has_codesign_forbidden_xattrs "$APP_FIXTURE"
assert_status 0 "real FinderInfo cleanup" prepare_codesign_xattrs "$APP_FIXTURE"

xattr -wx com.apple.FinderInfo "$FINDER_INFO" "$EXTERNAL_FILE"
ln -s "$EXTERNAL_FILE" "$APP_FIXTURE/Contents/Resources/external-model"
assert_status 1 "external symlink target" has_codesign_forbidden_xattrs "$APP_FIXTURE"
assert_status 0 "symlink-safe xattr clear" prepare_codesign_xattrs "$APP_FIXTURE"
if ! xattr -p com.apple.FinderInfo "$EXTERNAL_FILE" >/dev/null; then
  echo "[check] package xattr cleanup followed an external symlink" >&2
  exit 1
fi
