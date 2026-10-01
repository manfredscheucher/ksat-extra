#!/usr/bin/env bash
# Run the ksat demo as a native macOS console executable (Kotlin/Native, Apple Silicon).
# For Intel Macs, swap MacosArm64 -> MacosX64.
set -e
cd "$(dirname "$0")/.."
exec ./gradlew :demo:runDebugExecutableMacosArm64 -q "$@"
