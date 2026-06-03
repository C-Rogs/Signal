#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/Signal"
BUILD_SIM_ID="20DDD35B-812A-49BE-9DCF-0685401ACC15"
# SignalTests stays on iPhone 17 / iOS 26.5 until its deployment target matches the app (26.4 build sim).
TEST_SIM_ID="311A9753-3F61-44C8-8BE6-AC7BC69558D4"
# Real app runs and M2 manual gates: XcodeBuildMCP build_device + install_app + launch_app on id=H3XLDTHR74 (unlocked, DDI mounted).
DEVICE_ID="H3XLDTHR74"

cd "$PROJECT_DIR"

echo "Building Signal (iPhone 16 Pro, pinned id)..."
xcodebuild -scheme Signal \
  -destination "platform=iOS Simulator,id=${BUILD_SIM_ID}" \
  build

echo "Running SignalTests (iPhone 17, NL embedding, excluding full import integration)..."
SIGNAL_USE_NL_EMBEDDING=1 xcodebuild -scheme Signal \
  -destination "platform=iOS Simulator,id=${TEST_SIM_ID}" \
  test -only-testing:SignalTests \
  -skip-testing:SignalTests/FullImportIntegrationTests

echo "Running full import integration tests (serialized, deterministic embed on simulator)..."
xcodebuild -scheme Signal \
  -destination "platform=iOS Simulator,id=${TEST_SIM_ID}" \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  test -only-testing:SignalTests/FullImportIntegrationTests

echo "Done."
echo ""
echo "Device install/launch (manual gates, not xcodebuild): use XcodeBuildMCP on device id=${DEVICE_ID}"
echo "  build_device -> install_app -> launch_app"
