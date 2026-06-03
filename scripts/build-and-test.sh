#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/Signal"
# Single pinned sim: iPhone 16 Pro (matches app + test deployment target 26.0).
SIM_ID="20DDD35B-812A-49BE-9DCF-0685401ACC15"
# Physical iPhone 16 Pro for real HealthKit, background, Train, and Watch gates.
DEVICE_ID="00008140-001E34E10A01801C"

cd "$PROJECT_DIR"

DEST="platform=iOS Simulator,id=${SIM_ID}"

echo "Building Signal (iPhone 16 Pro sim)..."
xcodebuild -scheme Signal -destination "$DEST" build

echo "Running SignalTests (same sim, NL embedding, excluding full import integration)..."
SIGNAL_USE_NL_EMBEDDING=1 xcodebuild -scheme Signal \
  -destination "$DEST" \
  test -only-testing:SignalTests \
  -skip-testing:SignalTests/FullImportIntegrationTests

echo "Running full import integration tests (serialized)..."
xcodebuild -scheme Signal \
  -destination "$DEST" \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  test -only-testing:SignalTests/FullImportIntegrationTests

echo "Done."
echo ""
echo "Device install/launch: XcodeBuildMCP build_device -> install_app -> launch_app on id=${DEVICE_ID}"
