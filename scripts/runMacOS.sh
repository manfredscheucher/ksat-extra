#!/usr/bin/env bash
# Run the ksat demo as a native macOS console executable (Kotlin/Native).
# macOS host only; auto-picks the arch of this Mac (arm64 -> MacosArm64, x86_64 -> MacosX64).
set -e
cd "$(dirname "$0")/.."

case "$(uname -s)" in
    Darwin) ;;  # macOS — OK
    *) echo "runMacOS.sh needs a macOS host (Kotlin/Native macos* can't cross-build here)." >&2
       echo "Current system: $(uname -s)." >&2
       exit 1 ;;
esac

case "$(uname -m)" in
    arm64)  TARGET=MacosArm64 ;;
    x86_64) TARGET=MacosX64 ;;
    *) echo "Unknown Mac arch: $(uname -m)" >&2; exit 1 ;;
esac

exec ./gradlew ":demo:runDebugExecutable${TARGET}" -q "$@"
