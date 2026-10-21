#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/build/DerivedData}"

xcodebuild \
  -project "$ROOT/Mac游戏工具箱.xcodeproj" \
  -scheme "Mac游戏工具箱" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DERIVED_DATA/Build/Products/Release/Mac 游戏工具箱.app"
HELPER="$APP/Contents/Library/LaunchServices/MacGameToolboxPrivilegedHelper"
APPDROP_HELPER_APP="$APP/Contents/Library/LoginItems/AppDropHelper.app"
APPDROP_HELPER="$APPDROP_HELPER_APP/Contents/MacOS/AppDropHelper"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development}"
if ! security find-identity -v -p codesigning | grep -Fq "$SIGN_IDENTITY"; then
  SIGN_IDENTITY="-"
fi
xattr -cr "$APP"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
while IFS= read -r -d '' bundle; do
  xattr -cr "$bundle"
  codesign --force --sign "$SIGN_IDENTITY" "$bundle"
done < <(find "$APP" -type d -name '*.bundle' -print0)
codesign --force --sign "$SIGN_IDENTITY" -i com.iven.macgametoolbox.appdrop.helper "$APPDROP_HELPER"
codesign --force --sign "$SIGN_IDENTITY" "$APPDROP_HELPER_APP"
codesign --force --sign "$SIGN_IDENTITY" -i com.iven.macgametoolbox.helper "$HELPER"
for attempt in 1 2 3 4 5; do
  xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
  if codesign --force --sign "$SIGN_IDENTITY" -i com.iven.macgametoolbox "$APP"; then break; fi
  [[ "$attempt" == 5 ]] && exit 1
  sleep 0.2
done
for attempt in 1 2 3 4 5; do
  xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
  if codesign --verify --deep --strict --verbose=2 "$APP"; then break; fi
  [[ "$attempt" == 5 ]] && exit 1
  sleep 0.2
done
echo "$APP"
