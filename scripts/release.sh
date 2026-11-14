#!/bin/bash
# Builds, signs, notarizes and zips a release: dist/Triage-<version>.zip (+ .sha256).
#
#   scripts/release.sh
#
# Signing:      SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"  (auto-detected if unset)
# Notarization (skipped if none of these are set; the zip is then NOT distributable):
#   REQUIRE_NOTARIZATION=1                            fail instead of warning when notarization does not happen
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
  # The ticket can take a moment to be available after acceptance, and Apple's CDN occasionally
  # drops the connection; retry before giving up.
  stapled=0
  for attempt in 1 2 3 4 5 6; do
    if xcrun stapler staple "$APP"; then stapled=1; break; fi
    echo "stapling attempt $attempt failed; retrying in 20s" >&2
    sleep 20
  done
  [ "$stapled" = "1" ] || { echo "Could not staple the notarization ticket" >&2; exit 1; }
  ditto -c -k --keepParent "$APP" "$ZIP"      # re-zip with the ticket stapled in
  spctl -a -vv -t exec "$APP"
  echo "Notarized."
else
  echo "WARNING: not notarized (missing or rejected notary credentials). Gatekeeper will block this build on other Macs." >&2
  # CI sets REQUIRE_NOTARIZATION=1 so a build that can't be notarized is never published.
  if [ "${REQUIRE_NOTARIZATION:-0}" = "1" ]; then echo "REQUIRE_NOTARIZATION=1: refusing to continue." >&2; exit 1; fi
fi

shasum -a 256 "$ZIP" | awk '{print $1}' > "$ZIP.sha256"
echo "==> $ZIP"
echo "    sha256 $(cat "$ZIP.sha256")"
