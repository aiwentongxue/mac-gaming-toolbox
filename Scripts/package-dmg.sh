#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 '/path/to/Mac 游戏工具箱.app' output.dmg" >&2
  exit 2
fi

APP="$1"
OUTPUT="$2"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

COPYFILE_DISABLE=1 ditto --norsrc --noextattr "$APP" "$STAGING/$(basename "$APP")"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Mac 游戏工具箱" -srcfolder "$STAGING" -ov -format UDZO "$OUTPUT"
