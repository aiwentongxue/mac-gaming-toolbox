#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/build/DerivedData}"

xcodebuild \
  -project "$ROOT/Mac游戏工具箱.xcodeproj" \
  -scheme "Mac游戏工具箱" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DERIVED_DATA/Build/Products/Release/Mac 游戏工具箱.app"
HELPER="$APP/Contents/Library/LaunchServices/MacGameToolboxPrivilegedHelper"
xattr -cr "$APP"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
codesign --force --sign - -i com.iven.macgametoolbox.helper "$HELPER"
for attempt in 1 2 3 4 5; do
  xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
  if codesign --force --sign - -i com.iven.macgametoolbox "$APP"; then break; fi
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
