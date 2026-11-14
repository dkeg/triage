#!/bin/bash
# Builds build/Triage.app from the SwiftPM products.
#
#   scripts/bundle.sh [debug|release]
#
# Environment:
#   UNIVERSAL=1      build for arm64 + x86_64
#   RELEASE=1        sign with the hardened runtime + secure timestamp + entitlements and refuse to
#                    fall back to ad-hoc signing (use with SIGN_IDENTITY="Developer ID Application: ...")
#   SIGN_IDENTITY    codesign identity. Default: an "Apple Development" identity if present (a stable
#                    signature keeps macOS privacy grants across rebuilds), otherwise ad-hoc.
set -euo pipefail
CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="$ROOT/build/Triage.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Triage" "$APP/Contents/MacOS/Triage"
cp "$BIN_DIR/triage-hook" "$APP/Contents/MacOS/triage-hook"
mkdir -p "$APP/Contents/Resources"
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.dkeg.triage</string>
  <key>CFBundleName</key><string>triage</string>
  <key>CFBundleDisplayName</key><string>triage</string>
  <key>CFBundleExecutable</key><string>Triage</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>triage brings the right Terminal or iTerm2 tab forward when you jump to a session.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && [ "${RELEASE:-0}" != "1" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)".*/\1/')"
fi

if [ "${RELEASE:-0}" = "1" ]; then
  [ -n "$IDENTITY" ] || { echo "RELEASE=1 needs SIGN_IDENTITY (a Developer ID Application identity)" >&2; exit 1; }
  sign() { codesign --force --timestamp --options runtime --entitlements packaging/triage.entitlements --sign "$IDENTITY" "$1"; }
else
  IDENTITY="${IDENTITY:--}"
  sign() { codesign --force --sign "$IDENTITY" "$1" 2>/dev/null || codesign --force --sign - "$1"; }
fi
sign "$APP/Contents/MacOS/triage-hook"
sign "$APP"
echo "Signed with: $IDENTITY"
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"
