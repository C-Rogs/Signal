#!/usr/bin/env bash
set -euo pipefail

# Archive Signal for TestFlight and upload to App Store Connect.
#
# One-time setup (human, in browser + Xcode):
#   1. developer.apple.com: confirm team SXWJBD2V3V has an active paid membership.
#   2. developer.apple.com > Identifiers: register bundle IDs (if missing):
#        com.cameronro.Signal
#        com.cameronro.Signal.watchkitapp
#        com.cameronro.Signal.watchkitapp.SignalWatch-Widget-Extension
#        com.cameronro.Signal.SignalWidget
#        App Group: group.com.cameronro.signal
#      Enable HealthKit + App Groups on the iOS and watch identifiers.
#   3. appstoreconnect.apple.com > Apps > + : create app "Signal"
#        bundle ID com.cameronro.Signal, SKU signal-ios, category Health & Fitness.
#   4. Xcode > Settings > Accounts > SXWJBD2V3V > Manage Certificates:
#        add "Apple Distribution" if missing.
#   5. App Store Connect > App Privacy: declare Health & Fitness data (on device only).
#
# Usage:
#   ./scripts/testflight.sh archive          # build Release .xcarchive
#   ./scripts/testflight.sh export           # export + upload (needs ASC app + Distribution cert)
#   ./scripts/testflight.sh archive export   # both

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Signal/Signal.xcodeproj"
SCHEME="Signal"
TEAM="SXWJBD2V3V"
ARCHIVE_DIR="$ROOT/.build/testflight"
ARCHIVE_PATH="$ARCHIVE_DIR/Signal.xcarchive"
EXPORT_PATH="$ARCHIVE_DIR/export"
EXPORT_PLIST="$ROOT/scripts/ExportOptions.plist"
DERIVED_DATA="$ROOT/.derivedDataArchive"

do_archive() {
  echo "Archiving $SCHEME (Release)..."
  mkdir -p "$ARCHIVE_DIR"
  xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM" \
    -allowProvisioningUpdates

  echo "Archive: $ARCHIVE_PATH"
  codesign -dv "$ARCHIVE_PATH/Products/Applications/Signal.app" 2>&1 | grep -E "Authority|Identifier" || true
}

do_export() {
  if [[ ! -d "$ARCHIVE_PATH" ]]; then
    echo "No archive at $ARCHIVE_PATH. Run: $0 archive" >&2
    exit 1
  fi

  rm -rf "$EXPORT_PATH"
  mkdir -p "$EXPORT_PATH"

  echo "Exporting and uploading to App Store Connect..."
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -allowProvisioningUpdates

  echo "Upload finished. Open App Store Connect > TestFlight to add testers."
  echo "https://appstoreconnect.apple.com/apps"
}

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 archive [export]" >&2
  exit 1
fi

for step in "$@"; do
  case "$step" in
    archive) do_archive ;;
    export)  do_export ;;
    *)
      echo "Unknown step: $step (use archive and/or export)" >&2
      exit 1
      ;;
  esac
done
