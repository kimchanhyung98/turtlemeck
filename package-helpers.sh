#!/usr/bin/env bash

package_cache_path() {
  local directory
  directory="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)" || return 1
  case "$directory" in
    /) return 1 ;;
    /*) directory="${directory%/}" ;;
    *) return 1 ;;
  esac
  printf '%s/turtlemeck-package-cache/%s/turtlemeck.app\n' "$directory" "$1"
}

has_codesign_forbidden_xattrs() {
  local output
  if ! output="$(xattr -rs "$1" 2>/dev/null)"; then
    return 2
  fi
  if printf '%s\n' "$output" \
    | grep -E '(^|:[[:space:]]+)com\.apple\.(FinderInfo|ResourceFork)$' >/dev/null; then
    return 0
  fi
  return 1
}

# 0: ready to sign, 1: forbidden metadata remains, 2: xattr operation failed.
prepare_codesign_xattrs() {
  local status
  xattr -crs "$1" 2>/dev/null || return 2
  has_codesign_forbidden_xattrs "$1" || status=$?
  case "${status:-0}" in
    0) return 1 ;;
    1) return 0 ;;
    *) return 2 ;;
  esac
}

needs_codesign_cache() {
  local status
  has_codesign_forbidden_xattrs "$1" || status=$?
  if [ "${status:-0}" -ne 1 ]; then
    return 0
  fi
  if prepare_codesign_xattrs "$1"; then
    return 1
  fi
  return 0
}
