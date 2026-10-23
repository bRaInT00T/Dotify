#!/bin/zsh
# Builds Dotify.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="build/Dotify.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Dotify" "$APP/Contents/MacOS/Dotify"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/Dotify.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Dotify.app"
fi
