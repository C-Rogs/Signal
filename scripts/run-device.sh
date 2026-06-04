#!/usr/bin/env bash
set -euo pipefail

# Fast iPhone deploy: build (optional), install, launch. No unit tests, no watch reinstall.
# SKIP_BUILD=1 reuses the last Debug-iphoneos app (fast smoke test).
# Full watch reinstall: ./scripts/reinstall-signal-device.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/Signal"
IPHONE_ID="${SIGNAL_IPHONE_DEVICE_ID:-3E68EF63-F6E7-555E-8A58-71D2DBAF88C9}"
DERIVED_DATA="${SIGNAL_DERIVED_DATA:-$ROOT/.derivedDataDevice}"
IPHONE_APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/Signal.app"
BUNDLE_ID="com.cameronro.Signal"

cd "$PROJECT_DIR"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "Building Signal for iPhone (Debug-iphoneos)..."
  xcodebuild -scheme Signal \
    -destination "platform=iOS,id=${IPHONE_ID}" \
    -derivedDataPath "$DERIVED_DATA" \
    build
else
  echo "SKIP_BUILD=1: using existing app at $IPHONE_APP"
fi

if [[ ! -d "$IPHONE_APP" ]]; then
  echo "Missing app bundle. Run without SKIP_BUILD=1 first."
  exit 1
fi

echo "Installing on iPhone ($IPHONE_ID)..."
xcrun devicectl device install app --device "$IPHONE_ID" "$IPHONE_APP"

echo "Launching $BUNDLE_ID..."
xcrun devicectl device process launch --device "$IPHONE_ID" "$BUNDLE_ID"

echo "Done. iPhone should show Signal."
