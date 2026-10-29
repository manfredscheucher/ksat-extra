#!/usr/bin/env bash
# Run the ksat playground in the browser (Kotlin/JS) via the Gradle webpack dev-server, then open
# Chrome on it. The solver runs in a Web Worker.
#
#   ./scripts/runPlaygroundWeb.sh               # serve on :8609, open Chrome
#   NO_CHROME=1 ./scripts/runPlaygroundWeb.sh   # serve only, open the URL yourself
#
# Port: 8609 (set in playground/webpack.config.d/watch.js; see ~/github/.dev-ports.md).
# Change it in BOTH that file and the PORT= line below if ever needed.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -x ./gradlew ] || { echo "Error: ./gradlew not found, run from inside the ksat-extra checkout." >&2; exit 1; }

PORT=8609
URL="http://localhost:$PORT/"
CHROME="${CHROME_PATH:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
TASK=":playground:jsBrowserDevelopmentRun"
LOG="${TMPDIR:-/tmp}/ksat-playground-runweb.log"

if curl -sf -o /dev/null "$URL"; then
    echo "Error: port $PORT is already in use (another dev-server running?)." >&2; exit 1
fi

echo "Starting Gradle dev-server ($TASK) ...  logs: $LOG   (Ctrl-C to stop)"
./gradlew "$TASK" >"$LOG" 2>&1 &
GRADLE_PID=$!
cleanup() { kill "$GRADLE_PID" 2>/dev/null || true; }
trap cleanup EXIT

# Wait for the dev-server to accept connections (a cold Gradle build can take a few minutes).
printf 'waiting for %s ' "$URL"
UP=false
for _ in $(seq 1 600); do
    if curl -sf -o /dev/null "$URL"; then UP=true; echo " up"; break; fi
    if ! kill -0 "$GRADLE_PID" 2>/dev/null; then
        echo; echo "Error: Gradle exited early, see $LOG" >&2; tail -20 "$LOG" >&2; exit 1
    fi
    printf .; sleep 0.5
done
[ "$UP" = true ] || { echo; echo "Error: dev-server did not come up within 5 minutes, see $LOG" >&2; exit 1; }

if [ -z "${NO_CHROME:-}" ]; then
    if [ -x "$CHROME" ]; then
        "$CHROME" --new-window "$URL" >/dev/null 2>&1 &
    elif command -v google-chrome >/dev/null 2>&1; then
        google-chrome --new-window "$URL" >/dev/null 2>&1 &
    else
        echo "Chrome not found, open manually: $URL" >&2
    fi
fi

wait "$GRADLE_PID"
