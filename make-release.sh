#!/bin/zsh
# Packages a universal Dotify.app as build/Dotify-<version>.zip plus a SHA-256 checksum file,
# ready to attach to a GitHub release. The version comes from Resources/Info.plist.
#
# Signed + notarized release (recommended):
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=dotify-notary ./make-release.sh
# SIGN_IDENTITY alone signs with hardened runtime but skips notarization (for testing).
# Neither: ad-hoc signed, and users must click "Open Anyway" on first launch.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP=build/Dotify.app
ZIP="build/Dotify-$VERSION.zip"
./build-app.sh --universal

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp \
    --entitlements Resources/Dotify.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"

zip_app() {
  rm -f "$ZIP"
  # ditto keeps the bundle intact (plain zip can break the signature); --norsrc leaves out __MACOSX clutter.
  ditto -c -k --norsrc --keepParent "$APP" "$ZIP"
}
zip_app

if [[ -n "${SIGN_IDENTITY:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Submitting to Apple for notarization (usually a few minutes)…"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  # Attach the notarization ticket to the app so it opens offline too, then re-zip the stapled app.
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  zip_app
  spctl --assess --type execute --verbose=2 "$APP"
fi

(cd build && shasum -a 256 "Dotify-$VERSION.zip" > "Dotify-$VERSION.zip.sha256")
echo "Packaged $ZIP"
cat "$ZIP.sha256"
