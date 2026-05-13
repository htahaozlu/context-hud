#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ContextHUD.app"
APP_DIR="$ROOT/dist/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_SRC="$ROOT/packaging/macos/ContextHUD-Info.plist"
ENTITLEMENTS="$ROOT/packaging/macos/ContextHUD.entitlements"
SWIFT_SRC="$ROOT/menubar/context-hud.swift"
EXECUTABLE="$MACOS_DIR/context-hud"
LOGO_SRC="$ROOT/logo.png"

# Pick a Developer ID Application identity from the keychain unless overridden.
SIGN_IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F\" '/Developer ID Application/ {print $2; exit}')"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

xcrun --sdk macosx swiftc -O "$SWIFT_SRC" -o "$EXECUTABLE"
cp "$PLIST_SRC" "$CONTENTS_DIR/Info.plist"
if [[ -f "$LOGO_SRC" ]]; then
  cp "$LOGO_SRC" "$RESOURCES_DIR/logo.png"
fi
chmod +x "$EXECUTABLE"

# Strip quarantine / provenance xattrs that browsers leak into source files.
xattr -cr "$APP_DIR" 2>/dev/null || true

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing with: $SIGN_IDENTITY"
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP_DIR"
else
  echo "WARNING: No Developer ID Application identity found; falling back to ad-hoc signature."
  echo "         The downloaded app will trigger Gatekeeper warnings."
  codesign --force --deep --sign - --timestamp=none "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "Built $APP_DIR"
