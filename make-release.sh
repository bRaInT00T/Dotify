#!/bin/zsh
# Packages a universal Dotify.app as build/Dotify-<version>.zip plus a SHA-256 checksum file,
# ready to attach to a GitHub release. The version comes from Resources/Info.plist.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
./build-app.sh --universal

ZIP="build/Dotify-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"
# ditto keeps the bundle intact (plain zip can break the signature); --norsrc leaves out __MACOSX clutter.
ditto -c -k --norsrc --keepParent build/Dotify.app "$ZIP"
(cd build && shasum -a 256 "Dotify-$VERSION.zip" > "Dotify-$VERSION.zip.sha256")

codesign --verify --deep --strict build/Dotify.app
echo "Packaged $ZIP"
cat "$ZIP.sha256"
