#!/bin/zsh
# Regenerates the DocC site into ./docs (served by GitHub Pages at /Dotify/).
set -euo pipefail
cd "$(dirname "$0")"

rm -rf docs
swift package --allow-writing-to-directory docs \
  generate-documentation --target Dotify \
  --symbol-graph-minimum-access-level internal \
  --experimental-skip-synthesized-symbols \
  --disable-indexing \
  --transform-for-static-hosting \
  --hosting-base-path Dotify \
  --output-path docs
touch docs/.nojekyll  # serve DocC files as-is on GitHub Pages
echo "Docs written to ./docs"
