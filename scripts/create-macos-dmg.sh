#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT/dist"
APP_NAME="ContextHUD.app"
APP_PATH="$DIST_DIR/$APP_NAME"
STAGE_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/ContextHUD.dmg"
APP_ZIP="$DIST_DIR/ContextHUD.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-contexthud-notary}"

"$ROOT/scripts/build-menubar-app.sh"

APP_SIG_INFO="$(codesign -dv --verbose=2 "$APP_PATH" 2>&1 || true)"
SIGNED_DEVELOPER_ID=0
if echo "$APP_SIG_INFO" | grep -q "Authority=Developer ID Application"; then
  SIGNED_DEVELOPER_ID=1
fi

# Stage 1: notarize the .app itself and staple the ticket into the bundle so
# even offline machines (or anyone who copies the .app out of the DMG) gets a
# clean Gatekeeper assessment.
if (( SIGNED_DEVELOPER_ID )); then
  rm -f "$APP_ZIP"
  /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
  echo "Submitting app to Apple notary service (profile: $NOTARY_PROFILE)..."
  if xcrun notarytool submit "$APP_ZIP" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait; then
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
  else
    echo "WARNING: app notarization failed; continuing without app staple."
  fi
  rm -f "$APP_ZIP"
fi

# Stage 2: build the DMG containing the (now stapled) app.
rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"

cp -R "$APP_PATH" "$STAGE_DIR/"
xattr -cr "$STAGE_DIR/$APP_NAME" 2>/dev/null || true
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "ContextHUD" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGE_DIR"

# Stage 3: notarize the DMG itself so the download artifact carries its own
# ticket too.
if (( SIGNED_DEVELOPER_ID )); then
  echo "Submitting DMG to Apple notary service (profile: $NOTARY_PROFILE)..."
  if xcrun notarytool submit "$DMG_PATH" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait; then
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
  else
    echo "WARNING: DMG notarization failed; DMG built but NOT notarized."
    echo "         Verify keychain profile exists: xcrun notarytool history --keychain-profile $NOTARY_PROFILE"
  fi
else
  echo "Skipping notarization: app is not Developer ID signed."
fi

echo "Built $DMG_PATH"
