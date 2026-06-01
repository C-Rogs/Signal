#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/Signal"
BUILD_SIM_ID="20DDD35B-812A-49BE-9DCF-0685401ACC15"
TEST_SIM_ID="311A9753-3F61-44C8-8BE6-AC7BC69558D4"

cd "$PROJECT_DIR"

echo "Building Signal (iPhone 16 Pro, pinned id)..."
xcodebuild -scheme Signal \
  -destination "platform=iOS Simulator,id=${BUILD_SIM_ID}" \
  build

echo "Running SignalTests (iPhone 17, iOS 26.5 test target)..."
xcodebuild -scheme Signal \
  -destination "platform=iOS Simulator,id=${TEST_SIM_ID}" \
  test -only-testing:SignalTests

echo "Done."
