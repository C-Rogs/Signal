#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/Signal"
BUILD_SIM_ID="20DDD35B-812A-49BE-9DCF-0685401ACC15"
TEST_SIM_ID="311A9753-3F61-44C8-8BE6-AC7BC69558D4"

export SIGNAL_HEALTH_EXPORT_XML="${SIGNAL_HEALTH_EXPORT_XML:-$ROOT/fixtures/export.xml}"
export SIGNAL_HEVY_CSV="${SIGNAL_HEVY_CSV:-$ROOT/fixtures/HevyExport.csv}"

if [[ ! -f "$SIGNAL_HEALTH_EXPORT_XML" ]]; then
  echo "Missing $SIGNAL_HEALTH_EXPORT_XML"
  exit 1
fi
if [[ ! -f "$SIGNAL_HEVY_CSV" ]]; then
  echo "Missing $SIGNAL_HEVY_CSV"
  exit 1
fi

echo "Health: $SIGNAL_HEALTH_EXPORT_XML ($(du -h "$SIGNAL_HEALTH_EXPORT_XML" | cut -f1))"
echo "Hevy:   $SIGNAL_HEVY_CSV ($(du -h "$SIGNAL_HEVY_CSV" | cut -f1))"
echo ""
echo "Full pipeline test (parse + MLX embed + retrieval). This can take 30-90 minutes on simulator."
echo "Optional faster path: SIGNAL_USE_NL_EMBEDDING=1 $0"
echo ""

(cd "$PROJECT_DIR" && xcodebuild -scheme Signal \
  -destination "platform=iOS Simulator,id=${BUILD_SIM_ID}" \
  build)

(cd "$PROJECT_DIR" && \
  TEST_RUNNER_SIGNAL_HEALTH_EXPORT_XML="$SIGNAL_HEALTH_EXPORT_XML" \
  TEST_RUNNER_SIGNAL_HEVY_CSV="$SIGNAL_HEVY_CSV" \
  xcodebuild -scheme Signal \
  -destination "platform=iOS Simulator,id=${TEST_SIM_ID}" \
  test -only-testing:SignalTests/FullFixturePipelineTests/fullImportPipelineHealthThenHevyWithMLVerification)

echo "Done."
