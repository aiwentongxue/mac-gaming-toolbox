#!/bin/bash
set -euo pipefail

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION}"
: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE}"

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 '/path/to/Mac 游戏工具箱.app' output.dmg" >&2
  exit 2
fi

APP="$1"
DMG="$2"
HELPER="$APP/Contents/Library/LaunchServices/MacGameToolboxPrivilegedHelper"

xattr -cr "$APP"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
codesign --force --options runtime --timestamp --identifier com.iven.macgametoolbox.helper --sign "$DEVELOPER_ID_APPLICATION" "$HELPER"
for attempt in 1 2 3 4 5; do
  xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
  if codesign --force --options runtime --timestamp --identifier com.iven.macgametoolbox --sign "$DEVELOPER_ID_APPLICATION" "$APP"; then break; fi
  [[ "$attempt" == 5 ]] && exit 1
  sleep 0.2
done
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$APP"
"$(dirname "$0")/package-dmg.sh" "$APP" "$DMG"
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
