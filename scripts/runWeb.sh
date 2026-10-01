#!/usr/bin/env bash
# Run the ksat demo in the browser (Kotlin/JS). Starts a blocking dev server and opens a
# browser showing the model enumeration. Works on any host with a JDK.
set -e
cd "$(dirname "$0")/.."
[ -x ./gradlew ] || { echo "Error: ./gradlew not found — run from inside the ksat-extra checkout." >&2; exit 1; }
echo "Starting Kotlin/JS dev server (blocking). It opens a browser; press Ctrl-C to stop." >&2
echo "For the WebAssembly build: ./gradlew :demo:wasmJsBrowserDevelopmentRun" >&2
exec ./gradlew :demo:jsBrowserDevelopmentRun "$@"
