#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/Signal"
# watchOS 26.5 (matches WATCHOS_DEPLOYMENT_TARGET). Pair host is chosen by Xcode.
WATCH_SIM_ID="93C9FE74-661C-43E7-BCEE-644772C166F4"

cd "$PROJECT_DIR"

DEST="platform=watchOS Simulator,id=${WATCH_SIM_ID}"

echo "Building SignalWatch Watch App (watchOS sim compile gate)..."
xcodebuild -scheme "SignalWatch Watch App" -destination "$DEST" build

echo "Running SignalWatch Watch AppTests (hosted on paired iPhone sim)..."
xcodebuild -scheme "SignalWatch Watch App" \
  -destination "$DEST" \
  test -only-testing:"SignalWatch Watch AppTests"

echo "Done."
