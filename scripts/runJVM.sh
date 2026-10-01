#!/usr/bin/env bash
# Run the ksat demo on the JVM (console). The demo enumerates all models of XOR(x1,x2)
# and ends in UNSAT. Works everywhere a JDK is present.
set -e
cd "$(dirname "$0")/.."
[ -x ./gradlew ] || { echo "Error: ./gradlew not found — run from inside the ksat-extra checkout." >&2; exit 1; }
exec ./gradlew :demo:runJvm -q "$@"
