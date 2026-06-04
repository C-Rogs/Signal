#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/Signal"
IPHONE_ID="${SIGNAL_IPHONE_DEVICE_ID:-3E68EF63-F6E7-555E-8A58-71D2DBAF88C9}"
WATCH_ID="${SIGNAL_WATCH_DEVICE_ID:-A8077392-5F1A-5A0A-90F8-641502715165}"
DERIVED_DATA="${SIGNAL_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Signal-czzvpnqthoxgecbadvgkpmiwedwz}"

cd "$PROJECT_DIR"

echo "Building Signal for iPhone (embeds watch app)..."
xcodebuild -scheme Signal \
  -destination "platform=iOS,id=${IPHONE_ID}" \
  build

BUILD_DIR="$(xcodebuild -scheme Signal -destination "platform=iOS,id=${IPHONE_ID}" -showBuildSettings 2>/dev/null | awk -F' = ' '/ TARGET_BUILD_DIR / {print $2; exit}')"
if [[ -z "$BUILD_DIR" ]]; then
  BUILD_DIR="$DERIVED_DATA/Build/Products/Debug-iphoneos"
fi

WATCH_APP="$BUILD_DIR/Signal.app/Watch/SignalWatch Watch App.app"
WATCH_ASSETS_CAR="$WATCH_APP/Assets.car"

if [[ ! -d "$WATCH_APP" ]]; then
  echo "Missing embedded watch app at:"
  echo "  $WATCH_APP"
  echo "Build the Signal scheme to your iPhone (not the watch scheme alone)."
  exit 1
fi

if [[ ! -f "$WATCH_ASSETS_CAR" ]]; then
  echo "Watch app is missing Assets.car (icons were not compiled)."
  echo "Run: ./scripts/generate-watch-app-icons.sh"
  echo "Then Product > Clean Build Folder and build Signal again."
  exit 1
fi

echo "Watch bundle OK: Assets.car present ($(wc -c < "$WATCH_ASSETS_CAR" | tr -d ' ') bytes)"

echo "Removing old watch install (ignore errors if not installed)..."
xcrun devicectl device uninstall app --device "$WATCH_ID" com.cameronro.Signal.watchkitapp 2>/dev/null || true

echo "Installing watch app to paired Apple Watch..."
xcrun devicectl device install app --device "$WATCH_ID" "$WATCH_APP"

echo "Done."
echo "Important: In Xcode, run the Signal scheme to your iPhone, not SignalWatch Watch App alone."
echo "Or use this script after every watch icon change."
