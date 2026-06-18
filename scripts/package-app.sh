#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/turtlemeck.app"
ZIP="$ROOT/.build/turtlemeck.zip"
DMG="$ROOT/.build/turtlemeck.dmg"
BUNDLE_ID="com.go.turtlemeck"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ARM_BIN="$ROOT/.build/arm64-apple-macosx/release/turtlemeck"
X86_BIN="$ROOT/.build/x86_64-apple-macosx/release/turtlemeck"

cd "$ROOT"

swift build --disable-sandbox -c release --arch arm64 --product turtlemeck
swift build --disable-sandbox -c release --arch x86_64 --product turtlemeck

rm -rf "$APP" "$ZIP" "$DMG"
mkdir -p "$MACOS" "$RESOURCES/en.lproj" "$RESOURCES/ko.lproj"

lipo -create "$ARM_BIN" "$X86_BIN" -output "$MACOS/turtlemeck"
cp Resources/Info.plist "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"
cp Resources/en.lproj/InfoPlist.strings "$RESOURCES/en.lproj/InfoPlist.strings"
cp Resources/ko.lproj/InfoPlist.strings "$RESOURCES/ko.lproj/InfoPlist.strings"

chmod +x "$MACOS/turtlemeck"
# 안정적인 번들 식별자를 ad-hoc 서명에 포함해 재빌드 후 TCC 권한 재요청 가능성을 줄인다.
codesign --force --deep --sign - --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -info "$MACOS/turtlemeck"

ditto -c -k --keepParent "$APP" "$ZIP"
if ! hdiutil create -volname "turtlemeck" -srcfolder "$APP" -ov -format UDZO "$DMG"; then
  echo "hdiutil create failed; falling back to hybrid DMG"
  rm -f "$DMG"
  hdiutil makehybrid -hfs -hfs-volume-name "turtlemeck" -o "$DMG" "$APP"
fi

echo "Packaged $APP"
echo "Packaged $ZIP"
echo "Packaged $DMG"
