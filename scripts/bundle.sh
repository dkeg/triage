#!/bin/bash
# Builds Triage.app from the SwiftPM executable. Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Triage"
APP="$ROOT/build/Triage.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Triage"
cp "$(dirname "$BIN")/triage-hook" "$APP/Contents/MacOS/triage-hook"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.dkeg.triage</string>
  <key>CFBundleName</key><string>triage</string>
  <key>CFBundleDisplayName</key><string>triage</string>
  <key>CFBundleExecutable</key><string>Triage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>triage brings the right Terminal or iTerm2 tab forward when you jump to a session.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Sign with a stable identity when one exists (macOS keeps Screen Recording and other grants
# across rebuilds only for a stable signature); otherwise ad-hoc. Release builds should pass
# SIGN_IDENTITY="Developer ID Application: ..." and notarize.
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)".*/\1/')"
fi
IDENTITY="${IDENTITY:--}"
sign() { codesign --force --sign "$IDENTITY" "$1" 2>/dev/null || codesign --force --sign - "$1"; }
sign "$APP/Contents/MacOS/triage-hook"
sign "$APP"
echo "Signed with: $IDENTITY"
echo "Built $APP"
