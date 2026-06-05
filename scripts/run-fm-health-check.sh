#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/Signal"
DEVICE_ID="00008140-001E34E10A01801C"
ONLY_TESTING="SignalTests/FoundationModelsHealthDeviceTests"

cd "$PROJECT_DIR"

DEST="platform=iOS,id=${DEVICE_ID}"

echo "Building Signal for device ${DEVICE_ID}..."
xcodebuild -scheme Signal -destination "$DEST" build

echo "Running Foundation Models health device tests..."
set +e
xcodebuild -scheme Signal \
  -destination "$DEST" \
  -parallel-testing-enabled NO \
  test -only-testing:"${ONLY_TESTING}" \
  2>&1 | tee /tmp/signal-fm-health-test.log
TEST_EXIT=${PIPESTATUS[0]}
set -e

XCRESULT_PATH="$(ls -td ~/Library/Developer/Xcode/DerivedData/Signal-*/Logs/Test/*.xcresult 2>/dev/null | head -1 || true)"

if [[ -n "${XCRESULT_PATH}" && -d "${XCRESULT_PATH}" ]]; then
  echo ""
  echo "Latest xcresult: ${XCRESULT_PATH}"
  if command -v xcrun >/dev/null 2>&1; then
    xcrun xcresulttool get test-results summary --path "${XCRESULT_PATH}" 2>/dev/null || true
  fi
fi

echo ""
echo "Optional: stream fm_health_report logs while the device test runs:"
echo "  log stream --device --predicate 'subsystem == \"com.cameronro.Signal\" AND category == \"coach\"' | grep fm_health_report"

if [[ "${TEST_EXIT}" -ne 0 ]]; then
  echo "FM health device tests failed with exit code ${TEST_EXIT}" >&2
  exit "${TEST_EXIT}"
fi

echo "FM health device tests passed."
