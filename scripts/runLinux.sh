#!/usr/bin/env bash
# Run the ksat demo as a native Linux console executable (Kotlin/Native, x86_64).
# Builds only on a Linux host (native Linux, or Windows via WSL) — Kotlin/Native can't
# cross-build linuxX64 from macOS/Windows, where the Gradle task is silently skipped.
set -e
cd "$(dirname "$0")/.."

case "$(uname -s)" in
    Linux) ;;  # native Linux or WSL — OK
    *) echo "runLinux.sh needs a Linux host (Kotlin/Native linuxX64 can't cross-build here)." >&2
       echo "Current system: $(uname -s). On macOS use runMacOS.sh; on Windows run this inside WSL." >&2
       exit 1 ;;
esac

exec ./gradlew :demo:runDebugExecutableLinuxX64 -q "$@"
