#!/usr/bin/env bash
# Build, install and launch the ksat demo on a physically connected Android device.
# Picks the attached device automatically (any adb serial that is NOT an emulator-XXXX),
# so no hard-coded device id. If several physical devices are attached, pass the serial:
#   ./scripts/runAndroidDevice.sh <serial>
set -e
cd "$(dirname "$0")/.."

ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
[ -x "$ADB" ] || ADB="$(command -v adb)"
[ -n "$ADB" ] || { echo "adb not found; set ANDROID_HOME" >&2; exit 1; }

# Physical devices = adb serials in 'device' state that are NOT emulators.
mapfile -t PHYS < <("$ADB" devices | awk '$2=="device" && $1 !~ /^emulator-/ {print $1}')

SERIAL="${1:-}"
if [ -z "$SERIAL" ]; then
    case "${#PHYS[@]}" in
        0) echo "No physical device attached (only emulators or none). Plug one in + enable USB debugging." >&2; exit 1 ;;
        1) SERIAL="${PHYS[0]}" ;;
        *) echo "Multiple physical devices: ${PHYS[*]}" >&2
           echo "Pass one: ./scripts/runAndroidDevice.sh <serial>" >&2; exit 1 ;;
    esac
fi

echo "Device: $SERIAL"
./gradlew :demo:installDebug
"$ADB" -s "$SERIAL" shell am start -n org.bytefred.ksat.demo/.MainActivity
echo "Launched 'ksat demo' on $SERIAL."
