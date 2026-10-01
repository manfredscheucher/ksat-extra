#!/usr/bin/env bash
# Build, install and launch the ksat demo on a running Android emulator.
# Picks the running emulator automatically (adb serial emulator-XXXX). Start one first
# (Android Studio, or `emulator -avd <name>`). If several are running, pass the serial:
#   ./scripts/runAndroidEmulator.sh <serial>
set -e
cd "$(dirname "$0")/.."
[ -x ./gradlew ] || { echo "Error: ./gradlew not found — run from inside the ksat-extra checkout." >&2; exit 1; }

ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
[ -x "$ADB" ] || ADB="$(command -v adb)"
[ -n "$ADB" ] || { echo "adb not found; set ANDROID_HOME" >&2; exit 1; }

# Emulators = adb serials in 'device' state matching emulator-XXXX.
# (newline-separated list; avoid bash-4 'mapfile' so this runs on macOS's bash 3.2)
EMUS="$("$ADB" devices | awk '$2=="device" && $1 ~ /^emulator-/ {print $1}')"
# Count lines with wc (always exits 0; grep -c returns 1 on zero matches and would trip set -e).
if [ -z "$EMUS" ]; then COUNT=0; else COUNT="$(printf '%s\n' "$EMUS" | wc -l | tr -d ' ')"; fi

SERIAL="${1:-}"
if [ -z "$SERIAL" ]; then
    case "$COUNT" in
        0) echo "No running emulator. Start one first (Android Studio or 'emulator -avd <name>')." >&2; exit 1 ;;
        1) SERIAL="$EMUS" ;;
        *) echo "Multiple emulators:" >&2; echo "$EMUS" >&2
           echo "Pass one: ./scripts/runAndroidEmulator.sh <serial>" >&2; exit 1 ;;
    esac
fi

echo "Emulator: $SERIAL"
# Pin install to the chosen serial (adb/Gradle honor ANDROID_SERIAL) so install and launch
# target the same device.
ANDROID_SERIAL="$SERIAL" ./gradlew :demo:installDebug
# am start prints "Error:" on stdout but exits 0, so check its output explicitly.
START_OUT="$("$ADB" -s "$SERIAL" shell am start -n org.bytefred.ksat.demo/.MainActivity 2>&1)"
echo "$START_OUT"
case "$START_OUT" in
    *Error*|*Exception*) echo "Error: failed to launch the app on $SERIAL." >&2; exit 1 ;;
esac
echo "Launched 'ksat demo' on $SERIAL."
