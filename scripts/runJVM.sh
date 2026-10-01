#!/usr/bin/env bash
# Run the ksat demo on the JVM (console). The demo enumerates all models of XOR(x1,x2)
# and ends in UNSAT. Works everywhere a JDK is present.
set -e
cd "$(dirname "$0")/.."
exec ./gradlew :demo:runJvm -q "$@"
