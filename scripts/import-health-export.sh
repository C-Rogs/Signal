#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/Signal"
SIM_ID="20DDD35B-812A-49BE-9DCF-0685401ACC15"

EXPORT="${SIGNAL_HEALTH_EXPORT_XML:-$ROOT/fixtures/export.xml}"

if [[ ! -f "$EXPORT" ]]; then
  echo "Missing export.xml."
  echo "  Place it at: $ROOT/fixtures/export.xml"
  echo "  Or set:      SIGNAL_HEALTH_EXPORT_XML=/full/path/to/export.xml"
  exit 1
fi

export SIGNAL_HEALTH_EXPORT_XML="$EXPORT"

echo "Building Signal (simulator)..."
(cd "$PROJECT_DIR" && xcodebuild -scheme Signal \
  -destination "platform=iOS Simulator,id=${SIM_ID}" \
  build)

echo "Running full health import test against:"
echo "  $EXPORT"
echo ""
echo "Optional: SIGNAL_USE_NL_EMBEDDING=1 for faster NL embeddings on simulator."
echo ""

(cd "$PROJECT_DIR" && \
  TEST_RUNNER_SIGNAL_HEALTH_EXPORT_XML="$SIGNAL_HEALTH_EXPORT_XML" \
  xcodebuild -scheme Signal \
  -destination "platform=iOS Simulator,id=${SIM_ID}" \
  test -only-testing:SignalTests/FullHealthExportImportTests/fullAppleHealthExportImport)

echo "Done."
