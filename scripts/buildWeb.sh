#!/usr/bin/env bash
# Build the static production website of the ksat demo (Kotlin/JS bundle + index.html).
# Output: demo/build/dist/js/productionExecutable/
#
#   ./scripts/buildWeb.sh
set -euo pipefail
cd "$(dirname "$0")/.."
[ -x ./gradlew ] || { echo "Error: ./gradlew not found, run from inside the ksat-extra checkout." >&2; exit 1; }

./gradlew :demo:jsBrowserDistribution
[ -f demo/build/dist/js/productionExecutable/index.html ] \
    || { echo "Error: build finished but demo/build/dist/js/productionExecutable/index.html is missing." >&2; exit 1; }
echo "Website built: demo/build/dist/js/productionExecutable/"
