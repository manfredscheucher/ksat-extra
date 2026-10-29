#!/usr/bin/env bash
# Run the ksat playground as a JVM desktop app (Compose's run task).
#
#   ./scripts/runPlaygroundJVM.sh
set -euo pipefail
cd "$(dirname "$0")/.."
[ -x ./gradlew ] || { echo "Error: ./gradlew not found, run from inside the ksat-extra checkout." >&2; exit 1; }

echo "Starting the desktop app (:playground:run) ...  (Ctrl-C to stop)"
exec ./gradlew :playground:run
