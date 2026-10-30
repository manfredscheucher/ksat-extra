#!/usr/bin/env bash
# Build the static website: the ksat playground (Kotlin/JS production bundle) at the site root.
# Output: build/pages/
#
#   ./scripts/buildWeb.sh
set -euo pipefail
cd "$(dirname "$0")/.."
[ -x ./gradlew ] || { echo "Error: ./gradlew not found, run from inside the ksat-extra checkout." >&2; exit 1; }

PLAYGROUND=playground/build/dist/js/productionExecutable
SITE=build/pages

./gradlew :playground:jsBrowserDistribution
for f in "$PLAYGROUND/index.html" "$PLAYGROUND/playground-worker.js"; do
    [ -f "$f" ] || { echo "Error: build finished but $f is missing." >&2; exit 1; }
done

rm -rf "$SITE"
mkdir -p "$SITE"
cp -R "$PLAYGROUND"/. "$SITE"/

echo "Website built: $SITE/ (the playground)"
