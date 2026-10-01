#!/usr/bin/env bash
# Run the ksat demo in the browser (Kotlin/JS). Opens a dev server and shows the
# model enumeration on the page. For the WebAssembly build use :demo:wasmJsBrowserDevelopmentRun.
set -e
cd "$(dirname "$0")/.."
exec ./gradlew :demo:jsBrowserDevelopmentRun "$@"
