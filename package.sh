#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export COPYFILE_DISABLE=1
APP="$ROOT/.build/turtlemeck.app"
CHECKSUMS="$ROOT/.build/SHA256SUMS"
BUNDLE_ID="com.go.turtlemeck"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ARM_BIN="$ROOT/.build/arm64-apple-macosx/release/turtlemeck"
X86_BIN="$ROOT/.build/x86_64-apple-macosx/release/turtlemeck"
RELEASE_ENTITLEMENTS="$ROOT/Resources/turtlemeck.release.entitlements"
RELEASE_MODE="${TURTLEMECK_RELEASE:-0}"
VERSION="${TURTLEMECK_VERSION:-}"
BUILD="${TURTLEMECK_BUILD:-}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARY_ARCHIVE=""
DMG_STAGE=""
ARTIFACT_NAME="turtlemeck"
if [ "$RELEASE_MODE" = "1" ] && [ -n "$VERSION" ]; then
  ARTIFACT_NAME="turtlemeck-$VERSION"
fi
ZIP="$ROOT/.build/$ARTIFACT_NAME.zip"
DMG="$ROOT/.build/$ARTIFACT_NAME.dmg"

cleanup() {
  if [ -n "$NOTARY_ARCHIVE" ]; then
    rm -f "$NOTARY_ARCHIVE"
  fi
  if [ -n "$DMG_STAGE" ]; then
    rm -rf "$DMG_STAGE"
  fi
}

trap cleanup EXIT

if [ "$RELEASE_MODE" != "0" ] && [ "$RELEASE_MODE" != "1" ]; then
  echo "[package] TURTLEMECK_RELEASE must be 0 or 1" >&2
  exit 1
fi
if [ -n "$VERSION" ] && [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "[package] TURTLEMECK_VERSION must use the numeric major.minor.patch format" >&2
  exit 1
fi
if [ -n "$BUILD" ] && [[ ! "$BUILD" =~ ^[1-9][0-9]*$ ]]; then
  echo "[package] TURTLEMECK_BUILD must be a positive integer" >&2
  exit 1
fi
# 릴리스 모드는 Developer ID 서명과 Apple 공증 정보를 모두 요구한다.
if [ "$RELEASE_MODE" = "1" ]; then
  : "${VERSION:?set TURTLEMECK_VERSION for a release build}"
  : "${BUILD:?set TURTLEMECK_BUILD for a release build}"
  : "${CODESIGN_IDENTITY:?set CODESIGN_IDENTITY for a release build}"
  : "${NOTARY_APPLE_ID:?set NOTARY_APPLE_ID for a release build}"
  : "${NOTARY_APP_PASSWORD:?set NOTARY_APP_PASSWORD for a release build}"
  : "${NOTARY_TEAM_ID:?set NOTARY_TEAM_ID for a release build}"
  test -f "$RELEASE_ENTITLEMENTS"
  if [ "$CODESIGN_IDENTITY" = "-" ]; then
    echo "[package] release builds require a Developer ID signing identity" >&2
    exit 1
  fi
fi

notarize() {
  xcrun notarytool submit "$1" \
    --apple-id "$NOTARY_APPLE_ID" \
    --password "$NOTARY_APP_PASSWORD" \
    --team-id "$NOTARY_TEAM_ID" \
    --wait
}

cd "$ROOT"

swift build --disable-sandbox -c release --arch arm64 --product turtlemeck
swift build --disable-sandbox -c release --arch x86_64 --product turtlemeck

rm -rf "$APP" "$ZIP" "$DMG" "$CHECKSUMS"
mkdir -p "$MACOS" "$RESOURCES/en.lproj" "$RESOURCES/ko.lproj"

lipo -create "$ARM_BIN" "$X86_BIN" -output "$MACOS/turtlemeck"
cp Resources/Info.plist "$CONTENTS/Info.plist"
if [ -n "$VERSION" ]; then
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS/Info.plist"
fi
if [ -n "$BUILD" ]; then
  plutil -replace CFBundleVersion -string "$BUILD" "$CONTENTS/Info.plist"
fi
printf 'APPL????' > "$CONTENTS/PkgInfo"
cp Resources/en.lproj/InfoPlist.strings "$RESOURCES/en.lproj/InfoPlist.strings"
cp Resources/ko.lproj/InfoPlist.strings "$RESOURCES/ko.lproj/InfoPlist.strings"
cp Resources/AppIcon.icns "$RESOURCES/AppIcon.icns"
cp Resources/ThirdPartyNotices.md "$RESOURCES/ThirdPartyNotices.md"
cp Resources/Apache-2.0.txt "$RESOURCES/Apache-2.0.txt"
MODEL_NAME="DepthAnythingV2SmallF16"
POSE_MODEL_NAME="PoseNetMobileNet075S16FP16"
compile_model() {
  local source_model="$1"
  if xcrun --find coremlcompiler >/dev/null 2>&1; then
    xcrun coremlcompiler compile "$source_model" "$RESOURCES"
    return 0
  fi
  return 1
}

if [ -d "Resources/$MODEL_NAME.mlmodelc" ]; then
  cp -R "Resources/$MODEL_NAME.mlmodelc" "$RESOURCES/"
elif [ -e "Resources/$MODEL_NAME.mlpackage" ]; then
  if ! compile_model "Resources/$MODEL_NAME.mlpackage"; then
    echo "[package] coremlcompiler not found; bundling $MODEL_NAME.mlpackage for runtime prewarm fallback" >&2
    cp -R "Resources/$MODEL_NAME.mlpackage" "$RESOURCES/"
  fi
elif [ -e "Resources/$MODEL_NAME.mlmodel" ]; then
  if ! compile_model "Resources/$MODEL_NAME.mlmodel"; then
    echo "[package] coremlcompiler not found; bundling $MODEL_NAME.mlmodel for runtime prewarm fallback" >&2
    cp "Resources/$MODEL_NAME.mlmodel" "$RESOURCES/"
  fi
fi

MODEL_RESOURCE_COUNT=0
for extension in mlmodelc mlpackage mlmodel; do
  if [ -e "$RESOURCES/$MODEL_NAME.$extension" ]; then
    MODEL_RESOURCE_COUNT=$((MODEL_RESOURCE_COUNT + 1))
  fi
done
if [ "$MODEL_RESOURCE_COUNT" -ne 1 ]; then
  echo "[package] expected exactly one $MODEL_NAME model resource, found $MODEL_RESOURCE_COUNT" >&2
  exit 1
fi
if [ -e "Resources/$POSE_MODEL_NAME.mlmodel" ]; then
  if ! compile_model "Resources/$POSE_MODEL_NAME.mlmodel"; then
    echo "[package] coremlcompiler not found; bundling $POSE_MODEL_NAME.mlmodel for runtime compilation" >&2
    cp "Resources/$POSE_MODEL_NAME.mlmodel" "$RESOURCES/"
  fi
fi
POSE_MODEL_RESOURCE_COUNT=0
for extension in mlmodelc mlmodel; do
  if [ -e "$RESOURCES/$POSE_MODEL_NAME.$extension" ]; then
    POSE_MODEL_RESOURCE_COUNT=$((POSE_MODEL_RESOURCE_COUNT + 1))
  fi
done
if [ "$POSE_MODEL_RESOURCE_COUNT" -ne 1 ]; then
  echo "[package] expected exactly one $POSE_MODEL_NAME model resource, found $POSE_MODEL_RESOURCE_COUNT" >&2
  exit 1
fi
if [ ! -f "$RESOURCES/AppIcon.icns" ] || [ ! -f "$RESOURCES/ThirdPartyNotices.md" ] || [ ! -f "$RESOURCES/Apache-2.0.txt" ]; then
  echo "[package] required icon or third-party notices are missing" >&2
  exit 1
fi
xattr -cr "$APP" 2>/dev/null || true

chmod +x "$MACOS/turtlemeck"
ARCHS="$(lipo -archs "$MACOS/turtlemeck")"
case " $ARCHS " in
  *" arm64 "*) ;;
  *) echo "[package] arm64 architecture is missing: $ARCHS" >&2; exit 1 ;;
esac
case " $ARCHS " in
  *" x86_64 "*) ;;
  *) echo "[package] x86_64 architecture is missing: $ARCHS" >&2; exit 1 ;;
esac
# 앱을 먼저 공증해 DMG 밖으로 복사한 뒤에도 공증 티켓을 유지한다.
if [ "$RELEASE_MODE" = "1" ]; then
  codesign --force --options runtime --timestamp --entitlements "$RELEASE_ENTITLEMENTS" --sign "$CODESIGN_IDENTITY" "$APP"
else
  # 안정적인 번들 식별자를 ad-hoc 서명에 포함해 재빌드 후 TCC 권한 재요청 가능성을 줄인다.
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" --timestamp=none "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
# 최종 배포 파일인 DMG도 별도로 서명하고 공증한다.
if [ "$RELEASE_MODE" = "1" ]; then
  codesign -d --entitlements - --xml "$APP" 2>/dev/null \
    | plutil -convert json -o - - \
    | grep -Eq '"com\.apple\.security\.device\.camera"[[:space:]]*:[[:space:]]*true'
fi
test "$(plutil -extract CFBundleIdentifier raw "$CONTENTS/Info.plist")" = "$BUNDLE_ID"
if [ -n "$VERSION" ]; then
  test "$(plutil -extract CFBundleShortVersionString raw "$CONTENTS/Info.plist")" = "$VERSION"
fi
if [ -n "$BUILD" ]; then
  test "$(plutil -extract CFBundleVersion raw "$CONTENTS/Info.plist")" = "$BUILD"
fi
echo "Architectures in the fat file: $ARCHS"

if [ "$RELEASE_MODE" = "1" ]; then
  NOTARY_ARCHIVE="$ROOT/.build/turtlemeck-notarize.zip"
  rm -f "$NOTARY_ARCHIVE"
  ditto -c -k --keepParent "$APP" "$NOTARY_ARCHIVE"
  notarize "$NOTARY_ARCHIVE"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
  rm -f "$NOTARY_ARCHIVE"
  NOTARY_ARCHIVE=""
fi

(
  cd "$ROOT/.build"
  zip -qry -X "$(basename "$ZIP")" "$(basename "$APP")"
)
DMG_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/turtlemeck-dmg.XXXXXX")"
cp -R "$APP" "$DMG_STAGE/turtlemeck.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "turtlemeck" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG"
rm -rf "$DMG_STAGE"
DMG_STAGE=""

if [ "$RELEASE_MODE" = "1" ]; then
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"
  codesign --verify --verbose=2 "$DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  codesign --verify --verbose=2 "$DMG"
fi

hdiutil verify "$DMG"
zip -T "$ZIP"

(
  cd "$ROOT/.build"
  shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > "$(basename "$CHECKSUMS")"
  shasum -a 256 -c "$(basename "$CHECKSUMS")"
)

echo "Packaged $APP"
echo "Packaged $ZIP"
echo "Packaged $DMG"
echo "Checksums $CHECKSUMS"
