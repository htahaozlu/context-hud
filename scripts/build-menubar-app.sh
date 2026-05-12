#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ContextHUD.app"
APP_DIR="$ROOT/dist/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_SRC="$ROOT/packaging/macos/ContextHUD-Info.plist"
SWIFT_SRC="$ROOT/menubar/context-hud.swift"
EXECUTABLE="$MACOS_DIR/context-hud"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

xcrun --sdk macosx swiftc -O "$SWIFT_SRC" -o "$EXECUTABLE"
cp "$PLIST_SRC" "$CONTENTS_DIR/Info.plist"
chmod +x "$EXECUTABLE"

echo "Built $APP_DIR"
