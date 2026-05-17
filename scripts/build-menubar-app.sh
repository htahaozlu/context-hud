#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ContextBar.app"
APP_DIR="$ROOT/dist/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_SRC="$ROOT/packaging/macos/ContextBar-Info.plist"
ENTITLEMENTS="$ROOT/packaging/macos/ContextBar.entitlements"
SWIFT_SRC_DIR="$ROOT/menubar/sources"
EXECUTABLE="$MACOS_DIR/context-bar"
ENGINE_DST="$MACOS_DIR/context-bar-engine"
USAGE_PY_SRC="$ROOT/src/usage_signal.py"
USAGE_PY_DST="$RESOURCES_DIR/usage_signal.py"
LOGO_SRC="$ROOT/logo.png"
APP_ICON_SRC="$ROOT/app_logo.png"
APP_ICON_DST="$RESOURCES_DIR/AppIcon.icns"
BRAND_ICONS_SRC="$ROOT/menubar/assets/brands"
BRAND_ICONS_DST="$RESOURCES_DIR/brands"
APP_PLIST_DST="$CONTENTS_DIR/Info.plist"
WIDGET_SRC_DIR="$ROOT/menubar/widget"
WIDGET_XCODEPROJ="$ROOT/packaging/macos/ContextBarWidget.xcodeproj"
WIDGET_XCODEGEN="$ROOT/scripts/generate-widget-xcodeproj.rb"
WIDGET_ENTITLEMENTS="$ROOT/packaging/macos/widget/Widget.entitlements"
PLUGINS_DIR="$CONTENTS_DIR/PlugIns"
WIDGET_APPEX="$PLUGINS_DIR/ContextBarWidget.appex"
WIDGET_BUILD_DIR="$ROOT/target/widget-xcodebuild"

VERSION="$(sed -n 's/^version = \"\(.*\)\"/\1/p' "$ROOT/Cargo.toml" | head -n1)"
if [[ -z "$VERSION" ]]; then
  echo "Failed to derive version from Cargo.toml" >&2
  exit 1
fi
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD)"
else
  BUILD_NUMBER="1"
fi

# Pick a Developer ID Application identity from the keychain unless overridden.
SIGN_IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F\" '/Developer ID Application/ {print $2; exit}')"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

EXECUTABLE_ARM64="$EXECUTABLE.arm64"
EXECUTABLE_X86_64="$EXECUTABLE.x86_64"
MIN_MACOS="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
xcrun --sdk macosx swiftc -O -target "arm64-apple-macos${MIN_MACOS}" "$SWIFT_SRC_DIR"/*.swift -o "$EXECUTABLE_ARM64"
xcrun --sdk macosx swiftc -O -target "x86_64-apple-macos${MIN_MACOS}" "$SWIFT_SRC_DIR"/*.swift -o "$EXECUTABLE_X86_64"
lipo -create "$EXECUTABLE_ARM64" "$EXECUTABLE_X86_64" -output "$EXECUTABLE"
rm -f "$EXECUTABLE_ARM64" "$EXECUTABLE_X86_64"
lipo -info "$EXECUTABLE"
cp "$PLIST_SRC" "$APP_PLIST_DST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PLIST_DST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PLIST_DST"
if [[ -f "$LOGO_SRC" ]]; then
  cp "$LOGO_SRC" "$RESOURCES_DIR/logo.png"
fi
if [[ -d "$BRAND_ICONS_SRC" ]]; then
  mkdir -p "$BRAND_ICONS_DST"
  cp "$BRAND_ICONS_SRC"/*.png "$BRAND_ICONS_DST"/
fi

# Generate AppIcon.icns from app_logo.png (2048x2048 source).
if [[ -f "$APP_ICON_SRC" ]]; then
  ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET_DIR"
  for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
              "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
              "512 512x512" "1024 512x512@2x"; do
    size="${spec%% *}"
    name="${spec##* }"
    sips -z "$size" "$size" "$APP_ICON_SRC" --out "$ICONSET_DIR/icon_${name}.png" >/dev/null
  done
  iconutil -c icns "$ICONSET_DIR" -o "$APP_ICON_DST"
  rm -rf "$(dirname "$ICONSET_DIR")"
fi
chmod +x "$EXECUTABLE"

# Build and embed the Rust engine so the menubar app can regenerate hud.json
# on demand without any external daemon. Universal binary via two passes + lipo.
ENGINE_ARM64="$ROOT/target/aarch64-apple-darwin/release/context-bar"
ENGINE_X86_64="$ROOT/target/x86_64-apple-darwin/release/context-bar"
rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null
(cd "$ROOT" && cargo build --release --bin context-bar --target aarch64-apple-darwin)
(cd "$ROOT" && cargo build --release --bin context-bar --target x86_64-apple-darwin)
lipo -create "$ENGINE_ARM64" "$ENGINE_X86_64" -output "$ENGINE_DST"
chmod +x "$ENGINE_DST"
cp "$USAGE_PY_SRC" "$USAGE_PY_DST"

# WidgetKit extensions need Xcode's extension build pipeline. Raw `swiftc`
# can produce an `.appex`-shaped bundle that pluginkit refuses to enumerate.
# Keep widget packaging opt-in until release signing/notarization covers it.
if [[ "${WIDGET_BUILD:-0}" == "1" && -d "$WIDGET_SRC_DIR" ]]; then
  if [[ ! -d "$WIDGET_XCODEPROJ" ]]; then
    "$WIDGET_XCODEGEN"
  fi
  rm -rf "$WIDGET_BUILD_DIR"
  xcodebuild \
    -project "$WIDGET_XCODEPROJ" \
    -target ContextBarWidget \
    -configuration Release \
    SYMROOT="$WIDGET_BUILD_DIR/Build/Products" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    build
  mkdir -p "$PLUGINS_DIR"
  cp -R "$WIDGET_BUILD_DIR/Build/Products/Release/ContextBarWidget.appex" "$WIDGET_APPEX"
fi

# Strip quarantine / provenance xattrs that browsers leak into source files.
xattr -cr "$APP_DIR" 2>/dev/null || true

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing with: $SIGN_IDENTITY"
  # Inner executables must be signed before the bundle so the bundle's
  # signature covers a fully-signed payload.
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$ENGINE_DST"
  if [[ -d "$WIDGET_APPEX" ]]; then
    codesign --force --options runtime --timestamp \
      --entitlements "$WIDGET_ENTITLEMENTS" \
      --sign "$SIGN_IDENTITY" \
      "$WIDGET_APPEX"
  fi
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
