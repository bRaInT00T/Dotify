#!/bin/zsh
# Regenerates the documentation screenshots with made-up demo content (no real artwork, accounts or
# device names) and copies them into the DocC catalog. Run ./generate-docs.sh afterwards.
set -euo pipefail
cd "$(dirname "$0")"

./build-app.sh
OUT=$(mktemp -d)
# -n starts a separate instance, so a running Dotify is left alone.
open -n -W --env DOTIFY_DEMO=1 --env DOTIFY_SNAPSHOT_DIR="$OUT" build/Dotify.app
mkdir -p Sources/Dotify/Dotify.docc/Resources
cp "$OUT"/*@2x.png Sources/Dotify/Dotify.docc/Resources/
rm -rf "$OUT"
echo "Screenshots copied to Sources/Dotify/Dotify.docc/Resources"
