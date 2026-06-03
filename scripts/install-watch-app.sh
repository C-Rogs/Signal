#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/Signal"
IPHONE_ID="${SIGNAL_IPHONE_DEVICE_ID:-3E68EF63-F6E7-555E-8A58-71D2DBAF88C9}"
WATCH_ID="${SIGNAL_WATCH_DEVICE_ID:-A8077392-5F1A-5A0A-90F8-641502715165}"
DERIVED_DATA="${SIGNAL_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Signal-czzvpnqthoxgecbadvgkpmiwedwz}"

WATCH_APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/Signal.app/Watch/SignalWatch Watch App.app"

cd "$PROJECT_DIR"

echo "Building Signal for iPhone (embeds watch app)..."
xcodebuild -scheme Signal \
  -destination "platform=iOS,id=${IPHONE_ID}" \
  build

if [[ ! -d "$WATCH_APP" ]]; then
  echo "Missing embedded watch app at:"
  echo "  $WATCH_APP"
  echo "Set SIGNAL_DERIVED_DATA if your DerivedData path differs."
  exit 1
fi

echo "Installing watch app to paired Apple Watch..."
xcrun devicectl device install app --device "$WATCH_ID" "$WATCH_APP"

echo "Done. Open SignalWatch on your watch, then open Signal Dashboard on iPhone to sync recovery."
