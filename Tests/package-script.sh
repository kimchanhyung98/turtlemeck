#!/usr/bin/env bash
# shellcheck disable=SC2329
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

extract_function() {
  local name="$1"
  sed -n "/^${name}() {$/,/^}$/p" package.sh
}

for function_name in package_cache_path has_codesign_forbidden_xattrs prepare_codesign_xattrs; do
  definition="$(extract_function "$function_name")"
  if [ -z "$definition" ]; then
    echo "[check] package.sh is missing $function_name" >&2
    exit 1
  fi
  eval "$definition"
done

assert_status() {
  local expected="$1"
  local label="$2"
  local actual
  shift 2
  set +e
  "$@"
  actual=$?
  set -e
  if [ "$actual" -ne "$expected" ]; then
    echo "[check] $label returned $actual, expected $expected" >&2
    exit 1
  fi
}

(
  xattr() {
    printf '%s\n' '/tmp/turtlemeck.app: com.example.com.apple.FinderInfo'
  }
  assert_status 1 "similar xattr name" has_codesign_forbidden_xattrs /tmp/turtlemeck.app
)

(
  xattr() {
    printf '%s\n' '/tmp/turtlemeck.app: com.apple.FinderInfo'
  }
  assert_status 0 "FinderInfo xattr" has_codesign_forbidden_xattrs /tmp/turtlemeck.app
)

(
  xattr() {
    return 0
  }
  assert_status 1 "clean xattr scan" has_codesign_forbidden_xattrs /tmp/turtlemeck.app
)

(
  xattr() {
    printf '%s\n' '/tmp/turtlemeck.app: com.apple.FinderInfo'
    return 7
  }
  assert_status 2 "xattr scan failure" has_codesign_forbidden_xattrs /tmp/turtlemeck.app
)

(
  XATTR_CLEAR_STATUS=0
  XATTR_SCAN_STATUS=0
  XATTR_SCAN_OUTPUT=""
  xattr() {
    case "$1" in
      -crs) return "$XATTR_CLEAR_STATUS" ;;
      -rs)
        if [ -n "$XATTR_SCAN_OUTPUT" ]; then
          printf '%s\n' "$XATTR_SCAN_OUTPUT"
        fi
        return "$XATTR_SCAN_STATUS"
        ;;
      *) return 64 ;;
    esac
  }

  assert_status 0 "removable xattrs" prepare_codesign_xattrs /tmp/turtlemeck.app
  XATTR_SCAN_OUTPUT='/tmp/turtlemeck.app: com.apple.FinderInfo'
  assert_status 1 "restored FinderInfo" prepare_codesign_xattrs /tmp/turtlemeck.app
  XATTR_SCAN_OUTPUT='/tmp/turtlemeck.app: com.example.com.apple.FinderInfo'
  assert_status 0 "similar restored xattr name" prepare_codesign_xattrs /tmp/turtlemeck.app
  XATTR_SCAN_STATUS=7
  assert_status 2 "post-clear scan failure" prepare_codesign_xattrs /tmp/turtlemeck.app
  XATTR_CLEAR_STATUS=7
  XATTR_SCAN_STATUS=0
  XATTR_SCAN_OUTPUT=""
  assert_status 2 "xattr clear failure" prepare_codesign_xattrs /tmp/turtlemeck.app
)

cache_path="$(TMPDIR='relative temp' package_cache_path test-key)"
expected_temp="$(getconf DARWIN_USER_TEMP_DIR)"
expected_temp="${expected_temp%/}"
if [ "$cache_path" != "$expected_temp/turtlemeck-package-cache/test-key/turtlemeck.app" ]; then
  echo "[check] package cache path is not rooted in the private user temporary directory" >&2
  exit 1
fi
if [ "$(stat -f '%u' "$expected_temp")" != "$(id -u)" ]; then
  echo "[check] private user temporary directory has the wrong owner" >&2
  exit 1
fi
temp_mode="$(stat -f '%Lp' "$expected_temp")"
if [ $((8#$temp_mode & 0022)) -ne 0 ]; then
  echo "[check] private user temporary directory is group- or world-writable" >&2
  exit 1
fi

(
  getconf() {
    printf '%s\n' 'relative/temp'
  }
  assert_status 1 "relative user temporary directory" package_cache_path test-key
)

(
  getconf() {
    return 7
  }
  assert_status 1 "user temporary directory lookup failure" package_cache_path test-key
)

TEST_ROOT="$(mktemp -d "$expected_temp/turtlemeck-package-test.XXXXXX")"
cleanup() {
  chmod -R u+rwx "$TEST_ROOT" 2>/dev/null || true
  find "$TEST_ROOT" -depth -delete
}
trap cleanup EXIT

APP_FIXTURE="$TEST_ROOT/turtlemeck.app"
EXTERNAL_FILE="$TEST_ROOT/external-model"
mkdir -p "$APP_FIXTURE/Contents/Resources"
touch "$APP_FIXTURE/Contents/Resources/model" "$EXTERNAL_FILE"
xattr -wx com.apple.FinderInfo \
  0000000000000000000000000000000000000000000000000000000000000001 \
  "$APP_FIXTURE/Contents/Resources/model"
assert_status 0 "real FinderInfo xattr" has_codesign_forbidden_xattrs "$APP_FIXTURE"
assert_status 0 "real removable FinderInfo" prepare_codesign_xattrs "$APP_FIXTURE"
assert_status 1 "real cleared FinderInfo" has_codesign_forbidden_xattrs "$APP_FIXTURE"

xattr -wx com.apple.FinderInfo \
  0000000000000000000000000000000000000000000000000000000000000001 \
  "$EXTERNAL_FILE"
ln -s "$EXTERNAL_FILE" "$APP_FIXTURE/Contents/Resources/external-model"
assert_status 1 "external symlink target" has_codesign_forbidden_xattrs "$APP_FIXTURE"
assert_status 0 "symlink-safe xattr clear" prepare_codesign_xattrs "$APP_FIXTURE"
if ! xattr -p com.apple.FinderInfo "$EXTERNAL_FILE" >/dev/null; then
  echo "[check] package xattr cleanup followed an external symlink" >&2
  exit 1
fi
