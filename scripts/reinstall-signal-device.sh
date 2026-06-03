#!/usr/bin/env bash
set -euo pipefail

# Full device reinstall without Xcode Run to watch.
# 1. Builds Signal for iPhone (embeds watch app + widget extension).
# 2. Installs Signal.app on iPhone (registers companion with iOS).
# 3. Installs SignalWatch Watch App.app on the paired watch.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/Signal"
IPHONE_ID="${SIGNAL_IPHONE_DEVICE_ID:-3E68EF63-F6E7-555E-8A58-71D2DBAF88C9}"
WATCH_ID="${SIGNAL_WATCH_DEVICE_ID:-A8077392-5F1A-5A0A-90F8-641502715165}"
DERIVED_DATA="${SIGNAL_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Signal-czzvpnqthoxgecbadvgkpmiwedwz}"

IPHONE_APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/Signal.app"
WATCH_APP="$IPHONE_APP/Watch/SignalWatch Watch App.app"

cd "$PROJECT_DIR"

echo "Building Signal for iPhone (embeds watch app + widget extension)..."
xcodebuild -scheme Signal \
  -destination "platform=iOS,id=${IPHONE_ID}" \
  build

if [[ ! -d "$IPHONE_APP" ]]; then
  echo "Missing iPhone app at: $IPHONE_APP"
  exit 1
fi

if [[ ! -d "$WATCH_APP" ]]; then
  echo "Missing embedded watch app at: $WATCH_APP"
  exit 1
fi

if [[ -d "$WATCH_APP/PlugIns/SignalWatch Widget ExtensionExtension.appex" ]]; then
  echo "Widget extension embedded in watch app: OK"
else
  echo "WARNING: Widget extension .appex not found in watch app bundle."
  echo "  Complication will show ! until the extension is embedded."
fi

echo "Installing Signal on iPhone..."
xcrun devicectl device install app --device "$IPHONE_ID" "$IPHONE_APP"

echo "Installing SignalWatch on Apple Watch..."
xcrun devicectl device install app --device "$WATCH_ID" "$WATCH_APP"

cat <<'EOF'

Install complete. On device (no Xcode required):

1. iPhone: open Watch app → My Watch → confirm Signal is installed on watch.
2. iPhone: open Signal → Dashboard → pull to refresh.
3. Watch: open SignalWatch once (should show your score).
4. Watch face: remove the old Recovery complication, then add it again.
5. Use a round (circular) slot; pick Recovery under SignalWatch Widget Extension.

If you still see ! on the complication, the widget extension crashed or is unsigned.
Reboot the watch, then repeat steps 2–4.

EOF
