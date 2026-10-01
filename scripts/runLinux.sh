#!/usr/bin/env bash
# Run the ksat demo as a native Linux console executable (Kotlin/Native, x86_64).
set -e
cd "$(dirname "$0")/.."
exec ./gradlew :demo:runDebugExecutableLinuxX64 -q "$@"
