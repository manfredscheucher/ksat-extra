#!/usr/bin/env bash
# Build and run the ksat demo on the iOS Simulator (macOS + Xcode only).
# The demo is a Kotlin/Native framework consumed by a tiny SwiftUI app in demo/iosApp/;
# Xcode's build phase calls ./gradlew :demo:embedAndSignAppleFrameworkForXcode to build it.
# Usage:
#   ./scripts/runIosSimulator.sh                   # first available iPhone simulator
#   ./scripts/runIosSimulator.sh "iPhone 16 Pro"   # a specific simulator by name
set -e
cd "$(dirname "$0")/.."

case "$(uname -s)" in
    Darwin) ;;
    *) echo "runIosSimulator.sh needs a macOS host with Xcode." >&2
       echo "Current system: $(uname -s)." >&2; exit 1 ;;
esac
command -v xcodebuild >/dev/null 2>&1 || { echo "Error: xcodebuild not found (install Xcode)." >&2; exit 1; }
[ -x ./gradlew ] || { echo "Error: ./gradlew not found — run from inside the ksat-extra checkout." >&2; exit 1; }

PROJECT="demo/iosApp/iosApp.xcodeproj"
SCHEME="iosApp"
APP_ID="org.bytefred.ksat.demo"
DERIVED="demo/iosApp/DerivedData"
[ -d "$PROJECT" ] || { echo "Error: $PROJECT not found." >&2; exit 1; }

SIM_NAME="${1:-}"
# Pick a simulator: a booted iPhone, else the named one, else the first available iPhone.
if [ -n "$SIM_NAME" ]; then
    SIM_UDID="$(xcrun simctl list devices available | grep -F "$SIM_NAME" | grep -oE '[0-9A-F-]{36}' | head -1)"
else
    SIM_UDID="$(xcrun simctl list devices | grep -i iphone | grep '(Booted)' | grep -oE '[0-9A-F-]{36}' | head -1)"
    [ -n "$SIM_UDID" ] || SIM_UDID="$(xcrun simctl list devices available | grep -i iphone | grep -oE '[0-9A-F-]{36}' | head -1)"
fi
[ -n "$SIM_UDID" ] || { echo "Error: no iPhone simulator found. Create one in Xcode > Settings > Platforms." >&2; exit 1; }
echo "Simulator: $SIM_UDID"

echo "Building (xcodebuild, iphonesimulator)..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -sdk iphonesimulator -destination "id=$SIM_UDID" -derivedDataPath "$DERIVED" build

APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/ksatdemo.app"
[ -d "$APP_PATH" ] || { echo "Error: built app not found at $APP_PATH." >&2; exit 1; }

echo "Booting simulator (if needed)..."
xcrun simctl bootstatus "$SIM_UDID" -b >/dev/null 2>&1 || xcrun simctl boot "$SIM_UDID" || true
open -a Simulator || true

echo "Installing..."
xcrun simctl install "$SIM_UDID" "$APP_PATH"
echo "Launching $APP_ID..."
xcrun simctl launch "$SIM_UDID" "$APP_ID" || { sleep 3; xcrun simctl launch "$SIM_UDID" "$APP_ID"; }
echo "Launched 'ksat demo' on the simulator."
