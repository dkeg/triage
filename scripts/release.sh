#!/bin/bash
# Builds, signs, notarizes and zips a release: dist/Triage-<version>.zip (+ .sha256).
#
#   scripts/release.sh
#
# Signing:      SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"  (auto-detected if unset)
# Notarization (skipped if none of these are set; the zip is then NOT distributable):
#   NOTARY_PROFILE                                    a keychain profile from `xcrun notarytool store-credentials`
#   or NOTARY_APPLE_ID + NOTARY_PASSWORD + NOTARY_TEAM_ID   Apple ID, app-specific password, team id (CI)
#   or NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID   an App Store Connect API key
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d '[:space:]' < VERSION)"

if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')"
fi
[ -n "$SIGN_IDENTITY" ] || { echo "No Developer ID Application identity found" >&2; exit 1; }
export SIGN_IDENTITY

RELEASE=1 UNIVERSAL=1 scripts/bundle.sh release
APP="build/Triage.app"
mkdir -p dist
ZIP="dist/Triage-${VERSION}.zip"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

notarize() {
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [ -n "${NOTARY_APPLE_ID:-}" ]; then
    xcrun notarytool submit "$1" --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID" --wait
  elif [ -n "${NOTARY_KEY_PATH:-}" ]; then
    xcrun notarytool submit "$1" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
  else
    return 1
  fi
}

ditto -c -k --keepParent "$APP" "$ZIP"
if notarize "$ZIP"; then
  echo "==> Stapling"
  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" "$ZIP"      # re-zip with the ticket stapled in
  spctl -a -vv -t exec "$APP"
  echo "Notarized."
else
  echo "WARNING: not notarized (no notary credentials set). Gatekeeper will block this build on other Macs." >&2
fi

shasum -a 256 "$ZIP" | awk '{print $1}' > "$ZIP.sha256"
echo "==> $ZIP"
echo "    sha256 $(cat "$ZIP.sha256")"
