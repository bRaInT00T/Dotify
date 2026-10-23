#!/bin/zsh
# Builds Dotify.app into ./build.
#   --universal  build for both Apple silicon and Intel (used for releases)
#   --install    also copy it to /Applications
set -euo pipefail
cd "$(dirname "$0")"

universal=false
install=false
for arg in "$@"; do
  case "$arg" in
    --universal) universal=true ;;
    --install) install=true ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if $universal; then
  arch_flags=(--arch arm64 --arch x86_64)
else
  arch_flags=()
fi

swift build -c release "${arch_flags[@]}"
APP="build/Dotify.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release "${arch_flags[@]}" --show-bin-path)/Dotify" "$APP/Contents/MacOS/Dotify"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature: required to run on Apple silicon. Not notarized (that needs a paid Developer ID).
codesign --force --sign - "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Dotify"))"

if $install; then
  rm -rf "/Applications/Dotify.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Dotify.app"
fi
