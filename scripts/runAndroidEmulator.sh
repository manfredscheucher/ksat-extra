#!/usr/bin/env bash
# Build, install and launch the ksat demo on a running Android emulator.
# Picks the running emulator automatically (adb serial emulator-XXXX). Start one first
# (Android Studio, or `emulator -avd <name>`). If several are running, pass the serial:
#   ./scripts/runAndroidEmulator.sh <serial>
set -e
cd "$(dirname "$0")/.."

ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
[ -x "$ADB" ] || ADB="$(command -v adb)"
[ -n "$ADB" ] || { echo "adb not found; set ANDROID_HOME" >&2; exit 1; }

# Emulators = adb serials in 'device' state matching emulator-XXXX.
mapfile -t EMUS < <("$ADB" devices | awk '$2=="device" && $1 ~ /^emulator-/ {print $1}')

SERIAL="${1:-}"
if [ -z "$SERIAL" ]; then
    case "${#EMUS[@]}" in
        0) echo "No running emulator. Start one first (Android Studio or 'emulator -avd <name>')." >&2; exit 1 ;;
        1) SERIAL="${EMUS[0]}" ;;
        *) echo "Multiple emulators: ${EMUS[*]}" >&2
           echo "Pass one: ./scripts/runAndroidEmulator.sh <serial>" >&2; exit 1 ;;
    esac
fi

echo "Emulator: $SERIAL"
./gradlew :demo:installDebug
"$ADB" -s "$SERIAL" shell am start -n org.bytefred.ksat.demo/.MainActivity
echo "Launched 'ksat demo' on $SERIAL."
