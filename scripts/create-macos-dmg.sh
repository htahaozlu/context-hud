#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT/dist"
APP_NAME="ContextHUD.app"
APP_PATH="$DIST_DIR/$APP_NAME"
STAGE_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/ContextHUD.dmg"

"$ROOT/scripts/build-menubar-app.sh"

rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"

cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "ContextHUD" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGE_DIR"

echo "Built $DMG_PATH"
